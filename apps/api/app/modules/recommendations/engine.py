"""Outfit recommendation engine — deterministic rules + scoring (no LLM required).

Pipeline:
  weather window (origin + destination over the travel time range)
  → effective targets (min/max feels-like, max rain risk, max wind)
  → per-garment scoring (weather, warmth, rain, wind, style, color, history…)
  → bounded combinatorial outfit assembly per garment group
  → top-N outfits with human-readable explanations.

Everything is a pure function over dataclasses: fully unit-testable.
"""

import itertools
from dataclasses import dataclass, field

# ----------------------------------------------------------------------------- inputs


@dataclass
class EngineGarment:
    id: str
    group: str  # head | top | bottom | shoes | wrist | other
    subcategory: str  # e.g. tshirt, coat, jeans
    name: str
    color: str
    warmth_level: int  # 1..5
    waterproof: bool
    windproof: bool
    styles: list[str] = field(default_factory=list)
    last_worn_days_ago: float | None = None
    is_layer: bool = False  # coats/jackets can layer over tops


@dataclass
class WeatherWindow:
    min_feels_like_c: float
    max_feels_like_c: float
    max_precip_probability: float  # 0..1
    max_precip_mm: float
    max_wind_kmh: float
    max_uv: float | None = None


@dataclass
class EnginePreferences:
    cold_threshold_celsius: float = 12.0  # below → user feels cold
    hot_threshold_celsius: float = 24.0  # above → user feels hot
    learned_warmth_offset: float = 0.0  # feedback-driven adjustment
    liked_colors: list[str] = field(default_factory=list)
    avoided_colors: list[str] = field(default_factory=list)
    preferred_styles: list[str] = field(default_factory=list)


@dataclass
class EngineContext:
    weather: WeatherWindow
    prefs: EnginePreferences
    activity: str = "everyday"
    recently_worn_outfit_keys: set[frozenset] = field(default_factory=set)


@dataclass
class ScoredOutfit:
    garment_ids: list[str]
    score: float
    explanations: list[str]
    breakdown: dict[str, float]


# ----------------------------------------------------------------------------- scoring

# Warmth a garment layer adds, indexed by warmth_level 1..5 (approx. °C comfort shift).
_WARMTH_CONTRIBUTION = {1: 0.0, 2: 1.5, 3: 3.0, 4: 5.0, 5: 8.0}

_LAYER_GROUPS = {"coat", "puffer", "jacket", "blazer", "cardigan"}


def _clamp01(x: float) -> float:
    return max(0.0, min(1.0, x))


def score_garment(g: EngineGarment, ctx: EngineContext) -> dict[str, float]:
    """Per-garment sub-scores in [0,1]."""
    w = ctx.weather
    prefs = ctx.prefs

    cold_line = prefs.cold_threshold_celsius + prefs.learned_warmth_offset
    hot_line = prefs.hot_threshold_celsius + prefs.learned_warmth_offset

    # Temperature fit: warmth contribution should cover the gap between the
    # coldest felt temperature and the user's comfort line — without overshooting
    # the hot line at the warmest moment of the window.
    warmth = _WARMTH_CONTRIBUTION.get(g.warmth_level, 3.0)
    needed = max(0.0, cold_line - w.min_feels_like_c)
    if g.group in {"bottom", "shoes", "head"}:
        # Avoid shorts in the cold and heavy trousers/bonnets in hot weather.
        if w.max_feels_like_c > hot_line:
            temperature_score = _clamp01(1.0 - (g.warmth_level - 1) * 0.2)
        elif w.min_feels_like_c < cold_line:
            temperature_score = min(1.0, g.warmth_level / 4.0)
        else:
            temperature_score = 0.8 if g.group != "shoes" else 0.85
    elif g.group in {"wrist", "other"}:
        temperature_score = 0.8
    else:
        overshoot = max(0.0, (w.max_feels_like_c + warmth) - (hot_line + 6.0))
        coverage = _clamp01(warmth / needed) if needed > 0 else _clamp01(1.0 - warmth / 12.0)
        temperature_score = _clamp01(coverage - overshoot * 0.15)

    rain_score = 1.0
    if w.max_precip_probability >= 0.5 or w.max_precip_mm >= 2.0:
        if g.group == "top" and g.subcategory in _LAYER_GROUPS:
            rain_score = 1.0 if g.waterproof else 0.35
        elif g.group == "shoes":
            rain_score = 1.0 if g.waterproof or g.subcategory == "boots" else 0.5
        elif g.group == "bottom":
            rain_score = 0.9 if g.subcategory not in {"shorts", "skirt"} else 0.5

    wind_score = 1.0
    if w.max_wind_kmh >= 35:
        if g.group == "top" and g.subcategory in _LAYER_GROUPS:
            wind_score = 1.0 if g.windproof else 0.55
        elif g.group == "head" and g.subcategory in {"hat", "cap"}:
            wind_score = 0.6  # hats fly away

    style_score = 0.6
    if prefs.preferred_styles and g.styles:
        overlap = len(set(g.styles) & set(prefs.preferred_styles))
        style_score = _clamp01(0.5 + 0.25 * overlap)

    color_score = 0.7
    if g.color in prefs.liked_colors:
        color_score = 1.0
    elif g.color in prefs.avoided_colors:
        color_score = 0.15

    availability_score = 1.0
    recently_worn_penalty = 0.0
    if g.last_worn_days_ago is not None and g.last_worn_days_ago < 2:
        recently_worn_penalty = 0.35

    activity_score = 0.75
    formal_activities = {"work", "restaurant", "date", "formal_event", "evening"}
    if ctx.activity in formal_activities:
        if g.subcategory in {"blazer", "shirt", "polo", "dress_shoes", "dress", "trousers", "blouse"}:
            activity_score = 1.0
        elif g.subcategory in {"joggers", "hoodie", "sandals"}:
            activity_score = 0.3
    elif ctx.activity == "sport":
        if g.subcategory in {"joggers", "sneakers", "tshirt", "shorts"}:
            activity_score = 1.0
        elif g.subcategory in {"blazer", "dress_shoes", "coat"}:
            activity_score = 0.25

    return {
        "temperature": temperature_score,
        "rain": rain_score,
        "wind": wind_score,
        "style": style_score,
        "color": color_score,
        "availability": availability_score,
        "recently_worn_penalty": recently_worn_penalty,
        "activity": activity_score,
    }


