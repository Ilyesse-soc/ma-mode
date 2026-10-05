"""Audit trail: security-relevant events, no PII payloads."""

import uuid

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from app.core.logging import redact
from app.db.mixins import BigIntPk, utcnow
from app.db.session import Base
from app.db.types import JsonVariant


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid(as_uuid=True), index=True)
    event_type: Mapped[str] = mapped_column(sa.String(64), index=True, nullable=False)
    ip_hash: Mapped[str | None] = mapped_column(sa.String(64))  # sha256, never raw IP
    user_agent: Mapped[str | None] = mapped_column(sa.String(255))
    metadata_json: Mapped[dict] = mapped_column(JsonVariant, default=dict, nullable=False)
    created_at: Mapped[object] = mapped_column(
        sa.DateTime(timezone=True), default=utcnow, server_default=sa.func.now(), nullable=False
    )


async def record_audit(
    db: AsyncSession,
    event_type: str,
    user_id: uuid.UUID | None = None,
    ip_hash: str | None = None,
    user_agent: str | None = None,
    metadata: dict | None = None,
) -> None:
    db.add(
        AuditEvent(
            user_id=user_id,
            event_type=event_type,
            ip_hash=ip_hash,
            user_agent=(user_agent or "")[:255] or None,
            metadata_json=redact(metadata or {}),
        )
    )
