"""V2 provenance, catalog decisions and fallback ownership contracts."""

import io
import uuid

import pytest
from PIL import Image

from app.db.session import get_session_factory
from app.modules.media.models import MediaUpload
from app.modules.product_search.providers import ProductCandidate
from tests.conftest import BASE, auth, register_user


async def imported(client, monkeypatch, source="file"):
    _, token, _ = await register_user(client)
    headers = auth(token)
    account = (await client.get(f"{BASE}/me", headers=headers)).json()["id"]
    response = await client.post(
        f"{BASE}/garments",
        headers=headers,
        json={"category_slug": "hoodie", "name": "Ma capture", "color": "grey", "is_archived": True},
    )
    identifier = response.json()["id"]
    key = f"users/{account}/quarantine/{uuid.uuid4().hex}.png"
    async with get_session_factory()() as db:
        db.add(MediaUpload(user_id=uuid.UUID(account), object_key=key))
        await db.commit()
    image = io.BytesIO()
    Image.new("RGB", (64, 64), "grey").save(image, format="PNG")
    writes = []

    class Storage:
        def put_object(self, **kwargs):
            writes.append(kwargs)

    monkeypatch.setattr("app.modules.media.storage._client", lambda: Storage())
    monkeypatch.setattr("app.modules.media.storage.read_object", lambda _: image.getvalue())
    monkeypatch.setattr(
        "app.modules.media.storage.create_presigned_download",
        lambda _: "https://example.com/private?signature=test",
    )
    attached = await client.post(
        f"{BASE}/garments/{identifier}/images",
        headers=headers,
        json={
            "object_key": key,
            "content_type": "image/png",
            "byte_size": len(image.getvalue()),
            "source_type": source,
        },
    )
    assert attached.status_code == 201, attached.text
    assert attached.json()["is_primary"] is True
    assert writes[0]["ContentType"] == "image/jpeg"
    return headers, identifier


@pytest.mark.parametrize("source", ["file", "gallery", "screenshot", "imported_image"])
async def test_import_keeps_private_sanitized_image_and_can_save_without_ai(client, monkeypatch, source):
    headers, identifier = await imported(client, monkeypatch, source)
    meta = (await client.get(f"{BASE}/garments/{identifier}", headers=headers)).json()["import_metadata"]
    assert meta["source_type"] == source
    assert "/validated/" in meta["original_image_path"] and "signature" not in str(meta)
    assert meta["exact_match"] is False
    await client.patch(f"{BASE}/garments/{identifier}", headers=headers, json={"is_archived": False})
    result = await client.post(
        f"{BASE}/garments/{identifier}/import/finish", headers=headers, json={"mode": "custom"}
    )
    assert result.status_code == 200
    assert result.json()["import_metadata"]["fallback_mode"] is True
    assert result.json()["import_metadata"]["verified_category"] == "hoodie"
    assert (await client.get(f"{BASE}/garments", headers=headers)).json()["total"] == 1
    _, other, _ = await register_user(client)
    assert (
        await client.post(
            f"{BASE}/garments/{identifier}/import/finish", headers=auth(other), json={"mode": "custom"}
        )
    ).status_code == 404
    assert (
        await client.post(f"{BASE}/garments/{identifier}/import/finish", json={"mode": "custom"})
    ).status_code == 401


async def test_text_catalog_retains_all_candidates_and_never_declares_visual_identity(client, monkeypatch):
    headers, identifier = await imported(client, monkeypatch)
    queries = []

    class Catalog:
        async def search_by_text(self, query):
            queries.append(query)
            return [
                ProductCandidate(
                    name=f"Grey hoodie {n}",
                    brand="Visible",
                    color="grey",
                    source="catalog",
                    images=[f"https://example.com/{n}.jpg"],
                )
                for n in range(3)
            ]

    monkeypatch.setattr(
        "app.modules.product_recognition.identification.get_product_search_providers", lambda: [Catalog()]
    )
    response = await client.post(
        f"{BASE}/garments/{identifier}/identify/refine",
        headers=headers,
        json={"category_slug": "hoodie", "color": "grey", "department": "male"},
    )
    assert response.status_code == 200
    assert "hoodie" in queries[0] and "male" in queries[0]
    catalog = [c for c in response.json()["candidates"] if c["proposed"].get("provider")]
    assert len(catalog) == 3
    chosen = catalog[0]["id"]
    await client.post(
        f"{BASE}/garments/{identifier}/candidates/{chosen}/confirm",
        headers=headers,
        json={"apply_fields": False},
    )
    state = await client.post(
        f"{BASE}/garments/{identifier}/import/finish", headers=headers, json={"mode": "candidate"}
    )
    meta = state.json()["import_metadata"]
    assert meta["candidate_selected"] == chosen and meta["confidence"] == 1
    assert meta["exact_match"] is False and meta["fallback_mode"] is True
    assert meta["search_query_used"] == queries[0]
    assert len(meta["candidates"]) == 4
    await client.post(f"{BASE}/garments/{identifier}/candidates/{chosen}/reject", headers=headers)
    state = (await client.get(f"{BASE}/garments/{identifier}", headers=headers)).json()
    assert state["import_metadata"]["candidate_selected"] is None
    assert state["product_image_url"] is None


