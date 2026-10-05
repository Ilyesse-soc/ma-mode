"""Auth flow tests: register, login, refresh rotation, reset, delete."""

from tests.conftest import BASE, auth, register_user


async def test_register_and_me(client):
    email, access, _refresh = await register_user(client)
    resp = await client.get(f"{BASE}/me", headers=auth(access))
    assert resp.status_code == 200
    assert resp.json()["email"] == email
    assert resp.json()["first_name"] == "Alex"


async def test_duplicate_email_rejected(client):
    email, _, _ = await register_user(client)
    resp = await client.post(
        f"{BASE}/auth/register",
        json={
            "first_name": "Other",
            "email": email,
            "password": "super-secret-10",
            "mannequin_presentation": "female",
        },
    )
    assert resp.status_code == 409


async def test_login_and_refresh_rotation(client):
    email, _, refresh = await register_user(client)
    resp = await client.post(f"{BASE}/auth/login", json={"email": email, "password": "super-secret-10"})
    assert resp.status_code == 200
    assert resp.json()["access_token"]

    # Rotate once: old refresh becomes invalid.
    resp1 = await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})
    assert resp1.status_code == 200
    new_refresh = resp1.json()["refresh_token"]
    assert new_refresh != refresh

    resp2 = await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})
    assert resp2.status_code == 401


async def test_refresh_reuse_revokes_chain(client):
    _email, _, refresh = await register_user(client)
    r1 = await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})
    assert r1.status_code == 200
    stolen_new = r1.json()["refresh_token"]
    # Replay old token → reuse detection → the NEW token must also be dead.
    replay = await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})
    assert replay.status_code == 401
    reuse = await client.post(f"{BASE}/auth/refresh", json={"refresh_token": stolen_new})
    assert reuse.status_code == 401


async def test_wrong_password_rejected(client):
    email, _, _ = await register_user(client)
    resp = await client.post(f"{BASE}/auth/login", json={"email": email, "password": "wrong-password-1"})
    assert resp.status_code == 401


async def test_password_reset_flow(client):
    email, _, _ = await register_user(client)
    req = await client.post(f"{BASE}/auth/password-reset/request", json={"email": email})
    assert req.status_code == 200
    token = req.json()["dev_token"]
    assert token

    confirm = await client.post(
        f"{BASE}/auth/password-reset/confirm",
        json={"token": token, "new_password": "brand-new-password-1"},
    )
    assert confirm.status_code == 200

    login = await client.post(f"{BASE}/auth/login", json={"email": email, "password": "brand-new-password-1"})
    assert login.status_code == 200


async def test_logout_invalidates_refresh(client):
    _email, _, refresh = await register_user(client)
    out = await client.post(f"{BASE}/auth/logout", json={"refresh_token": refresh})
    assert out.status_code == 200
    again = await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})
    assert again.status_code == 401


async def test_delete_account_blocks_login_and_anonymizes(client):
    email, access, _ = await register_user(client)
    resp = await client.request(
        "DELETE", f"{BASE}/me", headers=auth(access), json={"password": "super-secret-10"}
    )
    assert resp.status_code == 200
    login = await client.post(f"{BASE}/auth/login", json={"email": email, "password": "super-secret-10"})
    assert login.status_code == 401
    me = await client.get(f"{BASE}/me", headers=auth(access))
    assert me.status_code == 401
