"""Password hashing, JWT access/refresh tokens, refresh-token rotation.

Passwords: Argon2id (with optional server-side pepper).
Tokens: short-lived RS256 access JWT + opaque refresh token stored hashed (SHA-256)
in the `sessions` table with rotation on every use.
"""

import hashlib
import hmac
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from argon2.low_level import Type

from app.core.config import get_settings

_ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4, type=Type.ID)
DUMMY_PASSWORD_HASH = _ph.hash(secrets.token_urlsafe(32))


def hash_password(password: str) -> str:
    settings = get_settings()
    return _ph.hash(password + settings.bcrypt_like_pepper)


def verify_password(password: str, password_hash: str) -> bool:
    settings = get_settings()
    try:
        return _ph.verify(password_hash, password + settings.bcrypt_like_pepper)
    except (VerificationError, InvalidHashError):
        return False


def create_access_token(user_id: uuid.UUID, email: str, session_id: uuid.UUID) -> tuple[str, int]:
    settings = get_settings()
    ttl = settings.access_token_ttl_seconds
    now = datetime.now(UTC)
    claims = {
        "sub": str(user_id),
        "sid": str(session_id),
        "iss": "alamode-api",
        "aud": "alamode-mobile",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=ttl)).timestamp()),
        "jti": secrets.token_hex(8),
        "type": "access",
    }
    token = jwt.encode(claims, settings.jwt_private_key_pem, algorithm="RS256")
    return token, ttl


def decode_access_token(token: str) -> dict:
    settings = get_settings()
    payload = jwt.decode(
        token,
        settings.jwt_public_key_pem,
        algorithms=["RS256"],
        issuer="alamode-api",
        audience="alamode-mobile",
        options={"require": ["sub", "sid", "exp", "iat", "iss", "aud", "jti"]},
    )
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("wrong token type")
    return payload


def generate_refresh_token() -> str:
    """Opaque URL-safe refresh token (never stored in clear server-side)."""
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def refresh_token_matches(token: str, token_hash: str) -> bool:
    return hmac.compare_digest(hash_refresh_token(token), token_hash)
