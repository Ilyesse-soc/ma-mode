"""Auth and profile routes."""

from fastapi import APIRouter, BackgroundTasks, Depends, Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import not_found, upstream_unavailable
from app.core.mail import send_account_link
from app.db.session import get_db
from app.modules.users import service
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User, UserPreference
from app.modules.users.schemas import (
    DeleteAccountIn,
    LoginRequest,
    MessageOut,
    OnboardingStepIn,
    PasswordResetConfirmIn,
    PasswordResetRequestIn,
    PreferencesIn,
    PreferencesOut,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
    UpdateProfileRequest,
    UserOut,
    VerifyEmailIn,
)

router = APIRouter(tags=["auth"])
limiter = Limiter(key_func=get_remote_address)


@router.put("/me/onboarding", response_model=UserOut)
async def complete_onboarding_step(
    payload: OnboardingStepIn,
    current: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    locked = await db.scalar(select(User).where(User.id == current.id).with_for_update())
    if locked is None:
        raise not_found("user")
    locked.onboarding_steps = list(dict.fromkeys([*(locked.onboarding_steps or []), payload.step]))
    await db.commit()
    return locked


def _rate(key: str) -> str:
    return getattr(get_settings(), key)


@router.post("/auth/register", response_model=TokenPair, status_code=201)
@limiter.limit(lambda: _rate("rate_limit_auth"))
async def register(
    request: Request,
    payload: RegisterRequest,
    background: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    if get_settings().is_production:
        existing = await db.scalar(select(User).where(User.email == payload.email.lower()))
        if existing is None:
            user, verification = await service.register_user(db, payload)
            await db.commit()
            background.add_task(send_account_link, user.email, verification, "verify")
        return JSONResponse(
            status_code=202, content={"message": "If registration is possible, an email will be sent"}
        )
    user, _verification = await service.register_user(db, payload)
    if get_settings().smtp_host:
        background.add_task(send_account_link, user.email, _verification, "verify")
    access, refresh, ttl = await service.create_session(db, user, device_name=None)
    await db.commit()
    return TokenPair(access_token=access, refresh_token=refresh, expires_in=ttl)


@router.post("/auth/login", response_model=TokenPair)
@limiter.limit(lambda: _rate("rate_limit_auth"))
async def login(request: Request, payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    user = await service.authenticate(db, payload.email, payload.password)
    access, refresh, ttl = await service.create_session(db, user, payload.device_name)
    await db.commit()
    return TokenPair(access_token=access, refresh_token=refresh, expires_in=ttl)


@router.post("/auth/refresh", response_model=TokenPair)
@limiter.limit(lambda: _rate("rate_limit_auth"))
async def refresh(request: Request, payload: RefreshRequest, db: AsyncSession = Depends(get_db)):
    _user, access, new_refresh, ttl = await service.rotate_refresh_token(db, payload.refresh_token)
    await db.commit()
    return TokenPair(access_token=access, refresh_token=new_refresh, expires_in=ttl)


@router.post("/auth/logout", response_model=MessageOut)
async def logout(payload: RefreshRequest, db: AsyncSession = Depends(get_db)):
    await service.logout(db, payload.refresh_token)
    await db.commit()
    return MessageOut(message="Logged out")


@router.post("/auth/revoke-all", response_model=MessageOut)
async def revoke_all(
    payload: DeleteAccountIn, current: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    from sqlalchemy import update

    from app.core.errors import unauthorized
    from app.core.security import verify_password
    from app.core.time import utc_now
    from app.modules.audit.models import record_audit
    from app.modules.users.models import Session

    if not verify_password(payload.password, current.password_hash):
        raise unauthorized("Invalid password")
    await db.execute(update(Session).where(Session.user_id == current.id).values(revoked_at=utc_now()))
    await record_audit(db, "auth.all_sessions_revoked", user_id=current.id)
    await db.commit()
    return MessageOut(message="All sessions revoked")


@router.post("/auth/password-reset/request", response_model=MessageOut)
@limiter.limit(lambda: _rate("rate_limit_auth"))
async def request_reset(
    request: Request,
    payload: PasswordResetRequestIn,
    background: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    settings = get_settings()
    if not settings.smtp_host and not (settings.environment == "development" and settings.allow_dev_tokens):
        raise upstream_unavailable("email")
    token = await service.request_password_reset(db, payload.email)
    await db.commit()
    if token:
        background.add_task(send_account_link, payload.email, token, "reset")
    dev_token = token if settings.environment == "development" and settings.allow_dev_tokens else None
    return MessageOut(message="If this email exists, a reset link has been sent", dev_token=dev_token)


@router.post("/auth/password-reset/confirm", response_model=MessageOut)
@limiter.limit(lambda: _rate("rate_limit_auth"))
async def confirm_reset(
    request: Request, payload: PasswordResetConfirmIn, db: AsyncSession = Depends(get_db)
):
    await service.confirm_password_reset(db, payload.token, payload.new_password)
    await db.commit()
    return MessageOut(message="Password updated; all sessions revoked")


@router.post("/auth/verify-email", response_model=MessageOut)
async def verify_email(payload: VerifyEmailIn, db: AsyncSession = Depends(get_db)):
    await service.verify_email(db, payload.token)
    await db.commit()
    return MessageOut(message="Email verified")


@router.post("/auth/verification/request", response_model=MessageOut)
async def request_verification(
    payload: PasswordResetRequestIn, background: BackgroundTasks, db: AsyncSession = Depends(get_db)
):
    if not get_settings().smtp_host:
        raise upstream_unavailable("email")
    token = await service.request_email_verification(db, payload.email)
    await db.commit()
    if token:
        background.add_task(send_account_link, payload.email, token, "verify")
    return MessageOut(message="If verification is needed, an email will be sent")


# --- Profile -----------------------------------------------------------------


@router.get("/me", response_model=UserOut)
async def get_me(current: User = Depends(get_current_user)):
    return current


@router.patch("/me", response_model=UserOut)
async def update_me(
    payload: UpdateProfileRequest,
    current: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if payload.first_name is not None:
        current.first_name = payload.first_name.strip()
    if payload.mannequin_presentation is not None:
        current.mannequin_presentation = payload.mannequin_presentation
    await db.commit()
    return current


@router.get("/me/preferences", response_model=PreferencesOut)
async def get_preferences(current: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    prefs = await db.scalar(select(UserPreference).where(UserPreference.user_id == current.id))
    if prefs is None:
        raise not_found("preferences")
    return PreferencesOut(
        preferred_styles=prefs.preferred_styles,
        liked_colors=prefs.liked_colors,
        avoided_colors=prefs.avoided_colors,
        cold_threshold_celsius=prefs.cold_threshold_celsius,
        hot_threshold_celsius=prefs.hot_threshold_celsius,
        learned_warmth_offset=prefs.learned_warmth_offset,
    )


@router.put("/me/preferences", response_model=PreferencesOut)
async def put_preferences(
    payload: PreferencesIn,
    current: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    prefs = await db.scalar(select(UserPreference).where(UserPreference.user_id == current.id))
    if prefs is None:
        prefs = UserPreference(user_id=current.id)
        db.add(prefs)
    prefs.preferred_styles = payload.preferred_styles
    prefs.liked_colors = payload.liked_colors
    prefs.avoided_colors = payload.avoided_colors
    prefs.cold_threshold_celsius = payload.cold_threshold_celsius
    prefs.hot_threshold_celsius = payload.hot_threshold_celsius
    await db.commit()
    return PreferencesOut(
        preferred_styles=prefs.preferred_styles,
        liked_colors=prefs.liked_colors,
        avoided_colors=prefs.avoided_colors,
        cold_threshold_celsius=prefs.cold_threshold_celsius,
        hot_threshold_celsius=prefs.hot_threshold_celsius,
        learned_warmth_offset=prefs.learned_warmth_offset,
    )


@router.delete("/me", response_model=MessageOut)
async def delete_me(
    payload: DeleteAccountIn,
    current: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await service.delete_account(db, current, payload.password)
    # Storage deletion is queued in a durable outbox; no imaginary worker.
    await db.commit()
    return MessageOut(message="Account deleted and sessions revoked")
