"""Shared provider quota; no user identities or response bodies in Redis."""

import time
from functools import lru_cache

from limits import parse
from limits.storage import storage_from_string
from limits.strategies import MovingWindowRateLimiter

from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.monitoring import _redis

_blocked_until = 0.0


def unavailable(seconds=60):
    return ApiError(
        503,
        "barcode_rate_limited",
        "Recherche code-barres temporairement indisponible. Utilise une photo ou la saisie manuelle.",
        {"retry_after_seconds": max(1, min(86400, int(seconds)))},
    )


@lru_cache(maxsize=4)
def limiter(uri):
    options = (
        {"socket_timeout": 2, "socket_connect_timeout": 2} if uri.startswith(("redis:", "rediss:")) else {}
    )
    return MovingWindowRateLimiter(storage_from_string(uri, **options))


def reserve(kind="lookup"):
    settings = get_settings()
    if settings.upcitemdb_mode == "paid" and settings.upcitemdb_api_key:
        return
    try:
        client = _redis()
        remaining = client.ttl("dressly:upc:cooldown") if client else int(_blocked_until - time.time())
        if remaining > 0:
            raise unavailable(remaining)
        counter = limiter(settings.rate_limit_storage_uri)
        for limit, scope in [("100/day", "combined"), ("6/minute" if kind == "lookup" else "2/minute", kind)]:
            rate = parse(limit)
            if not counter.hit(rate, "dressly-upcitemdb", scope):
                reset, _ = counter.get_window_stats(rate, "dressly-upcitemdb", scope)
                raise unavailable(int(reset - time.time()) + 1)
    except ApiError:
        raise
    except Exception:
        raise unavailable() from None


def remember_headers(headers, status):
    global _blocked_until
    # Provider metadata is shared operational state, with no account identifiers.
    client = _redis()
    metadata = {}
    for header in ("x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset"):
        try:
            value = int(headers.get(header, ""))
            if 0 <= value <= 10_000_000_000:
                metadata[header] = value
        except (ValueError, TypeError):
            continue
    if client and metadata:
        client.hset("dressly:upc:quota", mapping=metadata)
        client.expire("dressly:upc:quota", 86400)
    if status != 429 and headers.get("x-ratelimit-remaining") != "0":
        return
    try:
        seconds = int(
            headers.get("retry-after") or max(1, int(headers.get("x-ratelimit-reset", "0")) - time.time())
        )
    except (ValueError, TypeError):
        seconds = 60
    seconds = max(1, min(86400, seconds))
    _blocked_until = time.time() + seconds
    if client:
        client.setex("dressly:upc:cooldown", seconds, "1")
