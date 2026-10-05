import pytest

from app.core.config import get_settings
from app.core.errors import ApiError
from app.modules.locations import geocoding
from app.modules.product_search import providers
from tests.conftest import BASE, auth, register_user


@pytest.mark.parametrize("status", [200, 404, 429])
async def test_free_lookup_has_no_auth_headers_and_handles_status(monkeypatch, status):
    settings = get_settings()
    monkeypatch.setattr(settings, "upcitemdb_mode", "trial")
    monkeypatch.setattr(settings, "upcitemdb_api_key", "unused-paid-key")
    monkeypatch.setattr(providers.budget, "reserve", lambda _: None)
    monkeypatch.setattr(providers.budget, "remember_headers", lambda *args: None)
    calls = []

    async def request(method, url, **kwargs):
        calls.append((url, kwargs))
        return (
            {"items": [{"title": "Real test response", "ean": "0885909950805", "brand": "Brand"}]},
            {"retry-after": "37"},
            status,
        )

    monkeypatch.setattr(providers, "bounded_json_request", request)
    if status == 429:
        with pytest.raises(ApiError) as caught:
            await providers.UpcItemDbProvider().search_by_barcode("0885909950805")
        assert caught.value.status_code == 503 and caught.value.details["retry_after_seconds"] == 37
    else:
        rows = await providers.UpcItemDbProvider().search_by_barcode("0885909950805")
        assert bool(rows) == (status == 200)
    url, options = calls[0]
    assert url == "https://api.upcitemdb.com/prod/trial/lookup"
    assert "user_key" not in options["headers"] and "key_type" not in options["headers"]


async def test_paid_lookup_uses_server_key_and_paid_path(monkeypatch):
    monkeypatch.setattr(get_settings(), "upcitemdb_mode", "paid")
    monkeypatch.setattr(get_settings(), "upcitemdb_api_key", "test-only-not-a-real-key")
    monkeypatch.setattr(providers.budget, "reserve", lambda _: None)
    monkeypatch.setattr(providers.budget, "remember_headers", lambda *args: None)

    async def request(method, url, **kwargs):
        assert url.endswith("/prod/v1/lookup")
        assert kwargs["headers"]["key_type"] == "3scale"
        assert kwargs["headers"]["user_key"] == "test-only-not-a-real-key"
        return {"items": []}, {}, 200

    monkeypatch.setattr(providers, "bounded_json_request", request)
    assert await providers.UpcItemDbProvider().search_by_barcode("0885909950805") == []


async def test_barcode_cache_is_owned_and_reuses_recent_db_proposal(client, monkeypatch):
    _, first, _ = await register_user(client)
    _, second, _ = await register_user(client)
    calls = []

    class Provider:
        async def search_by_barcode(self, barcode):
            calls.append(barcode)
            return [providers.ProductCandidate(name="Stored catalogue result", brand="Brand", confidence=0.7)]

    monkeypatch.setattr(providers, "get_product_search_providers", lambda: [Provider()])
    for token in [first, first, second]:
        result = await client.post(
            f"{BASE}/garments/identify/barcode", headers=auth(token), json={"barcode": "0885909950805"}
        )
        assert result.status_code == 200
    assert len(calls) == 2


async def test_poissy_reverse_keeps_precise_coordinate_input(monkeypatch):
    async def request(method, url, **kwargs):
        assert kwargs["params"]["lat"] == 48.9295123
        assert kwargs["params"]["lon"] == 2.0453123
        return {"features": [{"properties": {"city": "Poissy", "context": "78, Yvelines, Île-de-France"}}]}

    monkeypatch.setattr(geocoding, "bounded_json_request", request)
    result = await geocoding.reverse(48.9295123, 2.0453123)
    assert result.label == "Poissy" and result.administrative_area == "Yvelines"


async def test_reverse_endpoint_requires_authentication(client):
    assert (
        await client.get(f"{BASE}/locations/reverse?latitude=48.9295&longitude=2.0453")
    ).status_code == 401


