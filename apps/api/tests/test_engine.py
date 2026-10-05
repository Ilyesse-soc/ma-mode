"""Recommendation engine unit tests: rain, cold, heat, destination window."""

import time

import pytest

from app.modules.recommendations.engine import (
    EngineContext,
    EngineGarment,
    EnginePreferences,
    build_weather_window,
    recommend,
)


def _wardrobe() -> list[EngineGarment]:
    return [
        EngineGarment("t1", "top", "tshirt", "T-shirt", "white", 2, False, False, ["casual"]),
        EngineGarment("t2", "top", "polo", "Polo", "navy", 2, False, False, ["casual"]),
        EngineGarment("s1", "top", "sweater", "Pull", "grey", 4, False, False, ["casual"]),
        EngineGarment("j1", "top", "jacket", "Veste imperméable", "black", 3, True, True, ["casual"]),
        EngineGarment("c1", "top", "coat", "Manteau", "beige", 5, False, True, ["chic"]),
        EngineGarment("b1", "bottom", "jeans", "Jean", "navy", 3, False, False, ["casual"]),
        EngineGarment("b2", "bottom", "shorts", "Short", "beige", 1, False, False, ["casual"]),
        EngineGarment("sh1", "shoes", "sneakers", "Sneakers", "white", 2, False, False, ["casual"]),
        EngineGarment("sh2", "shoes", "boots", "Bottes", "brown", 3, True, False, ["casual"]),
    ]


def _ctx(temp_min: float, temp_max: float, rain: float = 0.0, wind: float = 10.0) -> EngineContext:
    return EngineContext(
        weather=__import__("app.modules.recommendations.engine", fromlist=["WeatherWindow"]).WeatherWindow(
            min_feels_like_c=temp_min,
            max_feels_like_c=temp_max,
            max_precip_probability=rain,
            max_precip_mm=3.0 if rain >= 0.5 else 0.0,
            max_wind_kmh=wind,
            max_uv=None,
        ),
        prefs=EnginePreferences(),
        activity="everyday",
    )


def test_cold_weather_recommends_warm_layer():
    outfits = recommend(_wardrobe(), _ctx(temp_min=4.0, temp_max=8.0))
    assert outfits
    top = outfits[0]
    # A warm layer (coat/jacket/sweater) must be present.
    assert any(g in top.garment_ids for g in ("j1", "c1", "s1"))
    assert "au plus frais" in " ".join(top.explanations).lower() or "°C" in " ".join(top.explanations)


def test_rain_prefers_waterproof():
    outfits = recommend(_wardrobe(), _ctx(temp_min=15.0, temp_max=19.0, rain=0.7))
    assert outfits
    assert "j1" in outfits[0].garment_ids  # waterproof jacket picked
    assert any("pluie" in e.lower() for e in outfits[0].explanations)


def test_heat_avoids_heavy_layer():
    outfits = recommend(_wardrobe(), _ctx(temp_min=26.0, temp_max=32.0))
    assert outfits
    top = outfits[0]
    assert "c1" not in top.garment_ids  # no heavy coat in a heatwave
    assert "j1" not in top.garment_ids


def test_recently_worn_outfit_not_reproposed():
    ctx = _ctx(temp_min=15.0, temp_max=20.0)
    first = recommend(_wardrobe(), ctx)
    assert first
    ctx.recently_worn_outfit_keys = {frozenset(first[0].garment_ids)}
    second = recommend(_wardrobe(), ctx)
    assert all(frozenset(o.garment_ids) != frozenset(first[0].garment_ids) for o in second)


def test_max_three_proposals():
    outfits = recommend(_wardrobe(), _ctx(15.0, 20.0), max_outfits=3)
    assert len(outfits) <= 3


def test_empty_wardrobe_returns_nothing():
    assert recommend([], _ctx(15.0, 20.0)) == []


def _point(ts: int, feels: float, rain: float = 0.0) -> dict:
    return {
        "timestamp": ts,
        "temperature_c": feels,
        "feels_like_c": feels,
        "precip_probability": rain,
        "precip_mm": 5.0 if rain > 0.5 else 0.0,
        "wind_kmh": 10.0,
        "gust_kmh": 20.0,
        "humidity_pct": 60.0,
        "uv_index": 2.0,
        "condition": "rain" if rain > 0.5 else "clear",
    }


def test_destination_window_catches_evening_rain_and_cold():
    """Paris now 19°C clear; Lille at 21h 11°C + rain → window must see both."""
    now = int(time.time())
    points = [
        _point(now + 3600, 19.0),  # origin, mild
        _point(now + 6 * 3600, 11.0, rain=0.8),  # destination, cold + rain
    ]
    window = build_weather_window(points, now, now + 8 * 3600)
    assert window.min_feels_like_c == pytest.approx(11.0)
    assert window.max_precip_probability == pytest.approx(0.8)

    outfits = recommend(_wardrobe(), EngineContext(weather=window, prefs=EnginePreferences()))
    assert outfits
    assert "j1" in outfits[0].garment_ids  # waterproof layer recommended


def test_window_fallback_to_nearest_point():
    now = int(time.time())
    points = [_point(now + 100 * 3600, 5.0)]
    window = build_weather_window(points, now, now + 3600)
    assert window.min_feels_like_c == pytest.approx(5.0)


def test_avoided_color_penalized():
    ctx = _ctx(temp_min=15.0, temp_max=20.0)
    ctx.prefs.avoided_colors = ["white"]
    outfits = recommend(_wardrobe(), ctx)
    assert outfits
    # White t-shirt + white sneakers should lose against alternatives.
    assert "t1" not in outfits[0].garment_ids
