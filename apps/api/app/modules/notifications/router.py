"""Notification preferences routes (push delivery handled by the worker)."""

from fastapi import APIRouter, Depends
from pydantic import Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.validation import StrictModel
from app.db.session import get_db
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import NotificationPreference, User

router = APIRouter(tags=["notifications"])


class NotificationPrefsIn(StrictModel):
    rain_alerts: bool = True
    daily_outfit: bool = True
    temperature_alerts: bool = True
    push_token: str | None = Field(default=None, max_length=255)


class NotificationPrefsOut(NotificationPrefsIn):
    pass


@router.get("/notifications/preferences", response_model=NotificationPrefsOut)
async def get_prefs(db: AsyncSession = Depends(get_db), current: User = Depends(get_current_user)):
    prefs = await db.scalar(
        select(NotificationPreference).where(NotificationPreference.user_id == current.id)
    )
    if prefs is None:
        prefs = NotificationPreference(user_id=current.id)
        db.add(prefs)
        await db.commit()
    return NotificationPrefsOut(
        rain_alerts=prefs.rain_alerts,
        daily_outfit=prefs.daily_outfit,
        temperature_alerts=prefs.temperature_alerts,
        push_token=prefs.push_token,
    )


@router.put("/notifications/preferences", response_model=NotificationPrefsOut)
async def put_prefs(
    payload: NotificationPrefsIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    prefs = await db.scalar(
        select(NotificationPreference).where(NotificationPreference.user_id == current.id)
    )
    if prefs is None:
        prefs = NotificationPreference(user_id=current.id)
        db.add(prefs)
    prefs.rain_alerts = payload.rain_alerts
    prefs.daily_outfit = payload.daily_outfit
    prefs.temperature_alerts = payload.temperature_alerts
    prefs.push_token = payload.push_token
    await db.commit()
    return NotificationPrefsOut(
        rain_alerts=prefs.rain_alerts,
        daily_outfit=prefs.daily_outfit,
        temperature_alerts=prefs.temperature_alerts,
        push_token=prefs.push_token,
    )
