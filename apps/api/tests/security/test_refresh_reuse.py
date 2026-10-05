from tests.conftest import BASE, auth, register_user


async def test_replay_revokes_all_devices_access_and_refresh(client):
    email, first, old = await register_user(client)
    login = await client.post(f"{BASE}/auth/login", json={"email": email, "password": "super-secret-10"})
    second = login.json()
    rotated = await client.post(f"{BASE}/auth/refresh", json={"refresh_token": old})
    new = rotated.json()
    assert rotated.status_code == 200
    assert (await client.get(f"{BASE}/me", headers=auth(first))).status_code == 401
    assert (await client.get(f"{BASE}/me", headers=auth(new["access_token"]))).status_code == 200
    assert (await client.post(f"{BASE}/auth/refresh", json={"refresh_token": old})).status_code == 401
    for tokens in (new, second):
        assert (await client.get(f"{BASE}/me", headers=auth(tokens["access_token"]))).status_code == 401
        assert (
            await client.post(f"{BASE}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
        ).status_code == 401
