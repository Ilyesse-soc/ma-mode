"""S3-compatible object storage: presigned uploads/downloads, MIME validation."""

import io
import re
import uuid
import warnings

import boto3
from botocore.config import Config as BotoConfig
from PIL import Image, ImageOps

from app.core.config import get_settings
from app.core.errors import bad_request
from app.core.logging import get_logger

log = get_logger("media")

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}


def _client(public=False):
    settings = get_settings()
    return boto3.client(
        "s3",
        endpoint_url=settings.s3_public_endpoint_url if public else settings.s3_endpoint_url,
        region_name=settings.s3_region,
        aws_access_key_id=settings.s3_access_key,
        aws_secret_access_key=settings.s3_secret_key,
        config=BotoConfig(
            signature_version="s3v4",
            connect_timeout=5,
            read_timeout=15,
            retries={"max_attempts": 2, "mode": "standard"},
        ),
    )


def build_object_key(user_id: uuid.UUID, filename: str) -> str:
    safe_ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "bin"
    if safe_ext not in {"jpg", "jpeg", "png", "webp"}:
        safe_ext = "bin"
    return f"users/{user_id}/{uuid.uuid4().hex}.{safe_ext}"


def validate_object_key(user_id: uuid.UUID, key: str) -> None:
    if not re.fullmatch(
        rf"users/{user_id}/(?:quarantine/|validated/)?[0-9a-f]{{32}}\.(?:jpg|jpeg|png|webp|bin)", key
    ):
        from app.core.errors import not_found

        raise not_found("object")


def read_object(key: str) -> bytes:
    settings = get_settings()
    obj = _client().get_object(Bucket=settings.s3_bucket, Key=key)
    body = obj["Body"]
    try:
        if obj.get("ContentLength", 0) > settings.max_upload_bytes:
            raise bad_request("file_too_large", "Image exceeds maximum size")
        data = body.read(settings.max_upload_bytes + 1)
        if len(data) > settings.max_upload_bytes:
            raise bad_request("file_too_large", "Image exceeds maximum size")
        return data
    finally:
        body.close()


def sanitize_image(data: bytes) -> tuple[bytes, str, int, int]:
    settings = get_settings()
    if not data or len(data) > settings.max_upload_bytes:
        raise bad_request("file_too_large", "Invalid image size")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                if image.format not in {"JPEG", "PNG", "WEBP"}:
                    raise bad_request("unsupported_media_type", "Only JPEG/PNG/WebP supported")
                width, height = image.size
                if (
                    width > settings.max_image_dimension
                    or height > settings.max_image_dimension
                    or width * height > settings.max_image_pixels
                ):
                    raise bad_request("image_dimensions", "Image dimensions exceed policy")
                if getattr(image, "n_frames", 1) != 1:
                    raise bad_request("animated_image", "Animated images are not supported")
                image.load()
                pixels = ImageOps.exif_transpose(image).convert("RGB")
                # Fresh image drops EXIF/GPS, XMP, ICC and comments, not merely the extension.
                clean = Image.frombytes("RGB", pixels.size, pixels.tobytes())
                target = io.BytesIO()
                clean.save(target, format="JPEG", quality=90, optimize=True)
                result = target.getvalue()
                if len(result) > settings.max_upload_bytes:
                    raise bad_request("file_too_large", "Sanitized image exceeds policy")
                return result, "image/jpeg", clean.width, clean.height
    except (OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise bad_request("invalid_image", "Uploaded file is not a valid image") from None


def create_presigned_upload(object_key: str, content_type: str) -> dict:
    """Presigned multipart POST: S3 enforces the size policy before storage."""
    settings = get_settings()
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise bad_request("unsupported_media_type", f"Allowed: {sorted(ALLOWED_CONTENT_TYPES)}")
    client = _client(public=True)
    temporary_tag = "<Tagging><TagSet><Tag><Key>temporary</Key><Value>true</Value></Tag></TagSet></Tagging>"
    signed = client.generate_presigned_post(
        Bucket=settings.s3_bucket,
        Key=object_key,
        Fields={"Content-Type": content_type, "tagging": temporary_tag},
        Conditions=[
            {"Content-Type": content_type},
            {"tagging": temporary_tag},
            ["content-length-range", 1, settings.max_upload_bytes],
        ],
        ExpiresIn=settings.s3_presign_ttl_seconds,
    )
    return {
        "upload_url": signed["url"],
        "method": "POST",
        "fields": signed["fields"],
        "object_key": object_key,
        "content_type": content_type,
        "max_bytes": settings.max_upload_bytes,
        "headers": {},
    }


def create_presigned_download(object_key: str) -> str:
    settings = get_settings()
    client = _client(public=True)
    return client.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.s3_bucket, "Key": object_key},
        ExpiresIn=settings.s3_presign_ttl_seconds,
    )


def delete_object(object_key: str) -> None:
    settings = get_settings()
    _client().delete_object(Bucket=settings.s3_bucket, Key=object_key)


def ensure_bucket_exists() -> None:
    """Local bootstrap only; never silently accept failed bucket creation."""
    settings = get_settings()
    client = _client()
    try:
        client.head_bucket(Bucket=settings.s3_bucket)
    except client.exceptions.ClientError as exc:
        if exc.response["Error"]["Code"] not in {"404", "NoSuchBucket", "NotFound"}:
            raise
        if settings.is_production:
            raise RuntimeError("Production media bucket must be provisioned") from None
        client.create_bucket(Bucket=settings.s3_bucket)


def verify_private_bucket() -> None:
    """Fail closed on public policies or ACLs, including MinIO-compatible S3."""
    import json

    client = _client()
    bucket = get_settings().s3_bucket
    client.head_bucket(Bucket=bucket)
    try:
        policy = json.loads(client.get_bucket_policy(Bucket=bucket)["Policy"])
    except client.exceptions.ClientError as exc:
        if exc.response["Error"]["Code"] not in {"NoSuchBucketPolicy", "NoSuchPolicy", "404"}:
            raise
    else:
        for statement in policy.get("Statement", []):
            principal = statement.get("Principal")
            if statement.get("Effect") == "Allow" and (
                principal == "*" or (isinstance(principal, dict) and "*" in str(principal.get("AWS", "")))
            ):
                raise RuntimeError("Public media bucket policy prohibited")
    acl = client.get_bucket_acl(Bucket=bucket)
    if any(grant.get("Grantee", {}).get("Type") == "Group" for grant in acl.get("Grants", [])):
        raise RuntimeError("Public media bucket ACL prohibited")


def configure_local_lifecycle() -> None:
    """Temporary quarantined uploads expire; validated photos never expire here."""
    _client().put_bucket_lifecycle_configuration(
        Bucket=get_settings().s3_bucket,
        LifecycleConfiguration={
            "Rules": [
                {
                    "ID": "temporary-quarantine",
                    "Status": "Enabled",
                    "Filter": {"Tag": {"Key": "temporary", "Value": "true"}},
                    "Expiration": {"Days": 1},
                },
            ]
        },
    )


def inspect_image(data: bytes) -> tuple[str, int, int, int]:
    """Validate content and return (content_type, width, height, byte_size).

    Raises ApiError when content is not a valid supported image.
    """
    cleaned, content_type, width, height = sanitize_image(data)
    return content_type, width, height, len(cleaned)
