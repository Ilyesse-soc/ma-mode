"""Recommendation API tests with a stubbed weather provider (no network)."""

import time

import pytest

from app.modules.weather import providers as weather_providers
from app.modules.weather.providers import HourlyPoint, WeatherReport
from tests.conftest import BASE, auth, register_user


class _StubWeatherProvider(weather_providers.WeatherProvider):
    name = "stub"

    def __init__(self, dest_cold_rainy: bool = True):
        self.calls = 0
        self.dest_cold_rainy = dest_cold_rainy

    async def forecast(self, latitude: float, longitude: float) -> WeatherReport:
        self.calls += 1
        now = int(time.time())
        if self.calls > 1 and self.dest_cold_rainy:
            # Destination: 11°C, 80% rain this evening.
            points = [
                HourlyPoint(now + i * 3600, 11.0, 10.0, 0.8, 4.0, 25.0, 40.0, 80.0, None, "rain")
                for i in range(6)
            ]
            current = points[0]
        else:
            # Origin: mild 19°C, clear.
            points = [
                HourlyPoint(now + i * 3600, 19.0, 18.0, 0.0, 0.0, 10.0, 15.0, 55.0, 3.0, "clear")
                for i in range(6)
            ]
            current = points[0]
        return WeatherReport(latitude, longitude, current, points, provider=self.name)


@pytest.fixture
def stub_weather(monkeypatch):
    provider = _StubWeatherProvider()
    monkeypatch.setattr("app.modules.weather.router.get_weather_provider", lambda: provider)
    return provider


async def _seed_wardrobe(client, token):
    garments = [
        {"category_slug": "tshirt", "name": "T-shirt", "color": "white", "warmth_level": 2},
        {
            "category_slug": "jacket",
            "name": "Veste pluie",
            "color": "black",
            "warmth_level": 3,
            "waterproof": True,
            "windproof": True,
        },
        {"category_slug": "jeans", "name": "Jean", "color": "navy", "warmth_level": 3},
        {"category_slug": "boots", "name": "Bottes", "color": "brown", "warmth_level": 3, "waterproof": True},
    ]
    for g in garments:
        resp = await client.post(f"{BASE}/garments", headers=auth(token), json=g)
        assert resp.status_code == 201, resp.text


async def test_generate_with_destination_recommends_rain_gear(client, stub_weather):
    _, token, _ = await register_user(client)
    await _seed_wardrobe(client, token)

    resp = await client.post(
        f"{BASE}/recommendations/generate",
        headers=auth(token),
        json={
            "origin_latitude": 48.8566,
            "origin_longitude": 2.3522,
            "origin_label": "Paris",
            "destination_latitude": 50.6292,
            "destination_longitude": 3.0573,
            "destination_label": "Lille",
        },
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["destination_label"] == "Lille"
    assert len(data["proposals"]) >= 1
    assert len(data["proposals"]) <= 3
    assert stub_weather.calls == 2  # origin AND destination were fetched

    top = data["proposals"][0]
    joined = " ".join(top["explanations"]).lower()
    assert "pluie" in joined or "°c" in joined
    assert top["breakdown"]["rain_score"] > 0


async def test_generate_requires_non_empty_wardrobe(client, stub_weather):
    _, token, _ = await register_user(client)
    resp = await client.post(
        f"{BASE}/recommendations/generate",
        headers=auth(token),
        json={"origin_latitude": 48.85, "origin_longitude": 2.35},
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "empty_wardrobe"


async def test_feedback_learning_and_like(client, stub_weather):
    _, token, _ = await register_user(client)
    await _seed_wardrobe(client, token)
    gen = await client.post(
        f"{BASE}/recommendations/generate",
        headers=auth(token),
        json={"origin_latitude": 48.85, "origin_longitude": 2.35},
    )
    reco_id = gen.json()["id"]

    fb = await client.post(
        f"{BASE}/recommendations/{reco_id}/feedback",
        headers=auth(token),
        json={"action": "too_cold"},
    )
    assert fb.status_code == 201

    prefs = await client.get(f"{BASE}/me/preferences", headers=auth(token))
    assert prefs.json()["learned_warmth_offset"] == 1.0

    like = await client.post(
        f"{BASE}/recommendations/{reco_id}/feedback",
        headers=auth(token),
        json={"action": "like"},
    )
    assert like.status_code == 201

    last = await client.get(f"{BASE}/recommendations/last", headers=auth(token))
    assert last.status_code == 200
    assert last.json()["id"] == reco_id


async def test_feedback_on_foreign_recommendation_rejected(client, stub_weather):
    _, token_a, _ = await register_user(client)
    _, token_b, _ = await register_user(client)
    await _seed_wardrobe(client, token_a)
    gen = await client.post(
        f"{BASE}/recommendations/generate",
        headers=auth(token_a),
        json={"origin_latitude": 48.85, "origin_longitude": 2.35},
    )
    reco_id = gen.json()["id"]
    resp = await client.post(
        f"{BASE}/recommendations/{reco_id}/feedback",
        headers=auth(token_b),
        json={"action": "like"},
    )
    assert resp.status_code == 404


async def test_privacy_export_contains_own_data_only(client):
    email, token, _ = await register_user(client)
    await _seed_wardrobe(client, token)
    resp = await client.get(f"{BASE}/privacy/export", headers=auth(token))
    assert resp.status_code == 200
    data = resp.json()
    assert data["user"]["email"] == email
    assert len(data["garments"]) == 4
