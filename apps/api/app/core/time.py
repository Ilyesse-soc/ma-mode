"""Datetime helpers (SQLite drops tz info — normalize before comparing)."""

from datetime import UTC, datetime


def ensure_aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=UTC)


def utc_now() -> datetime:
    return datetime.now(UTC)
