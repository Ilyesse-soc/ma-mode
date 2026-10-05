"""User account, preferences and session (refresh token) models."""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.mixins import BigIntPk, TimestampMixin, utcnow
from app.db.session import Base
from app.domain.enums import MannequinPresentation


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    first_name: Mapped[str] = mapped_column(sa.String(80), nullable=False)
    email: Mapped[str] = mapped_column(sa.String(320), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    mannequin_presentation: Mapped[MannequinPresentation] = mapped_column(
        sa.Enum(MannequinPresentation, name="mannequin_presentation"), nullable=False
    )
    email_verified: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    email_verification_token_hash: Mapped[str | None] = mapped_column(sa.String(64))
    email_verification_expires_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    password_reset_token_hash: Mapped[str | None] = mapped_column(sa.String(64))
    password_reset_expires_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    preferences: Mapped["UserPreference"] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    sessions: Mapped[list["Session"]] = relationship(back_populates="user", cascade="all, delete-orphan")


class UserPreference(Base, TimestampMixin):
    __tablename__ = "user_preferences"

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    preferred_styles: Mapped[list] = mapped_column(sa.JSON, default=list, nullable=False)
    liked_colors: Mapped[list] = mapped_column(sa.JSON, default=list, nullable=False)
    avoided_colors: Mapped[list] = mapped_column(sa.JSON, default=list, nullable=False)
    cold_threshold_celsius: Mapped[float | None] = mapped_column(sa.Float)
    hot_threshold_celsius: Mapped[float | None] = mapped_column(sa.Float)
    # Learned implicit adjustments derived from feedback (transparent, user-resettable).
    learned_warmth_offset: Mapped[float] = mapped_column(sa.Float, default=0.0, nullable=False)

    user: Mapped[User] = relationship(back_populates="preferences")


class Session(Base):
    """Refresh-token session. Only the SHA-256 hash of the token is stored."""

    __tablename__ = "sessions"

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    refresh_token_hash: Mapped[str] = mapped_column(sa.String(64), unique=True, nullable=False)
    device_name: Mapped[str | None] = mapped_column(sa.String(120))
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), default=utcnow, server_default=sa.func.now(), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid(as_uuid=True))

    user: Mapped[User] = relationship(back_populates="sessions")


class NotificationPreference(Base, TimestampMixin):
    __tablename__ = "notification_preferences"

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    rain_alerts: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    daily_outfit: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    temperature_alerts: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    push_token: Mapped[str | None] = mapped_column(sa.String(255))
