"""GDPR data export: returns every piece of personal data held for the user."""

from typing import Any, Literal

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import forbidden
from app.core.time import utc_now
from app.core.validation import StrictModel
from app.db.session import get_db
from app.modules.audit.models import record_audit
from app.modules.outfits.models import Outfit, OutfitHistory
from app.modules.privacy.models import UserConsent
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User, UserPreference
from app.modules.wardrobe.models import Garment, GarmentIdentificationCandidate

router = APIRouter(tags=["privacy"])


class ConsentIn(StrictModel):
    enabled: bool
    version: Literal["ai-v1"] = "ai-v1"


@router.get("/me/consents")
async def get_consents(current: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = list(await db.scalars(select(UserConsent).where(UserConsent.user_id == current.id)))
    return {
        "ai": any(c.consent_type == "ai" and c.withdrawn_at is None for c in rows),
        "records": [
            {
                "consent_type": c.consent_type,
                "version": c.version,
                "accepted_at": c.accepted_at,
                "withdrawn_at": c.withdrawn_at,
            }
            for c in rows
        ],
    }


@router.put("/me/consents/ai")
async def set_ai_consent(
    payload: ConsentIn, current: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    rows = list(
        await db.scalars(
            select(UserConsent)
            .where(
                UserConsent.user_id == current.id,
                UserConsent.consent_type == "ai",
                UserConsent.withdrawn_at.is_(None),
            )
            .with_for_update()
        )
    )
    if not payload.enabled:
        for row in rows:
            row.withdrawn_at = utc_now()
    elif not rows:
        db.add(UserConsent(user_id=current.id, consent_type="ai", version=payload.version))
    await record_audit(
        db,
        "privacy.consent_changed",
        user_id=current.id,
        metadata={"consent_type": "ai", "enabled": payload.enabled, "version": payload.version},
    )
    await db.commit()
    return {"ai": payload.enabled}


async def require_ai_consent(db: AsyncSession, user_id):
    if not await db.scalar(
        select(UserConsent.id).where(
            UserConsent.user_id == user_id,
            UserConsent.consent_type == "ai",
            UserConsent.withdrawn_at.is_(None),
        )
    ):
        raise forbidden("Optional AI analysis requires your explicit choice")


@router.get("/privacy/export")
async def export_data(db: AsyncSession = Depends(get_db), current: User = Depends(get_current_user)):
    prefs = await db.scalar(select(UserPreference).where(UserPreference.user_id == current.id))
    garments = list(await db.scalars(select(Garment).where(Garment.user_id == current.id).limit(10001)))
    outfits = list(await db.scalars(select(Outfit).where(Outfit.user_id == current.id).limit(10001)))
    history = list(
        await db.scalars(select(OutfitHistory).where(OutfitHistory.user_id == current.id).limit(10001))
    )
    if any(len(rows) > 10000 for rows in (garments, outfits, history)):
        from app.core.errors import ApiError

        raise ApiError(413, "export_too_large", "Contact support for a larger export")
    result: dict[str, Any] = {
        "user": {
            "id": str(current.id),
            "first_name": current.first_name,
            "email": current.email,
            "mannequin_presentation": current.mannequin_presentation.value,
            "created_at": current.created_at.isoformat(),
            "updated_at": current.updated_at.isoformat(),
            "email_verified": current.email_verified,
        },
        "preferences": (
            {
                "preferred_styles": prefs.preferred_styles,
                "liked_colors": prefs.liked_colors,
                "avoided_colors": prefs.avoided_colors,
                "cold_threshold_celsius": prefs.cold_threshold_celsius,
                "hot_threshold_celsius": prefs.hot_threshold_celsius,
                "learned_warmth_offset": prefs.learned_warmth_offset,
            }
            if prefs
            else None
        ),
        "garments": [
            {
                "id": str(g.id),
                "name": g.name,
                "brand": g.brand,
                "color": g.color,
                "category": g.category.slug,
                "created_at": g.created_at.isoformat(),
            }
            for g in garments
        ],
        "outfits": [{"id": str(o.id), "name": o.name, "is_favorite": o.is_favorite} for o in outfits],
        "history": [
            {
                "worn_at": h.worn_at.isoformat(),
                "destination_label": h.destination_label,
                "activity": h.activity.value if h.activity else None,
            }
            for h in history
        ],
    }
    from fastapi.encoders import jsonable_encoder

    from app.modules.locations.router import Location
    from app.modules.recommendations.models import Recommendation, RecommendationFeedback
    from app.modules.users.models import NotificationPreference
    from app.modules.weather.router import WeatherSnapshot

    def serialize(row):
        return jsonable_encoder({column.name: getattr(row, column.name) for column in row.__table__.columns})

    result["preferences"] = serialize(prefs) if prefs else None
    proposals = list(
        await db.scalars(
            select(GarmentIdentificationCandidate)
            .join(Garment)
            .where(Garment.user_id == current.id)
            .limit(10001)
        )
    )
    if len(proposals) > 10000:
        from app.core.errors import ApiError

        raise ApiError(413, "export_too_large", "Contact support for a larger export")
    result["identification_candidates"] = [serialize(candidate) for candidate in proposals]
    result["garments"] = [
        {**serialize(g), "category": g.category.slug, "images": [serialize(image) for image in g.images]}
        for g in garments
    ]
    result["outfits"] = [{**serialize(o), "items": [serialize(item) for item in o.items]} for o in outfits]
    result["history"] = [serialize(h) for h in history]
    models: list[tuple[str, Any]] = [
        ("destinations", Location),
        ("recommendations", Recommendation),
        ("feedback", RecommendationFeedback),
        ("consents", UserConsent),
        ("notification_preferences", NotificationPreference),
        ("weather_snapshots", WeatherSnapshot),
    ]
    for name, model in models:
        rows = list(await db.scalars(select(model).where(model.user_id == current.id).limit(10001)))
        if len(rows) > 10000:
            from app.core.errors import ApiError

            raise ApiError(413, "export_too_large", "Contact support for a larger export")
        result[name] = [
            {
                **serialize(r),
                **({"items": [serialize(i) for i in r.items]} if name == "recommendations" else {}),
            }
            for r in rows
        ]
    # Push delivery identifiers are unnecessary in a portable export.
    for row in result["notification_preferences"]:
        row.pop("push_token", None)
    await record_audit(db, "privacy.export", user_id=current.id)
    await db.commit()
    return result


@router.get("/account/export")
async def export_zip(current: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    import io
    import json
    import zipfile

    from fastapi.encoders import jsonable_encoder
    from fastapi.responses import Response

    data = json.dumps(jsonable_encoder(await export_data(db, current)), ensure_ascii=False).encode()
    if len(data) > 20 * 1024 * 1024:
        from app.core.errors import ApiError

        raise ApiError(413, "export_too_large", "Contact support for a larger export")
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("dressly-donnees.json", data)
        from starlette.concurrency import run_in_threadpool

        from app.modules.media import storage

        structured = json.loads(data)
        total_bytes = len(data)
        for garment in structured["garments"]:
            for image in garment["images"]:
                storage.validate_object_key(current.id, image["object_key"])
                total_bytes += image["byte_size"]
                if total_bytes > 20 * 1024 * 1024:
                    from app.core.errors import ApiError

                    raise ApiError(413, "export_too_large", "Contact support for a larger export")
                photo = await run_in_threadpool(storage.read_object, image["object_key"])
                if len(photo) != image["byte_size"]:
                    from app.core.errors import upstream_unavailable

                    raise upstream_unavailable("storage")
                archive.writestr(f"photos/{image['id']}.jpg", photo, compress_type=zipfile.ZIP_STORED)
    return Response(
        buffer.getvalue(),
        media_type="application/zip",
        headers={
            "Content-Disposition": 'attachment; filename="dressly-donnees.zip"',
            "Cache-Control": "no-store",
        },
    )
