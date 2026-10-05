"""Shared ORM helpers: primary key type portable between PostgreSQL and SQLite."""

import uuid
from datetime import UTC, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

# Portable bigint PK: SQLite needs INTEGER PRIMARY KEY for autoincrement.
BigIntPk = sa.BigInteger().with_variant(sa.Integer, "sqlite")


def utcnow() -> datetime:
    return datetime.now(UTC)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), default=utcnow, server_default=sa.func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True),
        default=utcnow,
        server_default=sa.func.now(),
        onupdate=utcnow,
        nullable=False,
    )


class UuidPkMixin:
    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
