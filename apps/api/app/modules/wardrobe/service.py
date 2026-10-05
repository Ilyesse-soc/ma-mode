"""Wardrobe service: ownership-scoped CRUD (IDOR-safe) and identification flow."""

import uuid
from contextlib import suppress
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import bad_request, not_found
from app.modules.wardrobe.models import (
    Garment,
    GarmentCategory,
    GarmentIdentificationCandidate,
    GarmentImage,
)
from app.modules.wardrobe.schemas import GarmentCreate, GarmentUpdate


async def list_categories(db: AsyncSession) -> list[GarmentCategory]:
    result = await db.scalars(select(GarmentCategory).order_by(GarmentCategory.sort_order))
    return list(result)


async def get_category_by_slug(db: AsyncSession, slug: str) -> GarmentCategory:
    category = await db.scalar(select(GarmentCategory).where(GarmentCategory.slug == slug))
    if category is None:
        raise bad_request("unknown_category", f"Unknown category slug: {slug}")
    return category


async def list_garments(
    db: AsyncSession,
    user_id: uuid.UUID,
    page: int = 1,
    page_size: int = 50,
    category_slug: str | None = None,
    include_archived: bool = False,
) -> tuple[list[Garment], int]:
    stmt = select(Garment).where(Garment.user_id == user_id)
    count_stmt = select(func.count(Garment.id)).where(Garment.user_id == user_id)
    if not include_archived:
        stmt = stmt.where(Garment.is_archived.is_(False))
        count_stmt = count_stmt.where(Garment.is_archived.is_(False))
    if category_slug:
        stmt = stmt.join(Garment.category).where(GarmentCategory.slug == category_slug)
        count_stmt = count_stmt.join(Garment.category).where(GarmentCategory.slug == category_slug)
    total = await db.scalar(count_stmt) or 0
    stmt = stmt.order_by(Garment.created_at.desc()).offset((page - 1) * page_size).limit(page_size)
    items = list(await db.scalars(stmt))
    return items, total


async def get_garment(db: AsyncSession, user_id: uuid.UUID, garment_id: uuid.UUID) -> Garment:
    """Ownership-scoped fetch: a garment of user B is invisible to user A (404)."""
    garment = await db.scalar(select(Garment).where(Garment.id == garment_id, Garment.user_id == user_id))
    if garment is None:
        raise not_found("garment")
    return garment


async def create_garment(db: AsyncSession, user_id: uuid.UUID, payload: GarmentCreate) -> Garment:
    category = await get_category_by_slug(db, payload.category_slug)
    garment = Garment(
        user_id=user_id,
        category_id=category.id,
        name=payload.name.strip(),
        brand=payload.brand,
        color=payload.color.strip().lower(),
        secondary_colors=payload.secondary_colors,
        size=payload.size,
        material=payload.material,
        season=payload.season,
        warmth_level=payload.warmth_level,
        waterproof=payload.waterproof,
        windproof=payload.windproof,
        styles=payload.styles,
        reference=payload.reference,
        barcode=payload.barcode,
        notes=payload.notes,
        is_archived=payload.is_archived,
    )
    db.add(garment)
    await db.flush()
    await db.refresh(garment, attribute_names=["category", "images"])
    return garment


async def update_garment(
    db: AsyncSession, user_id: uuid.UUID, garment_id: uuid.UUID, payload: GarmentUpdate
) -> Garment:
    garment = await get_garment(db, user_id, garment_id)
    data = payload.model_dump(exclude_unset=True)
    if "category_slug" in data:
        category = await get_category_by_slug(db, data.pop("category_slug"))
        garment.category_id = category.id
    for field, value in data.items():
        setattr(garment, field, value)
    await db.flush()
    return garment


async def delete_garment(db: AsyncSession, user_id: uuid.UUID, garment_id: uuid.UUID) -> Garment:
    garment = await get_garment(db, user_id, garment_id)
    await db.delete(garment)
    return garment


async def mark_worn(db: AsyncSession, user_id: uuid.UUID, garment_ids: list[uuid.UUID]) -> None:
    if not garment_ids:
        return
    garments = await db.scalars(
        select(Garment).where(Garment.id.in_(garment_ids), Garment.user_id == user_id)
    )
    now = datetime.now(UTC)
    for garment in garments:
        garment.last_worn_at = now


# --- Identification candidates -------------------------------------------------


async def add_candidate(
    db: AsyncSession,
    garment_id: uuid.UUID,
    source,
    confidence: float,
    proposed: dict,
    raw_excerpt: str | None = None,
) -> GarmentIdentificationCandidate:
    candidate = GarmentIdentificationCandidate(
        garment_id=garment_id,
        source=source,
        confidence=max(0.0, min(1.0, confidence)),
        proposed=proposed,
        raw_excerpt=(raw_excerpt or None) and raw_excerpt[:2000],
    )
    db.add(candidate)
    await db.flush()
    return candidate


async def confirm_candidate(
    db: AsyncSession,
    user_id: uuid.UUID,
    garment_id: uuid.UUID,
    candidate_id: uuid.UUID,
    apply_fields: bool,
) -> GarmentIdentificationCandidate:
    garment = await get_garment(db, user_id, garment_id)  # IDOR guard
    candidate = await db.scalar(
        select(GarmentIdentificationCandidate).where(
            GarmentIdentificationCandidate.id == candidate_id,
            GarmentIdentificationCandidate.garment_id == garment.id,
        )
    )
    if candidate is None:
        raise not_found("candidate")
    candidate.status = candidate.status.__class__.CONFIRMED
    images = candidate.proposed.get("images", [])
    if isinstance(images, list) and images and isinstance(images[0], str):
        from app.core.errors import ApiError
        from app.core.outbound import validate_public_url

        with suppress(ApiError):
            garment.product_image_url = validate_public_url(images[0], resolve=False)
    if apply_fields:
        proposed = candidate.proposed
        for field in ("name", "brand", "color", "reference", "material"):
            if proposed.get(field):
                setattr(garment, field, proposed[field])
        if proposed.get("category_slug"):
            category = await get_category_by_slug(db, proposed["category_slug"])
            garment.category_id = category.id
    await db.flush()
    return candidate


async def attach_image(
    db: AsyncSession,
    user_id: uuid.UUID,
    garment_id: uuid.UUID,
    object_key: str,
    content_type: str,
    byte_size: int,
    width: int | None,
    height: int | None,
) -> GarmentImage:
    garment = await get_garment(db, user_id, garment_id)  # IDOR guard
    image = GarmentImage(
        garment_id=garment.id,
        object_key=object_key,
        content_type=content_type,
        byte_size=byte_size,
        width=width,
        height=height,
        is_primary=False,
    )
    db.add(image)
    await db.flush()
    return image


async def get_image_for_user(db: AsyncSession, user_id: uuid.UUID, image_id: uuid.UUID) -> GarmentImage:
    image = await db.scalar(
        select(GarmentImage)
        .join(Garment, GarmentImage.garment_id == Garment.id)
        .where(GarmentImage.id == image_id, Garment.user_id == user_id)
    )
    if image is None:
        raise not_found("image")
    return image
