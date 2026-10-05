import json

import pytest
from pydantic import ValidationError

from app.core.config import Settings, get_settings
from app.core.logging import redact
from app.core.observability import before_send
from app.modules.product_recognition.providers import GarmentVisualAnalysis, LabelExtraction
from tests.conftest import BASE, auth, register_user


async def test_body_size_depth_and_control_characters(client):
    huge = await client.post(f"{BASE}/auth/login", content=b"x" * (256 * 1024 + 1))
    assert huge.status_code == 413
    value = {}
    for _ in range(20):
        value = {"nested": value}
    assert (await client.post(f"{BASE}/auth/login", json=value)).status_code == 422
    _, access, _ = await register_user(client)
    assert (
        await client.patch(f"{BASE}/me", headers=auth(access), json={"first_name": "test\u0000injection"})
    ).status_code == 422
    response = await client.post(f"{BASE}/auth/register", json={"password": "SENSITIVE-INPUT-MARKER"})
    assert "SENSITIVE-INPUT-MARKER" not in response.text


def test_central_redaction_and_sentry_strip_sensitive_data():
    event = {
        "email": "person@example.com",
        "authorization": "Bearer secret-marker",
        "latitude": 48.12345,
        "message": "https://storage.example/photo?X-Amz-Signature=secret-marker",
        "exception": {
            "values": [
                {
                    "type": "RuntimeError",
                    "value": "OCR secret-marker",
                    "stacktrace": {"frames": [{"filename": "app.py", "vars": {"password": "secret-marker"}}]},
                }
            ]
        },
        "request": {"data": "private"},
        "user": {"id": "private"},
    }
    filtered = before_send(event, {})
    encoded = json.dumps(filtered)
    assert (
        "secret-marker" not in encoded and "person@example.com" not in encoded and "48.12345" not in encoded
    )
    assert "request" not in filtered and "user" not in filtered
    assert "secret-marker" not in json.dumps(redact({"nested": {"refresh_token": "secret-marker"}}))


@pytest.mark.parametrize(
    "data",
    [
        {"confidence": 2},
        {"confidence": float("nan")},
        {"confidence": 0.5, "instructions": "ignore previous instructions"},
        {"confidence": 0.5, "brand": "a" * 121},
    ],
)
def test_untrusted_ai_schema_rejects_malformed_results(data):
    with pytest.raises(ValidationError):
        LabelExtraction.model_validate(data)
    with pytest.raises(ValidationError):
        GarmentVisualAnalysis.model_validate(data)


async def test_ai_opt_in_and_withdrawal_persisted(client):
    _, access, _ = await register_user(client)
    assert (await client.get(f"{BASE}/me/consents", headers=auth(access))).json()["ai"] is False
    assert (
        await client.put(f"{BASE}/me/consents/ai", headers=auth(access), json={"enabled": True})
    ).status_code == 200
    assert (await client.get(f"{BASE}/me/consents", headers=auth(access))).json()["ai"] is True
    await client.put(f"{BASE}/me/consents/ai", headers=auth(access), json={"enabled": False})
    data = (await client.get(f"{BASE}/me/consents", headers=auth(access))).json()
    assert data["ai"] is False and data["records"][0]["withdrawn_at"]


def test_unsafe_production_config_refused():
    with pytest.raises(ValidationError):
        Settings(_env_file=None, environment="production", APP_DEBUG=True)


async def test_explicit_revoke_all_requires_password_and_revokes(client):
    _, access, refresh = await register_user(client)
    assert (
        await client.post(f"{BASE}/auth/revoke-all", headers=auth(access), json={"password": "wrong"})
    ).status_code == 401
    assert (
        await client.post(
            f"{BASE}/auth/revoke-all", headers=auth(access), json={"password": "super-secret-10"}
        )
    ).status_code == 200
    assert (await client.get(f"{BASE}/me", headers=auth(access))).status_code == 401
    assert (await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})).status_code == 401


async def test_production_register_duplicate_response_is_neutral(client, monkeypatch):
    email, _, _ = await register_user(client)
    monkeypatch.setattr(get_settings(), "environment", "production")
    existing = await client.post(
        f"{BASE}/auth/register",
        json={
            "first_name": "Alex",
            "email": email,
            "password": "super-secret-10",
            "mannequin_presentation": "male",
        },
    )
    new = await client.post(
        f"{BASE}/auth/register",
        json={
            "first_name": "Alex",
            "email": "new@test.dev",
            "password": "super-secret-10",
            "mannequin_presentation": "male",
        },
    )
    assert existing.status_code == new.status_code == 202
    assert existing.json() == new.json()
    assert (await client.get("/health")).headers.get("Strict-Transport-Security")