async def test_no_catalog_and_unavailable_ai_still_allow_approximate_save(client, monkeypatch):
    headers, identifier = await imported(client, monkeypatch)
    monkeypatch.setattr(
        "app.modules.product_recognition.identification.get_product_search_providers", lambda: []
    )
    result = await client.get(f"{BASE}/garments/{identifier}/identification", headers=headers)
    assert result.json()["status"] == "not_found"
    assert (
        await client.post(
            f"{BASE}/garments/{identifier}/import/finish", headers=headers, json={"mode": "candidate"}
        )
    ).status_code == 409
    from app.modules.product_recognition.providers import AiResponse

    class UnavailableAi:
        async def analyze_garment_photo(self, _):
            return AiResponse(parsed=None, error="unavailable")

    monkeypatch.setattr("app.modules.product_recognition.pipeline.get_ai_provider", lambda: UnavailableAi())
    await client.put(f"{BASE}/me/consents/ai", headers=headers, json={"enabled": True, "version": "ai-v1"})
    image_id = (await client.get(f"{BASE}/garments/{identifier}", headers=headers)).json()["images"][0]["id"]
    failed = await client.post(
        f"{BASE}/garments/{identifier}/identify/photo", headers=headers, json={"image_id": image_id}
    )
    assert failed.status_code == 503
    result = await client.post(
        f"{BASE}/garments/{identifier}/import/finish", headers=headers, json={"mode": "approximate"}
    )
    assert result.status_code == 200 and result.json()["import_metadata"]["exact_match"] is False
    assert (
        await client.patch(
            f"{BASE}/garments/{identifier}", headers=headers, json={"import_metadata": {"exact_match": True}}
        )
    ).status_code == 422


async def test_exact_match_requires_verified_catalog_identifier(client, monkeypatch):
    headers, identifier = await imported(client, monkeypatch)

    class Catalog:
        async def search_by_barcode(self, barcode):
            return [
                ProductCandidate(name="Identified hoodie", brand="Visible", ean=barcode, source="catalog")
            ]

    monkeypatch.setattr(
        "app.modules.product_search.providers.get_product_search_providers", lambda: [Catalog()]
    )
    result = await client.post(
        f"{BASE}/garments/identify/barcode",
        headers=headers,
        json={"garment_id": identifier, "barcode": "0885909950805"},
    )
    assert result.status_code == 200
    candidate = result.json()["candidates"][0]["id"]
    await client.post(
        f"{BASE}/garments/{identifier}/candidates/{candidate}/confirm",
        headers=headers,
        json={"apply_fields": False},
    )
    saved = await client.post(
        f"{BASE}/garments/{identifier}/import/finish", headers=headers, json={"mode": "candidate"}
    )
    assert saved.json()["import_metadata"]["exact_match"] is True
    assert saved.json()["import_metadata"]["fallback_mode"] is False


async def test_imported_brand_stays_a_hypothesis_until_explicitly_verified(client, monkeypatch):
    headers, identifier = await imported(client, monkeypatch)
    await client.patch(f"{BASE}/garments/{identifier}", headers=headers, json={"brand": "Possible brand"})
    result = await client.post(
        f"{BASE}/garments/{identifier}/import/finish", headers=headers, json={"mode": "approximate"}
    )
    assert result.json()["import_metadata"]["brand_status"] == "unverified"
    result = await client.post(
        f"{BASE}/garments/{identifier}/import/finish",
        headers=headers,
        json={"mode": "custom", "brand_confirmed": True},
    )
    assert result.json()["import_metadata"]["brand_status"] == "user_confirmed"
    assert result.json()["import_metadata"]["exact_match"] is False
