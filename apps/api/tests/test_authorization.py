"""Authorization / IDOR tests: user A must never reach user B's data."""

from tests.conftest import BASE, auth, register_user


async def _create_garment(client, token, name="T-shirt test"):
    resp = await client.post(
        f"{BASE}/garments",
        headers=auth(token),
        json={"category_slug": "tshirt", "name": name, "color": "navy"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def test_garment_crud_happy_path(client):
    _, token_a, _ = await register_user(client)
    gid = await _create_garment(client, token_a)

    got = await client.get(f"{BASE}/garments/{gid}", headers=auth(token_a))
    assert got.status_code == 200
    assert got.json()["name"] == "T-shirt test"
    assert got.json()["category"]["slug"] == "tshirt"

    patched = await client.patch(f"{BASE}/garments/{gid}", headers=auth(token_a), json={"warmth_level": 1})
    assert patched.status_code == 200
    assert patched.json()["warmth_level"] == 1

    deleted = await client.delete(f"{BASE}/garments/{gid}", headers=auth(token_a))
    assert deleted.status_code == 204
    missing = await client.get(f"{BASE}/garments/{gid}", headers=auth(token_a))
    assert missing.status_code == 404


async def test_user_b_cannot_read_user_a_garment(client):
    _, token_a, _ = await register_user(client)
    _, token_b, _ = await register_user(client)
    gid = await _create_garment(client, token_a)

    resp = await client.get(f"{BASE}/garments/{gid}", headers=auth(token_b))
    assert resp.status_code == 404


async def test_user_b_cannot_modify_or_delete_user_a_garment(client):
    _, token_a, _ = await register_user(client)
    _, token_b, _ = await register_user(client)
    gid = await _create_garment(client, token_a)

    patch = await client.patch(f"{BASE}/garments/{gid}", headers=auth(token_b), json={"name": "hacked"})
    assert patch.status_code == 404
    delete = await client.delete(f"{BASE}/garments/{gid}", headers=auth(token_b))
    assert delete.status_code == 404


async def test_user_b_cannot_access_user_a_outfit(client):
    _, token_a, _ = await register_user(client)
    _, token_b, _ = await register_user(client)
    gid = await _create_garment(client, token_a)
    outfit = await client.post(
        f"{BASE}/outfits",
        headers=auth(token_a),
        json={"name": "Tenue A", "garment_ids": [gid]},
    )
    assert outfit.status_code == 201
    outfit_id = outfit.json()["id"]

    assert (await client.get(f"{BASE}/outfits/{outfit_id}", headers=auth(token_b))).status_code == 404
    assert (await client.delete(f"{BASE}/outfits/{outfit_id}", headers=auth(token_b))).status_code == 404
    # B cannot even reference A's garment inside B's own outfit.
    stolen = await client.post(
        f"{BASE}/outfits",
        headers=auth(token_b),
        json={"name": "Vol", "garment_ids": [gid]},
    )
    assert stolen.status_code == 404


async def test_unauthenticated_requests_rejected(client):
    resp = await client.get(f"{BASE}/garments")
    assert resp.status_code == 401


async def test_outfit_duplicate_and_favorite(client):
    _, token, _ = await register_user(client)
    gid = await _create_garment(client, token)
    outfit = await client.post(
        f"{BASE}/outfits", headers=auth(token), json={"name": "Base", "garment_ids": [gid]}
    )
    oid = outfit.json()["id"]
    dup = await client.post(f"{BASE}/outfits/{oid}/duplicate", headers=auth(token))
    assert dup.status_code == 201
    assert dup.json()["garment_ids"] == [gid]
    fav = await client.patch(f"{BASE}/outfits/{oid}", headers=auth(token), json={"is_favorite": True})
    assert fav.json()["is_favorite"] is True


async def test_categories_listing(client):
    _, token, _ = await register_user(client)
    resp = await client.get(f"{BASE}/garment-categories", headers=auth(token))
    assert resp.status_code == 200
    slugs = {c["slug"] for c in resp.json()}
    assert {"tshirt", "coat", "jeans", "sneakers", "watch"} <= slugs


async def test_unknown_barcode_returns_not_found(client):
    _, token, _ = await register_user(client)
    resp = await client.post(
        f"{BASE}/garments/identify/barcode",
        headers=auth(token),
        json={"barcode": "000000000000"},
    )
    assert resp.status_code == 200
    # Without network providers reachable in tests, must not invent a reference.
    assert resp.json()["status"] == "not_found"
