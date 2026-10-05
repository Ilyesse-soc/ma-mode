"""Authentication dependencies: current user extraction from RS256 access JWT."""

import uuid

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import unauthorized
from app.core.security import decode_access_token
from app.core.time import ensure_aware, utc_now
from app.db.session import get_db
from app.modules.users.models import Session, User

_bearer = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    if credentials is None:
        raise unauthorized()
    try:
        payload = decode_access_token(credentials.credentials)
        user_id = uuid.UUID(payload["sub"])
        session_id = uuid.UUID(payload["sid"])
    except (jwt.PyJWTError, ValueError, KeyError):
        raise unauthorized("Invalid or expired access token") from None
    user = await db.scalar(select(User).where(User.id == user_id))
    session = await db.scalar(select(Session).where(Session.id == session_id, Session.user_id == user_id))
    if session is None or session.revoked_at is not None or ensure_aware(session.expires_at) <= utc_now():
        raise unauthorized("Session expired or revoked")
    if user is None or not user.is_active or user.deleted_at is not None:
        raise unauthorized("Account not available")
    return user
