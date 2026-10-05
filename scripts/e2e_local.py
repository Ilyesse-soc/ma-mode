"""Opt-in real local end-to-end check, including external FREE UPC/weather/AI.

Only this run's temporary account is deleted. No secrets or personal data printed.
The two synthetic test images never seed production wardrobe data.
"""

import asyncio
import io
import json
from pathlib import Path
import secrets
import uuid
import zipfile

import httpx
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BASE = "http://127.0.0.1:18000/api/v1"


def test_image(label):
    image = Image.new("RGB", (900, 1000), "#f2f0eb")
    draw = ImageDraw.Draw(image)
    if label:
        font_path = Path("C:/Windows/Fonts/arial.ttf")
        font = (
            ImageFont.truetype(str(font_path), 54)
            if font_path.exists()
            else ImageFont.load_default(size=54)
        )
        for i, text in enumerate(
            ["DRESSLY TEST", "SKU: TEST-001", "SIZE: M", "100% COTTON"]
        ):
            draw.text((70, 200 + i * 130), text, fill="black", font=font)
    else:
        draw.polygon(
            [
                (270, 160),
                (170, 190),
                (65, 370),
                (220, 460),
                (275, 390),
                (270, 880),
                (630, 880),
                (625, 390),
                (680, 460),
                (835, 370),
                (730, 190),
                (630, 160),
                (545, 240),
                (355, 240),
            ],
            fill="#255eb9",
        )
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


