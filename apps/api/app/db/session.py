"""Async SQLAlchemy engine and session factory."""

import ssl
from collections.abc import AsyncGenerator
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings


class Base(DeclarativeBase):
    """Declarative base for all ORM models."""


_engine = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def init_engine(database_url: str | None = None) -> None:
    global _engine, _session_factory
    url = database_url or get_settings().database_url
    connect_args: dict[str, Any] = {"check_same_thread": False} if url.startswith("sqlite") else {}
    if get_settings().is_production and url.startswith("postgresql"):
        connect_args["ssl"] = ssl.create_default_context(cafile=get_settings().database_ca_file or None)
    _engine = create_async_engine(url, echo=False, pool_pre_ping=True, connect_args=connect_args)
    _session_factory = async_sessionmaker(_engine, class_=AsyncSession, expire_on_commit=False)


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    if _session_factory is None:
        init_engine()
    if _session_factory is None:
        raise RuntimeError("Database session factory unavailable")
    return _session_factory


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    factory = get_session_factory()
    async with factory() as session:
        yield session


async def dispose_engine() -> None:
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _session_factory = None
