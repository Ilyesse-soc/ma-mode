from app.core.config import get_settings
from tests.conftest import BASE


async def test_login_budget_enforced_without_disabling_limiter(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_account", "2/minute")
    payload = {"email": "unknown@test.dev", "password": "wrong-password"}
    results = [await client.post(f"{BASE}/auth/login", json=payload) for _ in range(3)]
    assert [r.status_code for r in results] == [401, 401, 429]
    assert results[-1].headers["Retry-After"] == "60"


async def test_reset_unknown_and_known_same_response_without_dev_tokens(client, monkeypatch):
    from tests.conftest import register_user

    email, _, _ = await register_user(client)
    monkeypatch.setattr(get_settings(), "allow_dev_tokens", False)
    known = await client.post(f"{BASE}/auth/password-reset/request", json={"email": email})
    unknown = await client.post(f"{BASE}/auth/password-reset/request", json={"email": "unknown@test.dev"})
    assert known.status_code == unknown.status_code == 503
    assert known.json() == unknown.json()
