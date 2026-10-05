"""Wardrobe schemas."""

import uuid
from datetime import datetime

from pydantic import ConfigDict, Field

from app.core.validation import StrictModel
from app.domain.enums import (
    GarmentCategoryGroup,
    IdentificationSource,
    IdentificationStatus,
    Season,
    VisualRepresentationLevel,
)


class CategoryOut(StrictModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    slug: str
    label: str
    group: GarmentCategoryGroup
    sort_order: int


class GarmentCreate(StrictModel):
    is_archived: bool = False
    category_slug: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=160)
    brand: str | None = Field(default=None, max_length=120)
    color: str = Field(min_length=1, max_length=60)
    secondary_colors: list[str] = Field(default_factory=list, max_length=8)
    size: str | None = Field(default=None, max_length=40)
    material: str | None = Field(default=None, max_length=120)
    season: Season = Season.ALL
    warmth_level: int = Field(default=3, ge=1, le=5)
    waterproof: bool = False
    windproof: bool = False
    styles: list[str] = Field(default_factory=list, max_length=10)
    reference: str | None = Field(default=None, max_length=160)
    barcode: str | None = Field(default=None, max_length=32)
    notes: str | None = Field(default=None, max_length=2000)


class GarmentUpdate(StrictModel):
    category_slug: str | None = Field(default=None, max_length=64)
    name: str | None = Field(default=None, min_length=1, max_length=160)
    brand: str | None = Field(default=None, max_length=120)
    color: str | None = Field(default=None, min_length=1, max_length=60)
    secondary_colors: list[str] | None = Field(default=None, max_length=8)
    size: str | None = Field(default=None, max_length=40)
    material: str | None = Field(default=None, max_length=120)
    season: Season | None = None
    warmth_level: int | None = Field(default=None, ge=1, le=5)
    waterproof: bool | None = None
    windproof: bool | None = None
    styles: list[str] | None = Field(default=None, max_length=10)
    reference: str | None = Field(default=None, max_length=160)
    notes: str | None = Field(default=None, max_length=2000)
    is_archived: bool | None = None


class GarmentImageOut(StrictModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    content_type: str
    byte_size: int
    width: int | None
    height: int | None
    is_primary: bool
    download_url: str | None = None  # presigned, injected at serialization


class GarmentOut(StrictModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    brand: str | None
    color: str
    secondary_colors: list
    size: str | None
    material: str | None
    season: Season
    warmth_level: int
    waterproof: bool
    windproof: bool
    styles: list
    reference: str | None
    barcode: str | None
    notes: str | None
    visual_representation_level: VisualRepresentationLevel
    asset_key: str | None
    is_archived: bool
    last_worn_at: datetime | None
    created_at: datetime
    category: CategoryOut
    images: list[GarmentImageOut] = Field(default_factory=list)


class GarmentPage(StrictModel):
    items: list[GarmentOut]
    total: int
    page: int
    page_size: int


class CandidateOut(StrictModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    source: IdentificationSource
    status: IdentificationStatus
    confidence: float
    proposed: dict
    raw_excerpt: str | None
    created_at: datetime


class IdentifyBarcodeIn(StrictModel):
    barcode: str = Field(min_length=6, max_length=32, pattern=r"^[0-9A-Za-z\-]+$")


class IdentifyLabelIn(StrictModel):
    image_id: uuid.UUID  # previously uploaded label photo


class IdentifyPhotoIn(StrictModel):
    image_id: uuid.UUID  # previously uploaded garment photo


class IdentifyResult(StrictModel):
    garment_id: uuid.UUID | None = None
    status: str  # "matched" | "candidates" | "not_found"
    candidates: list[CandidateOut] = Field(default_factory=list)
    message: str


class ConfirmCandidateIn(StrictModel):
    apply_fields: bool = True  # copy confirmed fields onto the garment
