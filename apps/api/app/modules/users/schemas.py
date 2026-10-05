"""Auth + user schemas."""

import uuid
from datetime import datetime

from pydantic import ConfigDict, EmailStr, Field

from app.core.validation import StrictModel
from app.domain.enums import MannequinPresentation


class RegisterRequest(StrictModel):
    first_name: str = Field(min_length=1, max_length=80)
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)
    mannequin_presentation: MannequinPresentation


class LoginRequest(StrictModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)
    device_name: str | None = Field(default=None, max_length=120)


class TokenPair(StrictModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"  # noqa: S105 (OAuth2 token type literal, not a secret)
    expires_in: int


class RefreshRequest(StrictModel):
    refresh_token: str = Field(min_length=20, max_length=512)


class UserOut(StrictModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    first_name: str
    email: EmailStr
    mannequin_presentation: MannequinPresentation
    email_verified: bool
    created_at: datetime
    onboarding_steps: list[str] = Field(default_factory=list)


class OnboardingStepIn(StrictModel):
    step: str = Field(pattern=r"^(profile|preferences|consents)$")


class UpdateProfileRequest(StrictModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=80)
    mannequin_presentation: MannequinPresentation | None = None


class PreferencesIn(StrictModel):
    preferred_styles: list[str] = Field(default_factory=list, max_length=20)
    liked_colors: list[str] = Field(default_factory=list, max_length=30)
    avoided_colors: list[str] = Field(default_factory=list, max_length=30)
    cold_threshold_celsius: float | None = Field(default=None, ge=-40, le=40)
    hot_threshold_celsius: float | None = Field(default=None, ge=-10, le=60)


class PreferencesOut(PreferencesIn):
    learned_warmth_offset: float = 0.0


class PasswordResetRequestIn(StrictModel):
    email: EmailStr


class PasswordResetConfirmIn(StrictModel):
    token: str = Field(min_length=20, max_length=512)
    new_password: str = Field(min_length=10, max_length=128)


class VerifyEmailIn(StrictModel):
    token: str = Field(min_length=20, max_length=512)


class DeleteAccountIn(StrictModel):
    password: str = Field(min_length=1, max_length=128)


class MessageOut(StrictModel):
    message: str
    # Dev-only: when no SMTP is configured the token is returned so the flow
    # remains testable end-to-end. Never populated in production.
    dev_token: str | None = None