_WEIGHTS = {
    "temperature": 0.30,
    "rain": 0.18,
    "wind": 0.10,
    "style": 0.12,
    "color": 0.10,
    "activity": 0.12,
}


def garment_total(scores: dict[str, float]) -> float:
    base = sum(scores[k] * w for k, w in _WEIGHTS.items())
    total = base + scores["availability"] * 0.08 - scores["recently_worn_penalty"]
    if scores["color"] <= 0.2:  # explicitly avoided color: strong deterrent
        total *= 0.7
    return _clamp01(total)


# ----------------------------------------------------------------------------- assembly

# Basic color harmony: neutrals combine with everything; avoid known clashes.
_NEUTRALS = {"black", "white", "grey", "gray", "beige", "navy", "denim", "brown", "cream", "unknown"}
_CLASHES = {frozenset({"red", "pink"}), frozenset({"orange", "pink"}), frozenset({"red", "orange"})}


def color_compatibility(colors: list[str]) -> float:
    distinct = [c for c in set(colors) if c not in _NEUTRALS]
    if any(pair in _CLASHES for pair in itertools.pairwise(distinct)):
        return 0.4
    if len(distinct) <= 2:
        return 1.0
    if len(distinct) == 3:
        return 0.8
    return 0.6


def _pick_layer(garments: list[EngineGarment], ctx: EngineContext) -> EngineGarment | None:
    """Choose an outer layer when the window is cold/rainy/windy."""
    w = ctx.weather
    cold_line = ctx.prefs.cold_threshold_celsius + ctx.prefs.learned_warmth_offset
    needs_layer = (
        w.min_feels_like_c < cold_line
        or w.max_precip_probability >= 0.5
        or w.max_precip_mm >= 2
        or w.max_wind_kmh >= 40
    )
    if not needs_layer:
        return None
    layers = [g for g in garments if g.group == "top" and g.subcategory in _LAYER_GROUPS]
    if not layers:
        return None
    if w.max_precip_probability >= 0.5 or w.max_precip_mm >= 2:
        waterproof_layers = [g for g in layers if g.waterproof]
        if waterproof_layers:
            layers = waterproof_layers
    return max(layers, key=lambda g: garment_total(score_garment(g, ctx)))


