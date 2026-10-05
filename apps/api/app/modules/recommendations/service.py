"""Recommendation orchestration: weather window → engine → persistence → learning."""

import time
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import bad_request, not_found
from app.domain.enums import ActivityContext, FeedbackAction
from app.modules.outfits.models import OutfitHistory
from app.modules.recommendations import engine
from app.modules.recommendations.models import (
    Recommendation,
    RecommendationFeedback,
    RecommendationItem,
)
from app.modules.users.models import UserPreference
from app.modules.wardrobe.models import Garment
from app.modules.weather.router import fetch_and_snapshot

DEFAULT_TRIP_HOURS = 12  # how far ahead we look when no explicit end is given


async def _recent_outfit_keys(db: AsyncSession, user_id: uuid.UUID) -> set[frozenset]:
    result = await db.scalars(
        select(OutfitHistory)
        .where(OutfitHistory.user_id == user_id)
        .order_by(OutfitHistory.worn_at.desc())
        .limit(10)
    )
    keys: set[frozenset] = set()
    for h in result:
        if h.garment_ids:
            keys.add(frozenset(str(g) for g in h.garment_ids))
    return keys


async def generate_recommendations(
    db: AsyncSession,
    user_id: uuid.UUID,
    origin_lat: float,
    origin_lon: float,
    origin_label: str | None,
    destination_lat: float | None,
    destination_lon: float | None,
    destination_label: str | None,
    arrival_ts: int | None,
    activity: ActivityContext,
) -> Recommendation:
    now = int(time.time())
    end_ts = (arrival_ts + 4 * 3600) if arrival_ts else now + DEFAULT_TRIP_HOURS * 3600

    snapshot_ids: list[int] = []
    origin_report = await fetch_and_snapshot(db, user_id, origin_lat, origin_lon, origin_label, snapshot_ids)
    points: list[dict] = [vars(p) for p in origin_report.hourly] or [vars(origin_report.current)]

    if destination_lat is not None and destination_lon is not None:
        dest_report = await fetch_and_snapshot(
            db, user_id, destination_lat, destination_lon, destination_label, snapshot_ids
        )
        # Consider the destination from the arrival time onward.
        points += [vars(p) for p in dest_report.hourly]

    window = engine.build_weather_window(points, now, end_ts)

    prefs_row = await db.scalar(select(UserPreference).where(UserPreference.user_id == user_id))
    prefs = engine.EnginePreferences(
        cold_threshold_celsius=(
            prefs_row.cold_threshold_celsius
            if prefs_row and prefs_row.cold_threshold_celsius is not None
            else 12.0
        ),
        hot_threshold_celsius=(
            prefs_row.hot_threshold_celsius
            if prefs_row and prefs_row.hot_threshold_celsius is not None
            else 24.0
        ),
        learned_warmth_offset=prefs_row.learned_warmth_offset if prefs_row else 0.0,
        liked_colors=prefs_row.liked_colors if prefs_row else [],
        avoided_colors=prefs_row.avoided_colors if prefs_row else [],
        preferred_styles=prefs_row.preferred_styles if prefs_row else [],
    )

    garments_rows = list(
        await db.scalars(select(Garment).where(Garment.user_id == user_id, Garment.is_archived.is_(False)))
    )
    now_s = time.time()
    engine_garments = [
        engine.EngineGarment(
            id=str(g.id),
            group=g.category.group.value,
            subcategory=g.category.slug,
            name=g.name,
            color=g.color,
            warmth_level=g.warmth_level,
            waterproof=g.waterproof,
            windproof=g.windproof,
            styles=g.styles,
            last_worn_days_ago=((now_s - g.last_worn_at.timestamp()) / 86400 if g.last_worn_at else None),
        )
        for g in garments_rows
    ]
    if not engine_garments:
        raise bad_request(
            "empty_wardrobe",
            "Ajoute d'abord quelques vêtements à ta garde-robe pour recevoir des suggestions.",
        )

    recent_keys = await _recent_outfit_keys(db, user_id)
    ctx = engine.EngineContext(
        weather=window, prefs=prefs, activity=activity.value, recently_worn_outfit_keys=recent_keys
    )
    proposals = engine.recommend(engine_garments, ctx, max_outfits=3)
    if not proposals:
        raise bad_request(
            "no_outfit_available",
            "Pas assez de variété dans la garde-robe pour proposer une tenue différente.",
        )

    recommendation = Recommendation(
        user_id=user_id,
        origin_label=origin_label,
        destination_label=destination_label,
        activity=activity,
        weather_summary={
            "weather_snapshot_id": snapshot_ids[-1] if snapshot_ids else None,
            "min_feels_like_c": window.min_feels_like_c,
            "max_feels_like_c": window.max_feels_like_c,
            "max_precip_probability": window.max_precip_probability,
            "max_precip_mm": window.max_precip_mm,
            "max_wind_kmh": window.max_wind_kmh,
        },
    )
    recommendation.items = [
        RecommendationItem(
            rank=i + 1,
            score=p.score,
            garment_ids=p.garment_ids,
            explanations=p.explanations,
            breakdown=p.breakdown,
        )
        for i, p in enumerate(proposals)
    ]
    db.add(recommendation)
    await db.flush()
    return recommendation


async def record_feedback(
    db: AsyncSession,
    user_id: uuid.UUID,
    recommendation_id: uuid.UUID,
    action: FeedbackAction,
    garment_id: uuid.UUID | None,
    reason: str | None = None,
) -> None:
    recommendation = await db.scalar(
        select(Recommendation).where(
            Recommendation.id == recommendation_id, Recommendation.user_id == user_id
        )
    )
    if recommendation is None:
        raise not_found("recommendation")
    if garment_id is not None:
        from app.modules.wardrobe.service import get_garment

        await get_garment(db, user_id, garment_id)
        if not any(str(garment_id) in item.garment_ids for item in recommendation.items):
            raise not_found("garment")
    db.add(
        RecommendationFeedback(
            recommendation_id=recommendation.id,
            user_id=user_id,
            action=action,
            garment_id=garment_id,
            reason=reason,
        )
    )
    if action == FeedbackAction.LIKE:
        recommendation.accepted = True
    elif action in {FeedbackAction.NOT_TODAY, FeedbackAction.DISLIKE_COMBINATION}:
        recommendation.accepted = False

    # Transparent preference learning: explicit, bounded, user-resettable.
    thermal_action = reason if reason in {"too_cold", "too_hot"} else action
    if thermal_action in {FeedbackAction.TOO_COLD, FeedbackAction.TOO_HOT}:
        prefs = await db.scalar(select(UserPreference).where(UserPreference.user_id == user_id))
        if prefs is not None:
            delta = 1.0 if thermal_action == FeedbackAction.TOO_COLD else -1.0
            prefs.learned_warmth_offset = max(-5.0, min(5.0, prefs.learned_warmth_offset + delta))


async def get_last_recommendation(db: AsyncSession, user_id: uuid.UUID) -> Recommendation | None:
    return await db.scalar(
        select(Recommendation)
        .where(Recommendation.user_id == user_id)
        .order_by(Recommendation.created_at.desc())
        .limit(1)
    )
