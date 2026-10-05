"""Auth business logic: register, login, refresh rotation, reset, verify, delete."""

import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app.core.config import get_settings
from app.core.errors import bad_request, conflict, unauthorized
from app.core.monitoring import record_metric
from app.core.security import (
    DUMMY_PASSWORD_HASH,
    create_access_token,
    generate_refresh_token,
    hash_password,
    hash_refresh_token,
    refresh_token_matches,
    verify_password,
)
from app.core.time import ensure_aware, utc_now
from app.modules.audit.models import record_audit
from app.modules.users.models import (
    NotificationPreference,
    Session,
    User,
    UserPreference,
)
from app.modules.users.schemas import RegisterRequest

RESET_TOKEN_TTL = timedelta(hours=1)


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


async def register_user(db: AsyncSession, payload: RegisterRequest) -> tuple[User, str]:
    existing = await db.scalar(select(User).where(User.email == payload.email.lower()))
    if existing is not None:
        raise conflict("registration_unavailable", "Unable to register this account")
    verification_token = secrets.token_urlsafe(32)
    user = User(
        first_name=payload.first_name.strip(),
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
        mannequin_presentation=payload.mannequin_presentation,
        email_verification_token_hash=_hash_token(verification_token),
        email_verification_expires_at=utc_now() + timedelta(hours=24),
    )
    db.add(user)
    await db.flush()
    db.add(UserPreference(user_id=user.id))
    db.add(NotificationPreference(user_id=user.id))
    await record_audit(db, "user.registered", user_id=user.id)
    await db.flush()
    return user, verification_token


async def create_session(db: AsyncSession, user: User, device_name: str | None) -> tuple[str, str, int]:
    settings = get_settings()
    refresh = generate_refresh_token()
    session = Session(
        user_id=user.id,
        refresh_token_hash=hash_refresh_token(refresh),
        device_name=device_name,
        expires_at=datetime.now(UTC) + timedelta(seconds=settings.refresh_token_ttl_seconds),
    )
    db.add(session)
    await db.flush()
    await record_audit(db, "auth.session_created", user_id=user.id)
    access, ttl = create_access_token(user.id, user.email, session.id)
    return access, refresh, ttl


async def authenticate(db: AsyncSession, email: str, password: str) -> User:
    user = await db.scalar(select(User).where(User.email == email.lower()))
    # Uniform timing: verify against a dummy hash when user is unknown.
    verified = verify_password(password, user.password_hash if user else DUMMY_PASSWORD_HASH)
    if user is None or not verified:
        await run_in_threadpool(record_metric, "login_failure")
        await record_audit(db, "auth.login_failed", user_id=user.id if user else None)
        await db.commit()
        raise unauthorized("Invalid email or password")
    if not user.is_active or user.deleted_at is not None:
        raise unauthorized("Account not available")
    if get_settings().is_production and not user.email_verified:
        raise unauthorized("Invalid email or password")
    await record_audit(db, "auth.login", user_id=user.id)
    return user


async def rotate_refresh_token(db: AsyncSession, refresh_token: str) -> tuple[User, str, str, int]:
    token_hash = hash_refresh_token(refresh_token)
    session = await db.scalar(
        select(Session).where(Session.refresh_token_hash == token_hash).with_for_update()
    )
    if session is None:
        raise unauthorized("Invalid refresh token")
    now = datetime.now(UTC)
    if session.revoked_at is not None:
        await run_in_threadpool(record_metric, "refresh_reuse")
        # Refresh-token reuse detected: revoke the whole chain (theft protection).
        await db.execute(update(Session).where(Session.user_id == session.user_id).values(revoked_at=now))
        await record_audit(db, "auth.refresh_reuse_detected", user_id=session.user_id)
        await db.commit()  # security write must persist even though we raise
        raise unauthorized("Refresh token reuse detected; all sessions revoked")
    if ensure_aware(session.expires_at) <= now:
        raise unauthorized("Refresh token expired")
    if not refresh_token_matches(refresh_token, session.refresh_token_hash):
        raise unauthorized("Invalid refresh token")

    user = await db.scalar(select(User).where(User.id == session.user_id))
    if user is None or not user.is_active or user.deleted_at is not None:
        raise unauthorized("Account not available")

    new_refresh = generate_refresh_token()
    new_session = Session(
        user_id=user.id,
        refresh_token_hash=hash_refresh_token(new_refresh),
        device_name=session.device_name,
        expires_at=session.expires_at,
    )
    db.add(new_session)
    await db.flush()
    session.revoked_at = now
    session.replaced_by_id = new_session.id
    access, ttl = create_access_token(user.id, user.email, new_session.id)
    return user, access, new_refresh, ttl