def recommend(garments: list[EngineGarment], ctx: EngineContext, max_outfits: int = 3) -> list[ScoredOutfit]:
    """Build up to `max_outfits` scored outfits with explanations."""
    if not garments:
        return []

    by_group: dict[str, list[EngineGarment]] = {}
    for g in garments:
        by_group.setdefault(g.group, []).append(g)

    for group in by_group.values():
        group.sort(key=lambda g: garment_total(score_garment(g, ctx)), reverse=True)

    tops = [g for g in by_group.get("top", []) if g.subcategory not in _LAYER_GROUPS]
    if ctx.activity in {"work", "restaurant", "date", "formal_event", "evening"}:
        formal_tops = [g for g in tops if g.subcategory in {"shirt", "polo", "blouse"}]
        if formal_tops:
            tops = formal_tops
    tops = tops[:4]
    dresses = [g for g in by_group.get("bottom", []) if g.subcategory == "dress"][:2]
    bottoms = [g for g in by_group.get("bottom", []) if g.subcategory != "dress"][:4]
    shoes = by_group.get("shoes", [])[:4]
    heads = by_group.get("head", [])[:2]
    wrists = by_group.get("wrist", [])[:1]
    layer = _pick_layer(garments, ctx)

    # UV / sun: suggest sunglasses/cap on high UV.
    if (ctx.weather.max_uv or 0) >= 6:
        heads = sorted(heads, key=lambda g: g.subcategory in {"sunglasses", "cap"}, reverse=True)

    combos: list[list[EngineGarment]] = []
    for dress in dresses:
        combos.append([dress])
    for top in tops:
        for bottom in bottoms:
            combos.append([top, bottom])

    results: list[ScoredOutfit] = []
    seen_keys: set[frozenset] = set()
    for combo in combos:
        pieces = list(combo)
        if layer is not None:
            pieces.append(layer)
        if shoes:
            pieces.append(shoes[0])
        pieces.extend(heads[:1])
        pieces.extend(wrists)

        key = frozenset(g.id for g in pieces)
        if key in seen_keys or key in ctx.recently_worn_outfit_keys:
            continue
        seen_keys.add(key)

        subscores = [score_garment(g, ctx) for g in pieces]
        garment_scores = [garment_total(s) for s in subscores]
        compat = color_compatibility([g.color for g in pieces])
        score = _clamp01(sum(garment_scores) / len(garment_scores) * (0.6 + 0.4 * compat))

        results.append(
            ScoredOutfit(
                garment_ids=[g.id for g in pieces],
                score=round(score, 3),
                explanations=_explain(pieces, ctx, compat),
                breakdown={
                    "weather_score": round(min(s["temperature"] for s in subscores), 3),
                    "rain_score": round(min(s["rain"] for s in subscores), 3),
                    "wind_score": round(min(s["wind"] for s in subscores), 3),
                    "style_score": round(sum(s["style"] for s in subscores) / len(subscores), 3),
                    "color_compatibility_score": round(compat, 3),
                    "activity_score": round(sum(s["activity"] for s in subscores) / len(subscores), 3),
                    "recently_worn_penalty": round(max(s["recently_worn_penalty"] for s in subscores), 3),
                },
            )
        )

    results.sort(key=lambda o: o.score, reverse=True)
    return results[:max_outfits]


def _explain(pieces: list[EngineGarment], ctx: EngineContext, compat: float) -> list[str]:
    """Human-readable 'why' (French) — required for transparency."""
    w = ctx.weather
    reasons: list[str] = []
    if w.max_precip_probability >= 0.5:
        pct = round(w.max_precip_probability * 100)
        if any(p.waterproof for p in pieces):
            reasons.append(f"Risque de pluie de {pct} % : pièce imperméable incluse.")
        else:
            reasons.append(f"Risque de pluie de {pct} % prévu sur ta journée.")
    if w.min_feels_like_c < ctx.prefs.cold_threshold_celsius + ctx.prefs.learned_warmth_offset:
        temp = round(w.min_feels_like_c)
        reasons.append(f"Il fera {temp} °C ressentis au plus frais : tenue chaude conseillée.")
    if w.max_feels_like_c > ctx.prefs.hot_threshold_celsius + ctx.prefs.learned_warmth_offset:
        temp = round(w.max_feels_like_c)
        reasons.append(f"Jusqu'à {temp} °C ressentis : tenue légère privilégiée.")
    if w.max_wind_kmh >= 40:
        reasons.append(f"Vent jusqu'à {round(w.max_wind_kmh)} km/h pris en compte.")
    if (w.max_uv or 0) >= 6:
        reasons.append("Indice UV élevé : protection (casquette/lunettes) suggérée.")
    if compat >= 0.99:
        reasons.append("Les couleurs se marient bien ensemble.")
    if not reasons:
        reasons.append("Tenue équilibrée pour la météo du jour et tes préférences.")
    return reasons


# ----------------------------------------------------------------------------- windowing


def build_weather_window(points: list[dict], start_ts: int, end_ts: int) -> WeatherWindow:
    """Aggregate hourly weather points over [start_ts, end_ts] into a window."""
    window = [p for p in points if start_ts <= p["timestamp"] <= end_ts]
    if not points:
        raise ValueError("no weather points")
    if not window:
        # nearest point fallback
        nearest = min(points, key=lambda p: abs(p["timestamp"] - start_ts))
        window = [nearest]
    return WeatherWindow(
        min_feels_like_c=min(p["feels_like_c"] for p in window),
        max_feels_like_c=max(p["feels_like_c"] for p in window),
        max_precip_probability=max(p["precip_probability"] for p in window),
        max_precip_mm=max(p["precip_mm"] for p in window),
        max_wind_kmh=max(p["wind_kmh"] for p in window),
        max_uv=max((p.get("uv_index") or 0) for p in window) or None,
    )