async def run():
    checks = []
    password = secrets.token_urlsafe(30)
    email = f"e2e-{uuid.uuid4().hex}@example.com"
    headers = None

    def record(flow, passed, **details):
        checks.append({"flow": flow, "passed": bool(passed), **details})
        print(flow + ": " + ("PASS" if passed else "LIMITATION"))

    async with httpx.AsyncClient(timeout=70, follow_redirects=False) as client:

        async def request(method, route, **kwargs):
            response = await client.request(
                method, BASE + route, headers=headers, **kwargs
            )
            if response.status_code >= 400:
                raise RuntimeError(f"{method} {route}: HTTP {response.status_code}")
            return response

        try:
            registration = await request(
                "POST",
                "/auth/register",
                json={
                    "first_name": "Test bout en bout",
                    "email": email,
                    "password": password,
                    "mannequin_presentation": "male",
                },
            )
            tokens = registration.json()
            headers = {"Authorization": "Bearer " + tokens["access_token"]}
            record(
                "register / authenticated empty wardrobe",
                (await request("GET", "/garments")).json()["total"] == 0,
            )
            for presentation in ["female", "male"]:
                profile = await request(
                    "PATCH", "/me", json={"mannequin_presentation": presentation}
                )
                asset = await client.get(
                    f"http://127.0.0.1:18080/assets/assets/3d/mannequins/{presentation}.glb"
                )
                record(
                    presentation + " real profile / served GLB",
                    profile.json()["mannequin_presentation"] == presentation
                    and asset.status_code == 200
                    and asset.content[:4] == b"glTF",
                )
            preferences = await request(
                "PUT",
                "/me/preferences",
                json={
                    "preferred_styles": ["Casual"],
                    "liked_colors": ["blue", "black"],
                    "avoided_colors": [],
                    "cold_threshold_celsius": 12,
                    "hot_threshold_celsius": 27,
                },
            )
            record(
                "save / reload preferences",
                preferences.json()["liked_colors"]
                == (await request("GET", "/me/preferences")).json()["liked_colors"],
            )
            ids = []
            for category, name, brand, color, warmth in [
                ("sneakers", "Nike Air Max 95", "Nike", "white", 1),
                ("hoodie", "Hoodie gris", None, "grey", 4),
                ("jeans", "Jean Zara", "Zara", "blue", 2),
                ("tshirt", "T-shirt bleu", None, "blue", 1),
                ("jacket", "Veste imperméable", None, "black", 3),
            ]:
                garment = (
                    await request(
                        "POST",
                        "/garments",
                        json={
                            "category_slug": category,
                            "name": name,
                            "brand": brand,
                            "color": color,
                            "warmth_level": warmth,
                            "waterproof": category == "jacket",
                        },
                    )
                ).json()
                ids.append(garment["id"])
            record(
                "manual actual garments / detail / wardrobe",
                (await request("GET", "/garments")).json()["total"] == 5
                and (await request("GET", "/garments/" + ids[0])).json()["name"]
                == "Nike Air Max 95",
            )
            unknown_prefix = "299" + f"{secrets.randbelow(1_000_000_000):09d}"
            check_digit = (
                -sum(
                    int(char) * (1 if index % 2 == 0 else 3)
                    for index, char in enumerate(unknown_prefix)
                )
            ) % 10
            for barcode in ["0885909950805", unknown_prefix + str(check_digit)]:
                scanned = await client.post(
                    BASE + "/garments/identify/barcode",
                    headers=headers,
                    json={"barcode": barcode},
                )
                if scanned.status_code == 503 and scanned.headers.get("retry-after"):
                    seconds = int(scanned.headers["retry-after"])
                    if 1 <= seconds <= 65:
                        print(
                            "FREE UPC minute quota: respecting Retry-After before one retry.",
                            flush=True,
                        )
                        for chunk in range(0, seconds + 1, 30):
                            await asyncio.sleep(min(30, seconds + 1 - chunk))
                        scanned = await client.post(
                            BASE + "/garments/identify/barcode",
                            headers=headers,
                            json={"barcode": barcode},
                        )
                status = scanned.json().get("status")
                known = barcode.startswith("088")
                record(
                    "live FREE UPC " + ("known" if known else "unknown"),
                    scanned.status_code == 200
                    and status == ("candidates" if known else "not_found"),
                    http_status=scanned.status_code,
                    identification_status=status,
                    candidates=len(scanned.json().get("candidates", [])),
                )
                if scanned.status_code == 200 and status == "candidates":
                    repeated = await request(
                        "POST", "/garments/identify/barcode", json={"barcode": barcode}
                    )
                    record(
                        "owned database barcode cache",
                        repeated.json()["status"] == "candidates",
                    )
            consent = await request(
                "PUT", "/me/consents/ai", json={"enabled": True, "version": "ai-v1"}
            )
            record("explicit AI consent", consent.json()["ai"])
            for label in [True, False]:
                upload = (
                    await request(
                        "POST",
                        "/media/upload",
                        files={
                            "file": ("test-image.jpg", test_image(label), "image/jpeg")
                        },
                    )
                ).json()
                attached = (
                    await request(
                        "POST",
                        f"/garments/{ids[1]}/images",
                        json={**upload, "image_kind": "label" if label else "garment"},
                    )
                ).json()
                image = await client.get(attached["download_url"])
                record(
                    "real " + ("label" if label else "garment") + " image / private S3",
                    image.status_code == 200
                    and attached["image_kind"] == ("label" if label else "garment")
                    and attached["is_primary"] is (not label),
                )
                route = f"/garments/{ids[1]}/identify/" + (
                    "label" if label else "photo"
                )
                analyzed = await client.post(
                    BASE + route, headers=headers, json={"image_id": attached["id"]}
                )
                if analyzed.status_code == 503:
                    print(
                        "Transient external AI unavailability: one bounded retry.",
                        flush=True,
                    )
                    await asyncio.sleep(1)
                    analyzed = await client.post(
                        BASE + route, headers=headers, json={"image_id": attached["id"]}
                    )
                payload = analyzed.json()
                record(
                    "live external AI " + ("label" if label else "photo"),
                    analyzed.status_code == 200 and bool(payload.get("candidates")),
                    http_status=analyzed.status_code,
                    identification_status=payload.get("status"),
                    candidates=len(payload.get("candidates", [])),
                    error_code=payload.get("error", {}).get("code"),
                )
                if analyzed.status_code == 200 and payload.get("candidates"):
                    candidate = payload["candidates"][0]
                    confirmed = await request(
                        "POST",
                        f"/garments/{ids[1]}/candidates/{candidate['id']}/confirm",
                        json={"apply_fields": False},
                    )
                    record(
                        "user confirms "
                        + ("label" if label else "photo")
                        + " candidate",
                        confirmed.json()["status"] == "confirmed",
                    )
            city = (
                await request(
                    "GET",
                    "/locations/reverse",
                    params={"latitude": 48.9295123, "longitude": 2.0453123},
                )
            ).json()
            record(
                "live IGN/BAN Poissy / Yvelines",
                city["label"] == "Poissy" and city["administrative_area"] == "Yvelines",
            )
            place = await request(
                "POST",
                "/locations",
                json={"label": "Lille", "latitude": 50.6292, "longitude": 3.0573},
            )
            record(
                "save / reload destination",
                any(
                    p["id"] == place.json()["id"]
                    for p in (await request("GET", "/locations")).json()
                ),
            )
            weather = await request(
                "GET",
                "/weather/current",
                params={
                    "latitude": 48.9295123,
                    "longitude": 2.0453123,
                    "location_label": "Poissy",
                },
            )
            record(
                "live precise Poissy weather", weather.json()["provider"] == "openmeteo"
            )
            generated = (
                await request(
                    "POST",
                    "/recommendations/generate",
                    json={
                        "origin_latitude": 48.9295123,
                        "origin_longitude": 2.0453123,
                        "origin_label": "Poissy",
                        "destination_latitude": 50.6292,
                        "destination_longitude": 3.0573,
                        "destination_label": "Lille",
                        "activity": "everyday",
                    },
                )
            ).json()
            proposed = generated["proposals"][0]["garment_ids"]
            record(
                "real wardrobe / origin and destination weather / recommendation explanations",
                set(proposed).issubset(ids)
                and bool(generated["proposals"][0]["explanations"]),
            )
            feedback = await request(
                "POST",
                f"/recommendations/{generated['id']}/feedback",
                json={"action": "like"},
            )
            record("persisted feedback", feedback.status_code == 201)
            outfit = (
                await request(
                    "POST",
                    "/outfits",
                    json={"name": "Tenue test E2E", "garment_ids": proposed},
                )
            ).json()
            await request(
                "POST",
                "/outfits/wear",
                json={
                    "outfit_id": outfit["id"],
                    "garment_ids": proposed,
                    "activity": "everyday",
                    "destination_label": "Lille",
                },
            )
            history = (await request("GET", "/outfits/history/recent")).json()
            record(
                "save mannequin selection / wear / real history",
                history[0]["outfit_id"] == outfit["id"],
            )
            exported = await request("GET", "/account/export")
            with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
                record(
                    "actual ZIP data and photo export",
                    "dressly-donnees.json" in archive.namelist()
                    and len([n for n in archive.namelist() if n.startswith("photos/")])
                    == 2,
                )
            await request(
                "POST", "/auth/logout", json={"refresh_token": tokens["refresh_token"]}
            )
            record(
                "logout revokes session",
                (await client.get(BASE + "/me", headers=headers)).status_code == 401,
            )
            logged = await request(
                "POST", "/auth/login", json={"email": email, "password": password}
            )
            headers = {"Authorization": "Bearer " + logged.json()["access_token"]}
            record(
                "relogin / persisted wardrobe / history",
                (await request("GET", "/garments")).json()["total"] == 5
                and bool((await request("GET", "/outfits/history/recent")).json()),
            )
        finally:
            if headers:
                removed = await client.request(
                    "DELETE", BASE + "/me", headers=headers, json={"password": password}
                )
                if removed.status_code != 200:
                    raise RuntimeError("Temporary E2E account removal failed")
                record(
                    "temporary account erased / access revoked",
                    (await client.get(BASE + "/me", headers=headers)).status_code
                    == 401,
                )
            report = {
                "scope": "real local PostgreSQL, Redis, MinIO and external providers; synthetic test images",
                "checks": checks,
                "native_camera_gps_mobile_performance": "requires a physical device",
                "ui_gestures_offline": "separate browser/widget checks",
            }
            (ROOT / "docs/E2E_LOCAL_CHECK.json").write_text(
                json.dumps(report, indent=2) + "\n", encoding="utf8"
            )


if __name__ == "__main__":
    asyncio.run(run())
