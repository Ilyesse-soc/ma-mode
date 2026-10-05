import uuid

from app.db.session import get_session_factory
from app.domain.enums import ActivityContext
from app.modules.product_search.providers import ProductCandidate
from app.modules.recommendations.models import Recommendation
from tests.conftest import BASE, auth, register_user


async def garment(client, headers, slug="tshirt", name="Piece"):
    response = await client.post(
        f"{BASE}/garments", headers=headers, json={"category_slug": slug, "name": name, "color": "blue"}
    )
    assert response.status_code == 201
    return response.json()["id"]


async def test_neutral_feedback_keeps_optional_reason_and_owner_isolation(client):
    from sqlalchemy import select

    from app.modules.recommendations.models import RecommendationFeedback
    from app.modules.users.models import User

    user, token, _ = await register_user(client)
    async with get_session_factory()() as db:
        account_id = await db.scalar(select(User.id).where(User.email == user))
        recommendation = Recommendation(
            user_id=account_id, activity=ActivityContext.EVERYDAY, weather_summary={}
        )
        db.add(recommendation)
        await db.commit()
        identifier = recommendation.id
    response = await client.post(
        f"{BASE}/recommendations/{identifier}/feedback",
        headers=auth(token),
        json={"action": "okay", "reason": "uncomfortable"},
    )
    assert response.status_code == 201
    async with get_session_factory()() as db:
        feedback = await db.scalar(
            select(RecommendationFeedback).where(RecommendationFeedback.recommendation_id == identifier)
        )
        assert feedback.action.value == "okay"
        assert feedback.reason == "uncomfortable"
    _, other, _ = await register_user(client)
    assert (
        await client.post(
            f"{BASE}/recommendations/{identifier}/feedback", headers=auth(other), json={"action": "okay"}
        )
    ).status_code == 404


async def test_functional_onboarding_is_account_scoped_persistent_and_idempotent(client):
    _, token, _ = await register_user(client)
    headers = auth(token)
    assert (await client.get(f"{BASE}/me", headers=headers)).json()["onboarding_steps"] == ["profile"]
    for step in ["preferences", "consents", "preferences"]:
        result = await client.put(f"{BASE}/me/onboarding", headers=headers, json={"step": step})
        assert result.status_code == 200
    assert result.json()["onboarding_steps"] == ["profile", "preferences", "consents"]
    _, other, _ = await register_user(client)
    assert (await client.get(f"{BASE}/me", headers=auth(other))).json()["onboarding_steps"] == ["profile"]
    assert (await client.put(f"{BASE}/me/onboarding", json={"step": "consents"})).status_code == 401
    assert (
        await client.put(f"{BASE}/me/onboarding", headers=headers, json={"step": "invalid"})
    ).status_code == 422


async def test_sources_accumulate_and_questions_only_request_missing_information(client, monkeypatch):
    monkeypatch.setattr(
        "app.modules.product_recognition.identification.get_product_search_providers", lambda: []
    )
    _, token, _ = await register_user(client)
    headers = auth(token)
    identifier = await garment(client, headers)
    for fields in [{"brand": "Adidas"}, {"reference": "READ-001"}, {"color": "black"}]:
        response = await client.post(
            f"{BASE}/garments/{identifier}/identify/refine", headers=headers, json=fields
        )
        assert response.status_code == 200
    result = response.json()
    assert result["missing_fields"] == []
    assert result["evidence"] == {"brand": "Adidas", "reference": "READ-001", "color": "black"}
    assert len(result["candidates"]) == 3
    assert all(c["confidence"] == 0 for c in result["candidates"])
    _, other, _ = await register_user(client)
    for method, suffix, body in [
        ("GET", "identification", None),
        ("POST", "identify/refine", {"brand": "Wrong"}),
    ]:
        response = await client.request(
            method, f"{BASE}/garments/{identifier}/{suffix}", headers=auth(other), json=body
        )
        assert response.status_code == 404


