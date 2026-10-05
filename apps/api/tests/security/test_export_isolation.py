import io
import json
import zipfile

from tests.conftest import BASE, auth, register_user


async def test_zip_export_only_requester_data_and_no_tokens(client):
    email_a, a, refresh = await register_user(client)
    email_b, b, _ = await register_user(client)
    await client.post(
        f"{BASE}/garments",
        headers=auth(b),
        json={"category_slug": "top_other", "name": "PRIVATE-B-MARKER", "color": "black"},
    )
    await client.put(f"{BASE}/me/consents/ai", headers=auth(a), json={"enabled": True})
    response = await client.get(f"{BASE}/account/export", headers=auth(a))
    assert response.status_code == 200
    assert response.headers["Cache-Control"] == "no-store"
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        text = archive.read("dressly-donnees.json").decode()
        data = json.loads(text)
    assert data["user"]["email"] == email_a and data["consents"]
    assert email_b not in text and "PRIVATE-B-MARKER" not in text
    assert a not in text and refresh not in text and "password_hash" not in text
