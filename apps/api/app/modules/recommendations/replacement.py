"""Rank one requested slot only; preserve every other owned garment ID."""

from sqlalchemy import select

from app.core.errors import bad_request, not_found
from app.modules.recommendations import engine
from app.modules.recommendations.models import Recommendation
from app.modules.users.models import UserPreference
from app.modules.wardrobe.models import Garment

OUTER = {"jacket", "blazer", "coat", "puffer", "cardigan"}


def slot(garment):
    return "outer" if garment.category.slug in OUTER else garment.category.group.value


async def replace_slot(db, user_id, recommendation_id, ids, requested_slot):
    recommendation = await db.scalar(
        select(Recommendation).where(
            Recommendation.id == recommendation_id, Recommendation.user_id == user_id
        )
    )
    if recommendation is None:
        raise not_found("recommendation")
    owned = list(
        await db.scalars(select(Garment).where(Garment.user_id == user_id, Garment.is_archived.is_(False)))
    )
    by_id = {g.id: g for g in owned}
    if not ids or len(set(ids)) != len(ids) or any(identifier not in by_id for identifier in ids):
        raise not_found("garment")
    alternatives = [g for g in owned if slot(g) == requested_slot and g.id not in ids]
    if not alternatives:
        raise bad_request("no_alternative", "Ajoute une autre pièce dans cette catégorie pour la remplacer.")
    preferences = await db.scalar(select(UserPreference).where(UserPreference.user_id == user_id))
    prefs = engine.EnginePreferences(
        preferred_styles=preferences.preferred_styles if preferences else [],
        liked_colors=preferences.liked_colors if preferences else [],
        avoided_colors=preferences.avoided_colors if preferences else [],
        cold_threshold_celsius=preferences.cold_threshold_celsius
        if preferences and preferences.cold_threshold_celsius is not None
        else 12,
        hot_threshold_celsius=preferences.hot_threshold_celsius
        if preferences and preferences.hot_threshold_celsius is not None
        else 24,
        learned_warmth_offset=preferences.learned_warmth_offset if preferences else 0,
    )
    summary = recommendation.weather_summary
    context = engine.EngineContext(
        weather=engine.WeatherWindow(
            min_feels_like_c=summary["min_feels_like_c"],
            max_feels_like_c=summary["max_feels_like_c"],
            max_precip_probability=summary["max_precip_probability"],
            max_precip_mm=summary.get("max_precip_mm", 0),
            max_wind_kmh=summary["max_wind_kmh"],
        ),
        prefs=prefs,
        activity=recommendation.activity.value,
    )

    def score(g):
        clothing = engine.EngineGarment(
            id=str(g.id),
            group=g.category.group.value,
            subcategory=g.category.slug,
            name=g.name,
            color=g.color,
            warmth_level=g.warmth_level,
            waterproof=g.waterproof,
            windproof=g.windproof,
            styles=g.styles,
        )
        return engine.garment_total(engine.score_garment(clothing, context))

    best = max(alternatives, key=score)
    updated = [g for g in ids if slot(by_id[g]) != requested_slot] + [best.id]
    # A dress occupies both top and bottom: do not create incompatible layers.
    if requested_slot == "bottom" and best.category.slug == "dress":
        updated = [g for g in updated if g == best.id or slot(by_id[g]) != "top"]
    if requested_slot == "top" and any(by_id[g].category.slug == "dress" for g in updated):
        raise bad_request(
            "dress_occupies_slots", "Cette robe couvre déjà le haut et le bas. Choisis d'abord un pantalon."
        )
    return {
        "garment_ids": [str(g) for g in updated],
        "replaced_slot": requested_slot,
        "replacement_id": str(best.id),
    }
