"""Media routes: presigned upload requests and direct (validated) upload fallback."""

from fastapi import APIRouter, Depends, UploadFile
from pydantic import Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app.core.errors import not_found
from app.core.validation import StrictModel
from app.db.session import get_db
from app.modules.media import storage
from app.modules.media.models import MediaUpload
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User
from app.modules.wardrobe.models import Garment, GarmentImage

router = APIRouter(tags=["media"])


class UploadUrlRequest(StrictModel):
    filename: str = Field(min_length=1, max_length=255)
    content_type: str = Field(min_length=3, max_length=80)


class UploadUrlResponse(StrictModel):
    upload_url: str
    object_key: str
    content_type: str
    max_bytes: int
    headers: dict
    method: str
    fields: dict


@router.post("/media/upload-url", response_model=UploadUrlResponse)
async def request_upload_url(
    payload: UploadUrlRequest, current: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    object_key = storage.build_object_key(current.id, payload.filename).replace(
        f"users/{current.id}/", f"users/{current.id}/quarantine/"
    )
    result = await run_in_threadpool(storage.create_presigned_upload, object_key, payload.content_type)
    db.add(MediaUpload(user_id=current.id, object_key=object_key))
    await db.commit()
    return result


class DirectUploadResponse(StrictModel):
    object_key: str
    content_type: str
    byte_size: int
    width: int
    height: int


@router.post("/media/upload", response_model=DirectUploadResponse)
async def direct_upload(
    file: UploadFile, current: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    """Server-side validated upload (used when presigned flow is unavailable)."""
    data = await file.read(storage.get_settings().max_upload_bytes + 1)
    clean, content_type, width, height = await run_in_threadpool(storage.sanitize_image, data)
    byte_size = len(clean)
    object_key = storage.build_object_key(current.id, "photo.jpg").replace(
        f"users/{current.id}/", f"users/{current.id}/validated/"
    )
    reservation = MediaUpload(user_id=current.id, object_key=object_key)
    db.add(reservation)
    await db.commit()  # Reserve before PUT so a DB failure cannot create an untracked orphan.
    client = storage._client()
    settings = storage.get_settings()
    await run_in_threadpool(
        client.put_object, Bucket=settings.s3_bucket, Key=object_key, Body=clean, ContentType=content_type
    )
    reservation.validated = True
    await db.commit()
    return DirectUploadResponse(
        object_key=object_key,
        content_type=content_type,
        byte_size=byte_size,
        width=width,
        height=height,
    )


@router.get("/media/download-url")
async def download_url(
    object_key: str, current: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    # Ownership: keys are namespaced per user — never sign another user's key.
    storage.validate_object_key(current.id, object_key)
    image = await db.scalar(
        select(GarmentImage)
        .join(Garment)
        .where(GarmentImage.object_key == object_key, Garment.user_id == current.id)
    )
    if image is None:
        raise not_found("object")
    return {"download_url": await run_in_threadpool(storage.create_presigned_download, object_key)}
