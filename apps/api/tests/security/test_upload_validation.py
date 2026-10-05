import io

import pytest
from PIL import Image

from app.core.config import get_settings
from app.core.errors import ApiError
from app.modules.media.storage import sanitize_image
from tests.conftest import BASE, auth, register_user


@pytest.mark.parametrize("data", [b"<script>alert(1)</script>", b"MZexecutable", b"", b"\xff\xd8broken"])
def test_invalid_images_rejected(data):
    with pytest.raises(ApiError):
        sanitize_image(data)


def test_image_exif_and_appended_payload_removed():
    photo = Image.new("RGB", (32, 24), "red")
    exif = Image.Exif()
    exif[270] = "private GPS and prompt injection text"
    buffer = io.BytesIO()
    photo.save(buffer, format="JPEG", exif=exif)
    clean, mime, width, height = sanitize_image(
        buffer.getvalue() + b"<script>malicious trailing payload</script>"
    )
    assert (mime, width, height) == ("image/jpeg", 32, 24)
    assert not Image.open(io.BytesIO(clean)).getexif()
    assert b"private GPS" not in clean and b"<script>" not in clean


def test_dimensions_bounded_before_decode(monkeypatch):
    buffer = io.BytesIO()
    Image.new("RGB", (30, 30)).save(buffer, format="PNG")
    monkeypatch.setattr(get_settings(), "max_image_pixels", 100)
    with pytest.raises(ApiError, match="dimensions"):
        sanitize_image(buffer.getvalue())


async def test_false_jpeg_mime_rejected_without_storage_write(client):
    _, access, _ = await register_user(client)
    response = await client.post(
        f"{BASE}/media/upload",
        headers=auth(access),
        files={"file": ("innocent.jpg", b"<html>executable</html>", "image/jpeg")},
    )
    assert response.status_code == 400
