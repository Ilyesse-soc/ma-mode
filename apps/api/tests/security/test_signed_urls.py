from tests.conftest import BASE, auth, register_user


async def test_foreign_or_unattached_objects_never_signed(client, monkeypatch):
    _, a, _ = await register_user(client)
    _, b, _ = await register_user(client)
    me = (await client.get(f"{BASE}/me", headers=auth(b))).json()
    key = f"users/{me['id']}/validated/{'a' * 32}.jpg"

    def forbidden_sign(_):
        raise AssertionError("Ownership must be checked before signing")

    monkeypatch.setattr("app.modules.media.storage.create_presigned_download", forbidden_sign)
    for token in (a, b):
        response = await client.get(
            f"{BASE}/media/download-url", headers=auth(token), params={"object_key": key}
        )
        assert response.status_code == 404
    response = await client.get(
        f"{BASE}/media/download-url",
        headers=auth(b),
        params={"object_key": f"users/{me['id']}/../other/private.jpg"},
    )
    assert response.status_code == 404
