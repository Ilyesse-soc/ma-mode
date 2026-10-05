"""Shared domain enumerations (single source of truth for mobile + API)."""

from enum import StrEnum


class MannequinPresentation(StrEnum):
    MALE = "male"
    FEMALE = "female"


class GarmentCategoryGroup(StrEnum):
    HEAD = "head"
    TOP = "top"
    BOTTOM = "bottom"
    SHOES = "shoes"
    WRIST = "wrist"
    OTHER = "other"


class Season(StrEnum):
    ALL = "all"
    SPRING = "spring"
    SUMMER = "summer"
    AUTUMN = "autumn"
    WINTER = "winter"


class VisualRepresentationLevel(StrEnum):
    """Honesty about 3D fidelity — see docs/3D_ASSET_SPEC.md."""

    GENERIC = "generic"  # Level 1: category/color faithful generic asset
    APPROXIMATE = "approximate"  # Level 2: close matching asset
    EXACT = "exact"  # Level 3: real product 3D asset


class IdentificationSource(StrEnum):
    MANUAL = "manual"
    BARCODE = "barcode"
    LABEL_OCR = "label_ocr"
    PHOTO_VISION = "photo_vision"


class IdentificationStatus(StrEnum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    REJECTED = "rejected"


class ActivityContext(StrEnum):
    EVERYDAY = "everyday"
    WORK = "work"
    SCHOOL = "school"
    SPORT = "sport"
    RESTAURANT = "restaurant"
    EVENING = "evening"
    DATE = "date"
    FORMAL_EVENT = "formal_event"
    TRAVEL = "travel"
    OTHER = "other"


class FeedbackAction(StrEnum):
    LIKE = "like"
    OKAY = "okay"
    NOT_TODAY = "not_today"
    TOO_HOT = "too_hot"
    TOO_COLD = "too_cold"
    DISLIKE_COMBINATION = "dislike_combination"
    CHANGE_TOP = "change_top"
    CHANGE_BOTTOM = "change_bottom"
    CHANGE_SHOES = "change_shoes"
