"""Exercise the real API contracts used by the mobile account and wardrobe flows."""

from app.modules.product_search.providers import ProductCandidate
from tests.conftest import BASE, auth, register_user


async def test_manual_garment_saved_outfit_history_export_and_delete(client):
    email, token, _ = await register_user(client)
    headers = auth(token)
    created = await client.post(
        f"{BASE}/garments",
        headers=headers,
        json={
            "category_slug": "tshirt",
            "name": "T-shirt blanc",
            "color": "white",
            "material": "coton",
            "size": "M",
            "season": "summer",
            "styles": ["Streetwear"],
        },
    )
    assert created.status_code == 201, created.text
    garment_id = created.json()["id"]
    edited = await client.patch(
        f"{BASE}/garments/{garment_id}", headers=headers, json={"name": "Mon t-shirt", "warmth_level": 2}
    )
    assert edited.status_code == 200
    assert edited.json()["material"] == "coton"
    outfit = await client.post(
        f"{BASE}/outfits", headers=headers, json={"name": "Tenue du jour", "garment_ids": [garment_id]}
    )
    assert outfit.status_code == 201, outfit.text
    outfit_id = outfit.json()["id"]
    worn = await client.post(
        f"{BASE}/outfits/wear",
        headers=headers,
        json={
            "outfit_id": outfit_id,
            "garment_ids": [garment_id],
            "destination_label": "Paris",
            "activity": "work",
        },
    )
    assert worn.status_code == 201, worn.text
    favorite = await client.patch(f"{BASE}/outfits/{outfit_id}", headers=headers, json={"is_favorite": True})
    assert favorite.json()["is_favorite"] is True
    history = await client.get(f"{BASE}/outfits/history/recent", headers=headers)
    assert history.json()[0]["outfit_id"] == outfit_id
    assert history.json()[0]["garment_ids"] == [garment_id]
    exported = await client.get(f"{BASE}/privacy/export", headers=headers)
    assert exported.status_code == 200, exported.text
    assert exported.json()["user"]["email"] == email
    assert exported.json()["outfits"][0]["is_favorite"] is True
    assert len(exported.json()["history"]) == 1
    denied = await client.request(
        "DELETE", f"{BASE}/me", headers=headers, json={"password": "wrong-password"}
    )
    assert denied.status_code == 401
    deleted = await client.request(
        "DELETE", f"{BASE}/me", headers=headers, json={"password": "super-secret-10"}
    )
    assert deleted.status_code == 200, deleted.text
    assert (await client.get(f"{BASE}/me", headers=headers)).status_code == 401


async def test_archived_photo_draft_becomes_same_visible_garment(client):
    _, token, _ = await register_user(client)
    headers = auth(token)
    draft = await client.post(
        f"{BASE}/garments",
        headers=headers,
        json={"category_slug": "top_other", "name": "Analyse photo", "color": "unknown", "is_archived": True},
    )
    assert draft.status_code == 201, draft.text
    garment_id = draft.json()["id"]
    assert (await client.get(f"{BASE}/garments", headers=headers)).json()["total"] == 0
    saved = await client.patch(
        f"{BASE}/garments/{garment_id}",
        headers=headers,
        json={"name": "Hoodie gris", "category_slug": "hoodie", "color": "grey", "is_archived": False},
    )
    assert saved.status_code == 200, saved.text
    wardrobe = (await client.get(f"{BASE}/garments", headers=headers)).json()
    assert wardrobe["total"] == 1
    assert wardrobe["items"][0]["id"] == garment_id


async def test_barcode_returns_draft_id_and_confirmation_keeps_one_garment(client, monkeypatch):
    class ExternalCatalog:
        async def search_by_barcode(self, barcode):
            return [ProductCandidate(name="T-shirt blanc", brand="Marque", confidence=0.9)]

    monkeypatch.setattr(
        "app.modules.product_search.providers.get_product_search_providers", lambda: [ExternalCatalog()]
    )
    _, token, _ = await register_user(client)
    headers = auth(token)
    scanned = await client.post(
        f"{BASE}/garments/identify/barcode", headers=headers, json={"barcode": "1234567890123"}
    )
    assert scanned.status_code == 200, scanned.text
    result = scanned.json()
    garment_id = result["garment_id"]
    assert garment_id
    assert (await client.get(f"{BASE}/garments", headers=headers)).json()["total"] == 0
    candidate_id = result["candidates"][0]["id"]
    confirmed = await client.post(
        f"{BASE}/garments/{garment_id}/candidates/{candidate_id}/confirm",
        headers=headers,
        json={"apply_fields": False},
    )
    assert confirmed.status_code == 200, confirmed.text
    assert confirmed.json()["status"] == "confirmed"
    saved = await client.patch(
        f"{BASE}/garments/{garment_id}",
        headers=headers,
        json={"category_slug": "tshirt", "name": "T-shirt validé", "color": "white", "is_archived": False},
    )
    assert saved.status_code == 200
    wardrobe = (await client.get(f"{BASE}/garments", headers=headers)).json()
    assert wardrobe["total"] == 1
    assert wardrobe["items"][0]["id"] == garment_id


async def test_destinations_preferences_notifications_and_profile(client):
    _, token, _ = await register_user(client)
    headers = auth(token)
    place = await client.post(
        f"{BASE}/locations",
        headers=headers,
        json={"label": "Lille", "latitude": 50.6292, "longitude": 3.0573},
    )
    assert place.status_code == 201
    assert (await client.get(f"{BASE}/locations", headers=headers)).json()[0]["label"] == "Lille"
    assert (await client.delete(f"{BASE}/locations/{place.json()['id']}", headers=headers)).status_code == 204
    assert (await client.get(f"{BASE}/locations", headers=headers)).json() == []
    prefs = {
        "preferred_styles": ["Streetwear"],
        "liked_colors": ["black"],
        "avoided_colors": ["red"],
        "cold_threshold_celsius": 10,
        "hot_threshold_celsius": 25,
    }
    assert (await client.put(f"{BASE}/me/preferences", headers=headers, json=prefs)).status_code == 200
    loaded = (await client.get(f"{BASE}/me/preferences", headers=headers)).json()
    for key, value in prefs.items():
        assert loaded[key] == value
    notification_prefs = {"rain_alerts": False, "daily_outfit": True, "temperature_alerts": False}
    assert (
        await client.put(f"{BASE}/notifications/preferences", headers=headers, json=notification_prefs)
    ).status_code == 200
    loaded_notifications = (await client.get(f"{BASE}/notifications/preferences", headers=headers)).json()
    for key, value in notification_prefs.items():
        assert loaded_notifications[key] == value
    profile = await client.patch(f"{BASE}/me", headers=headers, json={"mannequin_presentation": "female"})
    assert profile.status_code == 200
    assert profile.json()["mannequin_presentation"] == "female"
