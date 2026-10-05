import pytest

from tests.conftest import BASE, auth, register_user


@pytest.mark.parametrize(
    "field", ["owner_id", "user_id", "is_admin", "role", "subscription_status", "created_by", "verified"]
)
async def test_profile_protected_fields_rejected(client, field):
    _, access, _ = await register_user(client)
    response = await client.patch(
        f"{BASE}/me", headers=auth(access), json={"first_name": "Changed", field: "attacker"}
    )
    assert response.status_code == 422
    assert (await client.get(f"{BASE}/me", headers=auth(access))).json()["first_name"] == "Alex"


async def test_garment_owner_rejected(client):
    _, access, _ = await register_user(client)
    response = await client.post(
        f"{BASE}/garments",
        headers=auth(access),
        json={"category_slug": "top_other", "name": "T", "color": "white", "user_id": "attacker"},
    )
    assert response.status_code == 422
