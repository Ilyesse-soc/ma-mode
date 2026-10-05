"""Wardrobe models: categories, garments, images, identification candidates."""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.mixins import BigIntPk, TimestampMixin
from app.db.session import Base
from app.db.types import JsonVariant
from app.domain.enums import (
    GarmentCategoryGroup,
    IdentificationSource,
    IdentificationStatus,
    Season,
    VisualRepresentationLevel,
)


class GarmentCategory(Base):
    """Extensible category catalog (seeded; admins can add rows)."""

    __tablename__ = "garment_categories"

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    slug: Mapped[str] = mapped_column(sa.String(64), unique=True, index=True, nullable=False)
    label: Mapped[str] = mapped_column(sa.String(120), nullable=False)
    group: Mapped[GarmentCategoryGroup] = mapped_column(
        sa.Enum(GarmentCategoryGroup, name="garment_category_group"), index=True, nullable=False
    )
    sort_order: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)

    garments: Mapped[list["Garment"]] = relationship(back_populates="category")


class Garment(Base, TimestampMixin):
    __tablename__ = "garments"
    __table_args__ = (sa.Index("ix_garments_user_category", "user_id", "category_id"),)

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    category_id: Mapped[int] = mapped_column(
        BigIntPk, sa.ForeignKey("garment_categories.id", ondelete="RESTRICT"), nullable=False
    )
    name: Mapped[str] = mapped_column(sa.String(160), nullable=False)
    brand: Mapped[str | None] = mapped_column(sa.String(120))
    color: Mapped[str] = mapped_column(sa.String(60), nullable=False)
    secondary_colors: Mapped[list] = mapped_column(sa.JSON, default=list, nullable=False)
    size: Mapped[str | None] = mapped_column(sa.String(40))
    material: Mapped[str | None] = mapped_column(sa.String(120))
    season: Mapped[Season] = mapped_column(sa.Enum(Season, name="season"), default=Season.ALL, nullable=False)
    warmth_level: Mapped[int] = mapped_column(
        sa.Integer, default=3, nullable=False
    )  # 1 (very light) .. 5 (very warm)
    waterproof: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    windproof: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    styles: Mapped[list] = mapped_column(sa.JSON, default=list, nullable=False)
    reference: Mapped[str | None] = mapped_column(sa.String(160))  # SKU / product reference
    barcode: Mapped[str | None] = mapped_column(sa.String(32), index=True)
    notes: Mapped[str | None] = mapped_column(sa.Text)
    visual_representation_level: Mapped[VisualRepresentationLevel] = mapped_column(
        sa.Enum(VisualRepresentationLevel, name="visual_representation_level"),
        default=VisualRepresentationLevel.GENERIC,
        nullable=False,
    )
    asset_key: Mapped[str | None] = mapped_column(sa.String(255))  # 3D asset lookup key
    product_image_url: Mapped[str | None] = mapped_column(sa.String(2048))
    is_archived: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    last_worn_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    category: Mapped[GarmentCategory] = relationship(back_populates="garments", lazy="joined")
    images: Mapped[list["GarmentImage"]] = relationship(
        back_populates="garment", cascade="all, delete-orphan", lazy="selectin"
    )
    identification_candidates: Mapped[list["GarmentIdentificationCandidate"]] = relationship(
        back_populates="garment", cascade="all, delete-orphan"
    )


class GarmentImage(Base, TimestampMixin):
    __tablename__ = "garment_images"

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    garment_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("garments.id", ondelete="CASCADE"), index=True, nullable=False
    )
    object_key: Mapped[str] = mapped_column(sa.String(512), nullable=False)  # S3 object key
    content_type: Mapped[str] = mapped_column(sa.String(80), nullable=False)
    byte_size: Mapped[int] = mapped_column(sa.BigInteger, nullable=False)
    width: Mapped[int | None] = mapped_column(sa.Integer)
    height: Mapped[int | None] = mapped_column(sa.Integer)
    is_primary: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    image_kind: Mapped[str] = mapped_column(sa.String(16), default="garment", nullable=False)

    garment: Mapped[Garment] = relationship(back_populates="images")


class GarmentIdentificationCandidate(Base, TimestampMixin):
    """AI/provider proposals. Never auto-applied without user confirmation."""

    __tablename__ = "garment_identification_candidates"

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    garment_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("garments.id", ondelete="CASCADE"), index=True, nullable=False
    )
    source: Mapped[IdentificationSource] = mapped_column(
        sa.Enum(IdentificationSource, name="identification_source"), nullable=False
    )
    status: Mapped[IdentificationStatus] = mapped_column(
        sa.Enum(IdentificationStatus, name="identification_status"),
        default=IdentificationStatus.PENDING,
        nullable=False,
    )
    confidence: Mapped[float] = mapped_column(sa.Float, nullable=False)  # 0..1
    proposed: Mapped[dict] = mapped_column(
        JsonVariant, default=dict, nullable=False
    )  # {name, brand, reference, color, category_slug, ...}
    raw_excerpt: Mapped[str | None] = mapped_column(sa.Text)  # OCR excerpt (trimmed, no photos)

    garment: Mapped[Garment] = relationship(back_populates="identification_candidates")
