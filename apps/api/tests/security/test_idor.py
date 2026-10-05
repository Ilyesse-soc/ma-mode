from tests.conftest import BASE, auth, register_user


async def test_foreign_garment_read_update_delete_and_outfit_creation(client):
    _, a, _ = await register_user(client)
    _, b, _ = await register_user(client)
    created = await client.post(
        f"{BASE}/garments",
        headers=auth(b),
        json={"category_slug": "top_other", "name": "Private B", "color": "white"},
    )
    assert created.status_code == 201
    gid = created.json()["id"]
    for method, data in [("GET", None), ("PATCH", {"name": "Stolen"}), ("DELETE", None)]:
        response = await client.request(
            method, f"{BASE}/garments/{gid}", headers=auth(a), **({"json": data} if data else {})
        )
        assert response.status_code == 404
    assert (
        await client.post(f"{BASE}/outfits", headers=auth(a), json={"name": "Stolen", "garment_ids": [gid]})
    ).status_code == 404
    assert (await client.get(f"{BASE}/garments/{gid}", headers=auth(b))).json()["name"] == "Private B"


async def test_foreign_outfit_duplicate_update_delete_and_wear(client):
    _, a, _ = await register_user(client)
    _, b, _ = await register_user(client)
    garment = (
        await client.post(
            f"{BASE}/garments",
            headers=auth(b),
            json={"category_slug": "top_other", "name": "B", "color": "black"},
        )
    ).json()
    outfit = (
        await client.post(
            f"{BASE}/outfits", headers=auth(b), json={"name": "B outfit", "garment_ids": [garment["id"]]}
        )
    ).json()
    oid = outfit["id"]
    for method, suffix, payload in [
        ("GET", "", None),
        ("PATCH", "", {"name": "Stolen"}),
        ("DELETE", "", None),
        ("POST", "/duplicate", None),
    ]:
        response = await client.request(
            method, f"{BASE}/outfits/{oid}{suffix}", headers=auth(a), **({"json": payload} if payload else {})
        )
        assert response.status_code == 404
    assert (
        await client.post(
            f"{BASE}/outfits/wear", headers=auth(a), json={"garment_ids": [garment["id"]], "outfit_id": oid}
        )
    ).status_code == 404