async def logout(db: AsyncSession, refresh_token: str) -> None:
    token_hash = hash_refresh_token(refresh_token)
    session = await db.scalar(
        select(Session).where(Session.refresh_token_hash == token_hash).with_for_update()
    )
    if session is not None:
        now = datetime.now(UTC)
        if session.replaced_by_id is not None:
            # A refresh may have won a concurrent logout. Revoke descendants safely.
            await db.execute(update(Session).where(Session.user_id == session.user_id).values(revoked_at=now))
        else:
            session.revoked_at = now
        await record_audit(db, "auth.logout", user_id=session.user_id)


async def request_password_reset(db: AsyncSession, email: str) -> str | None:
    """Returns the dev token when out of production (no SMTP configured)."""
    user = await db.scalar(select(User).where(User.email == email.lower()))
    if user is None or user.deleted_at is not None:
        return None  # do not leak account existence
    token = secrets.token_urlsafe(32)
    user.password_reset_token_hash = _hash_token(token)
    user.password_reset_expires_at = datetime.now(UTC) + RESET_TOKEN_TTL
    await record_audit(db, "auth.password_reset_requested", user_id=user.id)
    return token


async def confirm_password_reset(db: AsyncSession, token: str, new_password: str) -> None:
    token_hash = _hash_token(token)
    user = await db.scalar(select(User).where(User.password_reset_token_hash == token_hash))
    if (
        user is None
        or user.password_reset_expires_at is None
        or ensure_aware(user.password_reset_expires_at) <= utc_now()
    ):
        raise bad_request("invalid_reset_token", "Reset token is invalid or expired")
    user.password_hash = hash_password(new_password)
    user.password_reset_token_hash = None
    user.password_reset_expires_at = None
    await db.execute(update(Session).where(Session.user_id == user.id).values(revoked_at=datetime.now(UTC)))
    await record_audit(db, "auth.password_reset_completed", user_id=user.id)


async def verify_email(db: AsyncSession, token: str) -> None:
    token_hash = _hash_token(token)
    user = await db.scalar(select(User).where(User.email_verification_token_hash == token_hash))
    if (
        user is None
        or ensure_aware(user.email_verification_expires_at or (user.created_at + timedelta(hours=24)))
        <= utc_now()
    ):
        raise bad_request("invalid_verification_token", "Verification token is invalid")
    user.email_verified = True
    user.email_verification_token_hash = None
    user.email_verification_expires_at = None
    await record_audit(db, "auth.email_verified", user_id=user.id)


async def request_email_verification(db: AsyncSession, email: str) -> str | None:
    user = await db.scalar(select(User).where(User.email == email.lower(), User.is_active.is_(True)))
    if user is None or user.email_verified:
        return None
    token = secrets.token_urlsafe(32)
    user.email_verification_token_hash = _hash_token(token)
    user.email_verification_expires_at = utc_now() + timedelta(hours=24)
    await record_audit(db, "auth.email_verification_requested", user_id=user.id)
    return token


async def delete_account(db: AsyncSession, user: User, password: str) -> User:
    if not verify_password(password, user.password_hash):
        raise unauthorized("Invalid password")
    now = datetime.now(UTC)
    from app.modules.audit.models import AuditEvent
    from app.modules.locations.router import Location
    from app.modules.media.models import DeletionTask, MediaUpload
    from app.modules.outfits.models import Outfit, OutfitHistory, OutfitItem
    from app.modules.privacy.models import UserConsent
    from app.modules.recommendations.models import Recommendation, RecommendationFeedback, RecommendationItem
    from app.modules.wardrobe.models import Garment, GarmentIdentificationCandidate, GarmentImage
    from app.modules.weather.router import WeatherSnapshot

    uid = user.id
    db.add_all(
        [
            DeletionTask(prefix=f"users/{uid}/", not_before=now),
            DeletionTask(
                prefix=f"users/{uid}/",
                not_before=now + timedelta(seconds=get_settings().s3_presign_ttl_seconds + 60),
            ),
        ]
    )
    garments = select(Garment.id).where(Garment.user_id == uid)
    outfits = select(Outfit.id).where(Outfit.user_id == uid)
    recommendations = select(Recommendation.id).where(Recommendation.user_id == uid)
    for model, predicate in [
        (GarmentImage, GarmentImage.garment_id.in_(garments)),
        (GarmentIdentificationCandidate, GarmentIdentificationCandidate.garment_id.in_(garments)),
        (OutfitItem, OutfitItem.outfit_id.in_(outfits)),
        (RecommendationItem, RecommendationItem.recommendation_id.in_(recommendations)),
    ]:
        await db.execute(delete(model).where(predicate))
    user_models: list[Any] = [
        RecommendationFeedback,
        OutfitHistory,
        Recommendation,
        Outfit,
        Garment,
        MediaUpload,
        Location,
        WeatherSnapshot,
        UserConsent,
        NotificationPreference,
        UserPreference,
        Session,
    ]
    for model in user_models:
        await db.execute(delete(model).where(model.user_id == uid))
    await db.execute(update(AuditEvent).where(AuditEvent.user_id == uid).values(user_id=None, ip_hash=None))
    await record_audit(db, "user.deleted")
    await db.execute(delete(User).where(User.id == uid))
    return user
