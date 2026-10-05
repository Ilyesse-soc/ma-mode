"""Outfit models: outfits, outfit_items, outfit_history."""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.mixins import BigIntPk, TimestampMixin, utcnow
from app.db.session import Base
from app.domain.enums import ActivityContext


class Outfit(Base, TimestampMixin):
    __tablename__ = "outfits"

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(sa.String(160), nullable=False)
    is_favorite: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)

    items: Mapped[list["OutfitItem"]] = relationship(
        back_populates="outfit", cascade="all, delete-orphan", lazy="selectin"
    )


class OutfitItem(Base):
    __tablename__ = "outfit_items"
    __table_args__ = (sa.UniqueConstraint("outfit_id", "garment_id", name="uq_outfit_garment"),)

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    outfit_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("outfits.id", ondelete="CASCADE"), index=True, nullable=False
    )
    garment_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("garments.id", ondelete="CASCADE"), nullable=False
    )
    layer_order: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)

    outfit: Mapped[Outfit] = relationship(back_populates="items")


class OutfitHistory(Base):
    __tablename__ = "outfit_history"

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    outfit_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("outfits.id", ondelete="SET NULL"), index=True
    )
    worn_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), default=utcnow, server_default=sa.func.now(), nullable=False
    )
    weather_snapshot_id: Mapped[int | None] = mapped_column(BigIntPk)
    destination_label: Mapped[str | None] = mapped_column(sa.String(160))
    activity: Mapped[ActivityContext | None] = mapped_column(
        sa.Enum(ActivityContext, name="activity_context")
    )
    feedback: Mapped[str | None] = mapped_column(sa.String(40))
    garment_ids: Mapped[list] = mapped_column(sa.JSON, default=list, nullable=False)
