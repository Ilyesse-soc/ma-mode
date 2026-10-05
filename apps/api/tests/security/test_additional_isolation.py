import uuid

from tests.conftest import BASE, auth, register_user


async def test_locations_list_and_delete_are_isolated(client):
    _, a, _ = await register_user(client)
    _, b, _ = await register_user(client)
    saved = await client.post(
        f"{BASE}/locations",
        headers=auth(b),
        json={"label": "Private B", "latitude": 48.12345, "longitude": 2.98765},
    )
    assert saved.status_code == 201
    assert saved.json()["latitude"] == 48.12
    assert (await client.get(f"{BASE}/locations", headers=auth(a))).json() == []
    assert (await client.delete(f"{BASE}/locations/{saved.json()['id']}", headers=auth(a))).status_code == 404


async def test_ai_rejects_foreign_garment_before_provider_or_storage(client, monkeypatch):
    _, a, _ = await register_user(client)
    _, b, _ = await register_user(client)
    garment = (
        await client.post(
            f"{BASE}/garments",
            headers=auth(b),
            json={"category_slug": "top_other", "name": "B", "color": "grey"},
        )
    ).json()
    await client.put(f"{BASE}/me/consents/ai", headers=auth(a), json={"enabled": True})

    def forbidden_call(*args):
        raise AssertionError("Foreign resources must be rejected before storage or AI calls")

    monkeypatch.setattr("app.modules.media.storage.read_object", forbidden_call)
    monkeypatch.setattr("app.modules.product_recognition.pipeline.get_ai_provider", forbidden_call)
    response = await client.post(
        f"{BASE}/garments/{garment['id']}/identify/photo",
        headers=auth(a),
        json={"image_id": str(uuid.uuid4())},
    )
    assert response.status_code == 404