async def test_barcode_preserves_all_candidates_and_same_draft_across_sources(client, monkeypatch):
    class Catalog:
        async def search_by_barcode(self, barcode):
            return [
                ProductCandidate(
                    name="First",
                    brand="Brand",
                    ean=barcode,
                    images=["https://example.com/first.jpg"],
                    source="catalog",
                ),
                ProductCandidate(name="Second", brand="Other", ean="0000000000001", source="catalog"),
            ]

    monkeypatch.setattr(
        "app.modules.product_search.providers.get_product_search_providers", lambda: [Catalog()]
    )
    _, token, _ = await register_user(client)
    headers = auth(token)
    identifier = await garment(client, headers)
    response = await client.post(
        f"{BASE}/garments/identify/barcode",
        headers=headers,
        json={"barcode": "0885909950805", "garment_id": identifier},
    )
    assert response.status_code == 200
    result = response.json()
    assert result["garment_id"] == identifier
    assert len(result["candidates"]) == 2
    assert [c["confidence"] for c in result["candidates"]] == [1, 0]
    candidate = result["candidates"][0]["id"]
    response = await client.post(
        f"{BASE}/garments/{identifier}/candidates/{candidate}/confirm",
        headers=headers,
        json={"apply_fields": False},
    )
    assert response.status_code == 200
    assert (await client.get(f"{BASE}/garments/{identifier}", headers=headers)).json()[
        "product_image_url"
    ] == "https://example.com/first.jpg"
    await client.post(f"{BASE}/garments/{identifier}/candidates/{candidate}/reject", headers=headers)
    state = (await client.get(f"{BASE}/garments/{identifier}/identification", headers=headers)).json()
    assert candidate not in [c["id"] for c in state["candidates"]]
    _, other, _ = await register_user(client)
    assert (
        await client.post(f"{BASE}/garments/{identifier}/candidates/{candidate}/reject", headers=auth(other))
    ).status_code == 404


async def test_unknown_barcode_is_a_real_archived_draft_with_help_actions(client):
    _, token, _ = await register_user(client)
    response = await client.post(
        f"{BASE}/garments/identify/barcode", headers=auth(token), json={"barcode": "2991234567891"}
    )
    assert response.status_code == 200
    result = response.json()
    assert result["garment_id"] and result["status"] == "not_found"
    assert "take_label_photo" in result["recommended_actions"]
    assert (await client.get(f"{BASE}/garments", headers=auth(token))).json()["total"] == 0


async def test_replacement_changes_only_requested_slot_and_rejects_foreign_ids(client):
    _, token, _ = await register_user(client)
    headers = auth(token)
    first = await garment(client, headers, name="First top")
    alternate = await garment(client, headers, name="Alternate top")
    bottom = await garment(client, headers, "jeans")
    shoes = await garment(client, headers, "sneakers")
    user_id = (await client.get(f"{BASE}/me", headers=headers)).json()["id"]
    async with get_session_factory()() as db:
        reco = Recommendation(
            user_id=uuid.UUID(user_id),
            activity=ActivityContext.EVERYDAY,
            weather_summary={
                "min_feels_like_c": 18,
                "max_feels_like_c": 23,
                "max_precip_probability": 0.1,
                "max_wind_kmh": 5,
            },
        )
        db.add(reco)
        await db.commit()
        recommendation_id = str(reco.id)
    endpoint = f"{BASE}/recommendations/{recommendation_id}/replace"
    payload = {"slot": "top", "garment_ids": [first, bottom, shoes]}
    response = await client.post(endpoint, headers=headers, json=payload)
    assert response.status_code == 200
    assert response.json()["garment_ids"] == [bottom, shoes, alternate]
    _, other, _ = await register_user(client)
    assert (await client.post(endpoint, headers=auth(other), json=payload)).status_code == 404
    payload["garment_ids"] = [str(uuid.uuid4()), bottom, shoes]
    assert (await client.post(endpoint, headers=headers, json=payload)).status_code == 404
