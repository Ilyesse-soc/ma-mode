"""Weather routes + persisted snapshots used by the recommendation engine."""

import uuid

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from app.db.mixins import BigIntPk, utcnow
from app.db.session import Base, get_db
from app.db.types import JsonVariant
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User
from app.modules.weather.providers import HourlyPoint, WeatherReport, get_weather_provider

router = APIRouter(tags=["weather"])


class WeatherSnapshot(Base):
    """Weather used for a recommendation — kept for explainability/history."""

    __tablename__ = "weather_snapshots"

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), index=True, nullable=False)
    location_label: Mapped[str | None] = mapped_column(sa.String(160))
    latitude: Mapped[float] = mapped_column(sa.Float, nullable=False)
    longitude: Mapped[float] = mapped_column(sa.Float, nullable=False)
    payload: Mapped[dict] = mapped_column(JsonVariant, nullable=False)
    provider: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    created_at: Mapped[object] = mapped_column(
        sa.DateTime(timezone=True), default=utcnow, server_default=sa.func.now(), nullable=False
    )


class HourlyPointOut(BaseModel):
    timestamp: int
    temperature_c: float
    feels_like_c: float
    precip_probability: float
    precip_mm: float
    wind_kmh: float
    gust_kmh: float
    humidity_pct: float
    uv_index: float | None
    condition: str


class WeatherReportOut(BaseModel):
    latitude: float
    longitude: float
    provider: str
    current: HourlyPointOut
    hourly: list[HourlyPointOut]


def _point_out(p: HourlyPoint) -> HourlyPointOut:
    return HourlyPointOut(**vars(p))


def report_to_out(report: WeatherReport) -> WeatherReportOut:
    return WeatherReportOut(
        latitude=report.latitude,
        longitude=report.longitude,
        provider=report.provider,
        current=_point_out(report.current),
        hourly=[_point_out(p) for p in report.hourly],
    )


async def fetch_and_snapshot(
    db: AsyncSession,
    user_id: uuid.UUID,
    latitude: float,
    longitude: float,
    location_label: str | None = None,
) -> WeatherReport:
    report = await get_weather_provider().forecast(latitude, longitude)
    snapshot = WeatherSnapshot(
        user_id=user_id,
        location_label=location_label,
        latitude=round(latitude, 2),
        longitude=round(longitude, 2),
        provider=report.provider,
        payload={
            "current": vars(report.current),
            "hourly": [vars(p) for p in report.hourly],
        },
    )
    db.add(snapshot)
    await db.flush()
    return report


@router.get("/weather/current", response_model=WeatherReportOut)
async def current_weather(
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    location_label: str | None = Query(default=None, max_length=160),
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    report = await fetch_and_snapshot(db, current.id, latitude, longitude, location_label)
    await db.commit()
    return report_to_out(report)
