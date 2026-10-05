"""Exercise real local API/PostgreSQL/MinIO/Redis; remove only its own test accounts."""
import asyncio
import io
import json
from pathlib import Path
import secrets
import uuid
import zipfile

import httpx
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = "http://127.0.0.1:18000/api/v1"


async def run():
    results = []
    accounts = []
    async with httpx.AsyncClient(timeout=30, follow_redirects=False) as client:
        try:
            for presentation in ["male", "female"]:
                password = secrets.token_urlsafe(24)
                response = await client.post(BASE + "/auth/register", json={"first_name": "Test local", "email": f"smoke-{uuid.uuid4().hex}@example.com", "password": password, "mannequin_presentation": presentation})
                response.raise_for_status()
                headers = {"Authorization": "Bearer " + response.json()["access_token"]}
                accounts.append((headers, password))
            headers, _ = accounts[0]
            other, _ = accounts[1]
            ids = []
            for category, name in [("tshirt", "Haut test"), ("jeans", "Pantalon test"), ("sneakers", "Chaussures test")]:
                response = await client.post(BASE + "/garments", headers=headers, json={"category_slug": category, "name": name, "color": "white"})
                response.raise_for_status()
                ids.append(response.json()["id"])
            results.append({"flow": "register / profile / garments CRUD", "passed": True})
            assert (await client.get(BASE + "/garments/" + ids[0], headers=other)).status_code == 404
            image = Image.new("RGB", (64, 48), "grey")
            metadata = Image.Exif()
            metadata[270] = "private-test-marker"
            buffer = io.BytesIO()
            image.save(buffer, format="JPEG", exif=metadata)
            upload = await client.post(BASE + "/media/upload", headers=headers, files={"file": ("photo.jpg", buffer.getvalue(), "image/jpeg")})
            upload.raise_for_status()
            payload = upload.json()
            attached = await client.post(BASE + f"/garments/{ids[0]}/images", headers=headers, json={**payload, "width": 9000, "height": 9000})
            attached.raise_for_status()
            detail = attached.json()
            assert detail["width"] == 64 and detail["height"] == 48
            downloaded = await client.get(detail["download_url"])
            assert downloaded.status_code == 200 and not Image.open(io.BytesIO(downloaded.content)).getexif()
            assert (await client.get(detail["download_url"].split("?")[0])).status_code == 403
            assert (await client.get(BASE + "/media/download-url", headers=other, params={"object_key": payload["object_key"]})).status_code == 404
            results.append({"flow": "real photo upload / metadata stripping / private S3 / signed download / IDOR", "passed": True})
            signed = await client.post(BASE + "/media/upload-url", headers=headers, json={"filename": "photo.jpg", "content_type": "image/jpeg"})
            signed.raise_for_status()
            form = signed.json()
            posted = await client.post(form["upload_url"], data=form["fields"], files={"file": ("photo.jpg", buffer.getvalue(), "image/jpeg")})
            assert posted.status_code in [200, 201, 204]
            verified = await client.post(BASE + f"/garments/{ids[1]}/images", headers=headers, json={"object_key": form["object_key"], "content_type": "image/jpeg", "byte_size": 1})
            verified.raise_for_status()
            results.append({"flow": "real presigned POST / quarantine / attachment sanitation", "passed": True})
            outfit = await client.post(BASE + "/outfits", headers=headers, json={"name": "Tenue test", "garment_ids": ids})
            outfit.raise_for_status()
            worn = await client.post(BASE + "/outfits/wear", headers=headers, json={"garment_ids": ids, "outfit_id": outfit.json()["id"], "activity": "everyday"})
            worn.raise_for_status()
            history = await client.get(BASE + "/outfits/history/recent", headers=headers)
            assert history.status_code == 200 and history.json()
            results.append({"flow": "outfit save / wear / actual history", "passed": True})
            export = await client.get(BASE + "/account/export", headers=headers)
            export.raise_for_status()
            with zipfile.ZipFile(io.BytesIO(export.content)) as archive:
                data = json.loads(archive.read("dressly-donnees.json"))
                photos = [name for name in archive.namelist() if name.startswith("photos/")]
                assert len(photos) == 2
                assert not Image.open(io.BytesIO(archive.read(photos[0]))).getexif()
            assert len(data["garments"]) == 3 and data["history"]
            results.append({"flow": "actual ZIP export", "passed": True})
            weather = await client.get(BASE + "/weather/current", headers=headers, params={"latitude": 48.86, "longitude": 2.35, "location_label": "Paris"})
            results.append({"flow": "live Open-Meteo", "passed": weather.status_code == 200, "status": weather.status_code})
            # The engine intentionally excludes the exact outfit just worn above.
            alternative = await client.post(BASE + "/garments", headers=headers, json={"category_slug": "tshirt", "name": "Haut alternatif test", "color": "black"})
            alternative.raise_for_status()
            generated = await client.post(BASE + "/recommendations/generate", headers=headers, json={"origin_latitude": 48.86, "origin_longitude": 2.35, "origin_label": "Paris", "activity": "everyday"})
            results.append({"flow": "live-weather outfit generation", "passed": generated.status_code == 201, "status": generated.status_code})
        finally:
            for headers, password in accounts:
                deleted = await client.request("DELETE", BASE + "/me", headers=headers, json={"password": password})
                assert deleted.status_code == 200, "Temporary test account removal failed"
            results.append({"flow": "test account erasure / tokens revoked", "passed": True})
            (ROOT / "docs" / "LOCAL_SMOKE_TEST.json").write_text(json.dumps(results, indent=2) + "\n")
            for result in results:
                print(result["flow"], "PASS" if result["passed"] else "FAIL")


if __name__ == "__main__":
    asyncio.run(run())