async def test_provider_timeout_keeps_actionable_unavailable_error(monkeypatch):
    from app.core.errors import upstream_unavailable

    monkeypatch.setattr(providers.budget, "reserve", lambda _: None)

    async def request(*args, **kwargs):
        raise upstream_unavailable("catalog")

    monkeypatch.setattr(providers, "bounded_json_request", request)
    with pytest.raises(ApiError) as caught:
        await providers.UpcItemDbProvider().search_by_barcode("0885909950805")
    assert caught.value.status_code == 503


def test_trial_budget_blocks_seventh_lookup_before_network(monkeypatch):
    from app.modules.product_search import budget

    monkeypatch.setattr(budget, "_redis", lambda: None)
    monkeypatch.setattr(budget, "_blocked_until", 0.0)
    monkeypatch.setattr(get_settings(), "upcitemdb_mode", "trial")
    monkeypatch.setattr(get_settings(), "rate_limit_storage_uri", "memory://")
    budget.limiter.cache_clear()
    try:
        for _ in range(6):
            budget.reserve("lookup")
        with pytest.raises(ApiError) as caught:
            budget.reserve("lookup")
        assert caught.value.status_code == 503
        assert 1 <= caught.value.details["retry_after_seconds"] <= 61
    finally:
        budget.limiter.cache_clear()


async def test_real_ocr_extraction_survives_catalogue_quota(client, monkeypatch):
    import uuid
    from types import SimpleNamespace

    from app.modules.product_recognition import pipeline
    from app.modules.product_recognition.providers import AiResponse, LabelExtraction

    _, token, _ = await register_user(client)
    headers = auth(token)
    garment = (
        await client.post(
            f"{BASE}/garments",
            headers=headers,
            json={"category_slug": "hoodie", "name": "Actual owned garment", "color": "grey"},
        )
    ).json()
    await client.put(f"{BASE}/me/consents/ai", headers=headers, json={"enabled": True})

    async def image(*args):
        return SimpleNamespace(garment_id=uuid.UUID(garment["id"]), object_key="test-image")

    class Vision:
        async def analyze_label(self, data):
            return AiResponse(parsed=LabelExtraction(reference="READ-001", size="M", confidence=0.9))

    class LimitedCatalogue:
        async def search_by_text(self, query):
            raise providers.budget.unavailable(60)

    monkeypatch.setattr(pipeline.wardrobe_service, "get_image_for_user", image)
    monkeypatch.setattr(pipeline, "_download_bytes", lambda _: b"test")
    monkeypatch.setattr(pipeline, "get_ai_provider", Vision)
    monkeypatch.setattr(pipeline, "get_product_search_providers", lambda: [LimitedCatalogue()])
    response = await client.post(
        f"{BASE}/garments/{garment['id']}/identify/label",
        headers=headers,
        json={"image_id": str(uuid.uuid4())},
    )
    assert response.status_code == 200
    assert response.json()["candidates"][0]["proposed"] == {"reference": "READ-001", "size": "M"}


async def test_gemini_requests_exact_schema_and_ignores_thought_parts(monkeypatch):
    from app.modules.product_recognition import providers as vision

    monkeypatch.setattr(get_settings(), "ai_provider", "gemini")
    monkeypatch.setattr(get_settings(), "ai_api_key", "test-only-not-a-real-key")
    monkeypatch.setattr(get_settings(), "ai_vision_model", "gemini-3.5-flash")

    async def request(*args, **kwargs):
        generation = kwargs["json"]["generationConfig"]
        assert generation["maxOutputTokens"] == 600
        assert generation["thinkingConfig"] == {"thinkingLevel": "minimal"}
        assert "color" in generation["responseJsonSchema"]["properties"]
        return {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": "untrusted thought", "thought": True},
                            {"text": '{"color":"blue","category_hint":"tshirt","confidence":0.9}'},
                        ]
                    }
                }
            ]
        }

    monkeypatch.setattr(vision, "bounded_json_request", request)
    result = await vision.GeminiProvider().analyze_garment_photo(b"test-image")
    assert result.parsed.color == "blue"
