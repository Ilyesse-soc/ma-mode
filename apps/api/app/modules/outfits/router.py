"""Outfit routes: CRUD, duplicate, favorite, wear tracking, history."""

import uuid

from fastapi import APIRouter, Depends
from pydantic import ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import bad_request, not_found
from app.core.validation import StrictModel
from app.db.session import get_db
from app.domain.enums import ActivityContext
from app.modules.outfits.models import Outfit, OutfitHistory, OutfitItem
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User
from app.modules.wardrobe import service as wardrobe_service

router = APIRouter(tags=["outfits"])


class OutfitIn(StrictModel):
    name: str = Field(min_length=1, max_length=160)
    garment_ids: list[uuid.UUID] = Field(min_length=1, max_length=30)


class OutfitUpdateIn(StrictModel):
    name: str | None = Field(default=None, min_length=1, max_length=160)
    garment_ids: list[uuid.UUID] | None = Field(default=None, min_length=1, max_length=30)
    is_favorite: bool | None = None


class OutfitOut(StrictModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    is_favorite: bool
    garment_ids: list[uuid.UUID]


class HistoryOut(StrictModel):
    id: int
    outfit_id: uuid.UUID | None
    worn_at: str
    destination_label: str | None
    activity: str | None
    feedback: str | None
    garment_ids: list
    weather: dict | None = None


def _to_out(outfit: Outfit) -> OutfitOut:
    return OutfitOut(
        id=outfit.id,
        name=outfit.name,
        is_favorite=outfit.is_favorite,
        garment_ids=[item.garment_id for item in sorted(outfit.items, key=lambda i: i.layer_order)],
    )


async def _get_owned_outfit(db: AsyncSession, user_id: uuid.UUID, outfit_id: uuid.UUID) -> Outfit:
    outfit = await db.scalar(select(Outfit).where(Outfit.id == outfit_id, Outfit.user_id == user_id))
    if outfit is None:
        raise not_found("outfit")
    return outfit


async def _validate_garments(db: AsyncSession, user_id: uuid.UUID, garment_ids: list[uuid.UUID]) -> None:
    for gid in garment_ids:
        await wardrobe_service.get_garment(db, user_id, gid)  # raises 404 if foreign


def _set_items(outfit: Outfit, garment_ids: list[uuid.UUID]) -> None:
    if len(set(garment_ids)) != len(garment_ids):
        raise bad_request("duplicate_garment", "An outfit cannot contain the same garment twice")
    outfit.items = [OutfitItem(garment_id=gid, layer_order=i) for i, gid in enumerate(garment_ids)]


@router.get("/outfits", response_model=list[OutfitOut])
async def list_outfits(db: AsyncSession = Depends(get_db), current: User = Depends(get_current_user)):
    result = await db.scalars(
        select(Outfit).where(Outfit.user_id == current.id).order_by(Outfit.created_at.desc())
    )
    return [_to_out(o) for o in result]


@router.post("/outfits", response_model=OutfitOut, status_code=201)
async def create_outfit(
    payload: OutfitIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    await _validate_garments(db, current.id, payload.garment_ids)
    outfit = Outfit(user_id=current.id, name=payload.name.strip())
    _set_items(outfit, payload.garment_ids)
    db.add(outfit)
    await db.commit()
    await db.refresh(outfit, attribute_names=["items"])
    return _to_out(outfit)


@router.get("/outfits/{outfit_id}", response_model=OutfitOut)
async def get_outfit(
    outfit_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    return _to_out(await _get_owned_outfit(db, current.id, outfit_id))


@router.patch("/outfits/{outfit_id}", response_model=OutfitOut)
async def update_outfit(
    outfit_id: uuid.UUID,
    payload: OutfitUpdateIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    outfit = await _get_owned_outfit(db, current.id, outfit_id)
    if payload.name is not None:
        outfit.name = payload.name.strip()
    if payload.is_favorite is not None:
        outfit.is_favorite = payload.is_favorite
    if payload.garment_ids is not None:
        await _validate_garments(db, current.id, payload.garment_ids)
        outfit.items.clear()
        await db.flush()
        _set_items(outfit, payload.garment_ids)
    await db.commit()
    await db.refresh(outfit, attribute_names=["items"])
    return _to_out(outfit)


@router.delete("/outfits/{outfit_id}", status_code=204)
async def delete_outfit(
    outfit_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    outfit = await _get_owned_outfit(db, current.id, outfit_id)
    await db.delete(outfit)
    await db.commit()


@router.post("/outfits/{outfit_id}/duplicate", response_model=OutfitOut, status_code=201)
async def duplicate_outfit(
    outfit_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    source = await _get_owned_outfit(db, current.id, outfit_id)
    copy = Outfit(user_id=current.id, name=f"{source.name} (copie)")
    _set_items(copy, [item.garment_id for item in source.items])
    db.add(copy)
    await db.commit()
    await db.refresh(copy, attribute_names=["items"])
    return _to_out(copy)


class WearIn(StrictModel):
    garment_ids: list[uuid.UUID] = Field(min_length=1, max_length=30)
    outfit_id: uuid.UUID | None = None
    destination_label: str | None = Field(default=None, max_length=160)
    activity: ActivityContext | None = None
    weather_snapshot_id: int | None = None


@router.post("/outfits/wear", status_code=201)
async def wear(
    payload: WearIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    await _validate_garments(db, current.id, payload.garment_ids)
    if payload.outfit_id is not None:
        await _get_owned_outfit(db, current.id, payload.outfit_id)
    if payload.weather_snapshot_id is not None:
        from app.modules.weather.router import WeatherSnapshot

        snapshot = await db.scalar(
            select(WeatherSnapshot.id).where(
                WeatherSnapshot.id == payload.weather_snapshot_id, WeatherSnapshot.user_id == current.id
            )
        )
        if snapshot is None:
            raise not_found("weather")
    entry = OutfitHistory(
        user_id=current.id,
        outfit_id=payload.outfit_id,
        destination_label=payload.destination_label,
        activity=payload.activity,
        weather_snapshot_id=payload.weather_snapshot_id,
        garment_ids=[str(g) for g in payload.garment_ids],
    )
    db.add(entry)
    await wardrobe_service.mark_worn(db, current.id, payload.garment_ids)
    await db.commit()
    return {"message": "Tenue enregistrée comme portée"}


@router.get("/outfits/stats/summary")
async def stats_summary(db: AsyncSession = Depends(get_db), current: User = Depends(get_current_user)):
    """Real usage statistics derived from outfit history + wardrobe."""
    from sqlalchemy import func

    from app.modules.wardrobe.models import Garment

    worn_count = await db.scalar(
        select(func.count(OutfitHistory.id)).where(OutfitHistory.user_id == current.id)
    )
    garment_count = await db.scalar(
        select(func.count(Garment.id)).where(Garment.user_id == current.id, Garment.is_archived.is_(False))
    )
    outfit_count = await db.scalar(select(func.count(Outfit.id)).where(Outfit.user_id == current.id))
    favorite_count = await db.scalar(
        select(func.count(Outfit.id)).where(Outfit.user_id == current.id, Outfit.is_favorite.is_(True))
    )
    return {
        "outfits_worn": worn_count or 0,
        "garments": garment_count or 0,
        "outfits_saved": outfit_count or 0,
        "favorites": favorite_count or 0,
    }


@router.get("/outfits/history/recent", response_model=list[HistoryOut])
async def recent_history(db: AsyncSession = Depends(get_db), current: User = Depends(get_current_user)):
    from app.modules.weather.router import WeatherSnapshot

    result = list(
        await db.scalars(
            select(OutfitHistory)
            .where(OutfitHistory.user_id == current.id)
            .order_by(OutfitHistory.worn_at.desc())
            .limit(50)
        )
    )
    snapshot_ids = [h.weather_snapshot_id for h in result if h.weather_snapshot_id is not None]
    snapshots = (
        {
            s.id: s.payload.get("current")
            for s in await db.scalars(
                select(WeatherSnapshot).where(
                    WeatherSnapshot.user_id == current.id, WeatherSnapshot.id.in_(snapshot_ids)
                )
            )
        }
        if snapshot_ids
        else {}
    )
    return [
        HistoryOut(
            id=h.id,
            outfit_id=h.outfit_id,
            worn_at=h.worn_at.isoformat(),
            destination_label=h.destination_label,
            activity=h.activity.value if h.activity else None,
            feedback=h.feedback,
            garment_ids=h.garment_ids,
            weather=snapshots.get(h.weather_snapshot_id) if h.weather_snapshot_id is not None else None,
        )
        for h in result
    ]
