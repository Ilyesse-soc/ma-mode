"""Saved locations: current city (manual), favorites, destinations."""

import uuid

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query
from pydantic import ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from app.core.errors import not_found
from app.core.validation import StrictModel
from app.db.mixins import TimestampMixin
from app.db.session import Base, get_db
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User


class Location(Base, TimestampMixin):
    __tablename__ = "locations"

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    label: Mapped[str] = mapped_column(sa.String(160), nullable=False)  # e.g. "Paris", "Lille"
    latitude: Mapped[float] = mapped_column(sa.Float, nullable=False)
    longitude: Mapped[float] = mapped_column(sa.Float, nullable=False)
    is_default: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)


class LocationIn(StrictModel):
    label: str = Field(min_length=1, max_length=160)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    is_default: bool = False


class LocationOut(LocationIn):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID


router = APIRouter(tags=["locations"])


@router.get("/locations/reverse")
async def reverse_location(
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    _: User = Depends(get_current_user),
):
    from app.modules.locations.geocoding import reverse

    return await reverse(latitude, longitude)


@router.get("/locations", response_model=list[LocationOut])
async def list_locations(db: AsyncSession = Depends(get_db), current: User = Depends(get_current_user)):
    result = await db.scalars(
        select(Location).where(Location.user_id == current.id).order_by(Location.created_at)
    )
    return [LocationOut.model_validate(loc) for loc in result]


@router.post("/locations", response_model=LocationOut, status_code=201)
async def create_location(
    payload: LocationIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    if payload.is_default:
        await db.execute(sa.update(Location).where(Location.user_id == current.id).values(is_default=False))
    values = payload.model_dump()
    values.update(latitude=round(payload.latitude, 2), longitude=round(payload.longitude, 2))
    location = Location(user_id=current.id, **values)
    db.add(location)
    await db.commit()
    return LocationOut.model_validate(location)


@router.delete("/locations/{location_id}", status_code=204)
async def delete_location(
    location_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    location = await db.scalar(
        select(Location).where(Location.id == location_id, Location.user_id == current.id)
    )
    if location is None:
        raise not_found("location")
    await db.delete(location)
    await db.commit()
