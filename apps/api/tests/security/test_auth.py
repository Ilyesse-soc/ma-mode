import jwt

from app.core.security import decode_access_token, hash_password, verify_password
from tests.conftest import BASE, auth, register_user


def test_password_hash_is_argon2id():
    hashed = hash_password("strong-passphrase-for-test")
    assert hashed.startswith("$argon2id$v=19$m=65536,t=3,p=4$")
    assert verify_password("strong-passphrase-for-test", hashed)
    assert not verify_password("wrong", hashed)
    assert not verify_password("anything", "malformed")


async def test_logout_revokes_access_immediately(client):
    _, access, refresh = await register_user(client)
    claims = decode_access_token(access)
    assert claims["sid"] and claims["iss"] == "alamode-api"
    assert "email" not in claims
    assert jwt.get_unverified_header(access)["alg"] == "RS256"
    assert (await client.post(f"{BASE}/auth/logout", json={"refresh_token": refresh})).status_code == 200
    assert (await client.get(f"{BASE}/me", headers=auth(access))).status_code == 401


async def test_password_reset_invalidates_old_tokens_and_is_single_use(client):
    email, access, refresh = await register_user(client)
    response = await client.post(f"{BASE}/auth/password-reset/request", json={"email": email})
    payload = {"token": response.json()["dev_token"], "new_password": "new-strong-password"}
    assert (await client.post(f"{BASE}/auth/password-reset/confirm", json=payload)).status_code == 200
    assert (await client.post(f"{BASE}/auth/password-reset/confirm", json=payload)).status_code == 400
    assert (await client.get(f"{BASE}/me", headers=auth(access))).status_code == 401
    assert (await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})).status_code == 401


async def test_tampered_token_and_anonymous_requests_rejected(client):
    _, access, _ = await register_user(client)
    assert (await client.get(f"{BASE}/me")).status_code == 401
    header, payload, signature = access.split(".")
    changed = ("A" if signature[0] != "A" else "B") + signature[1:]
    assert (await client.get(f"{BASE}/me", headers=auth(f"{header}.{payload}.{changed}"))).status_code == 401
