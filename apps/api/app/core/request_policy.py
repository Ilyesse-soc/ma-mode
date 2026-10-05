"""Bounded HTTP bodies and shared, differentiated IP/account request budgets."""

import asyncio
import hashlib
import hmac
import json
import secrets
from contextlib import suppress

import jwt
from limits import parse
from limits.storage import storage_from_string
from limits.strategies import MovingWindowRateLimiter
from starlette.concurrency import run_in_threadpool
from starlette.responses import JSONResponse

from app.core.config import get_settings
from app.core.security import decode_access_token


def check_json_tree(value, depth=0):
    if depth > 16:
        raise ValueError("JSON too deep")
    if isinstance(value, dict):
        for key, item in value.items():
            if len(key) > 120:
                raise ValueError("JSON key too long")
            check_json_tree(item, depth + 1)
    elif isinstance(value, list):
        if len(value) > 1000:
            raise ValueError("JSON array too large")
        for item in value:
            check_json_tree(item, depth + 1)


class RequestPolicyMiddleware:
    def __init__(self, app):
        self.app = app
        settings = get_settings()
        self.secret = settings.rate_limit_key_secret.encode() or secrets.token_bytes(32)
        options = (
            {"socket_timeout": 2, "socket_connect_timeout": 2}
            if settings.rate_limit_storage_uri.startswith(("redis:", "rediss:"))
            else {}
        )
        self.limiter = MovingWindowRateLimiter(
            storage_from_string(settings.rate_limit_storage_uri, **options)
        )

    def key(self, value):
        return hmac.new(self.secret, value.encode(), hashlib.sha256).hexdigest()

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        settings = get_settings()
        path = scope["path"]
        headers = dict(scope.get("headers", []))

        async def reject(status, code):
            response = JSONResponse(
                {"error": {"code": code, "message": code.replace("_", " ")}},
                status_code=status,
                headers={"Cache-Control": "no-store", "Retry-After": "60"}
                if status == 429
                else {"Cache-Control": "no-store"},
            )
            await response(scope, receive, send)

        ip = (scope.get("client") or ("unknown", 0))[0]
        try:
            if not await run_in_threadpool(
                self.limiter.hit, parse(settings.rate_limit_default), "ip", self.key(ip)
            ):
                return await reject(429, "rate_limited")
        except Exception:
            return await reject(503, "rate_limit_unavailable")

        limit = (
            settings.max_upload_bytes + 65536
            if path.endswith("/media/upload")
            else settings.max_json_body_bytes
        )
        try:
            if int(headers.get(b"content-length", b"0")) > limit:
                return await reject(413, "body_too_large")
        except ValueError:
            return await reject(400, "invalid_content_length")
        body = bytearray()
        try:
            async with asyncio.timeout(20):
                while True:
                    event = await receive()
                    if event["type"] == "http.disconnect":
                        return
                    body.extend(event.get("body", b""))
                    if len(body) > limit:
                        return await reject(413, "body_too_large")
                    if not event.get("more_body", False):
                        break
        except TimeoutError:
            return await reject(408, "request_timeout")
        payload = {}
        if body and b"json" in headers.get(b"content-type", b""):
            try:
                payload = json.loads(body)
                check_json_tree(payload)
                if not isinstance(payload, dict):
                    return await reject(422, "invalid_payload")
            except (ValueError, RecursionError, UnicodeError):
                return await reject(422, "invalid_payload")
        identity = None
        if isinstance(payload.get("email"), str):
            identity = payload["email"].strip().lower()
        elif isinstance(payload.get("refresh_token"), str):
            identity = payload["refresh_token"]
        elif isinstance(payload.get("token"), str):
            identity = payload["token"]
        elif b"authorization" in headers:
            with suppress(jwt.PyJWTError, ValueError, KeyError, UnicodeError):
                identity = decode_access_token(headers[b"authorization"].decode().removeprefix("Bearer "))[
                    "sub"
                ]
        rate = None
        if "/auth/" in path:
            rate = settings.rate_limit_account
        elif "/media/" in path or path.endswith("/images"):
            rate = settings.rate_limit_upload
        elif path.endswith("/identify/barcode") or "/product-search/" in path:
            rate = settings.rate_limit_barcode
        elif "/identify/" in path or path.endswith("/recommendations/generate"):
            rate = settings.rate_limit_ai
        if rate:
            try:
                for category, subject in [("ip", ip), ("account", identity)]:
                    if subject and not await run_in_threadpool(
                        self.limiter.hit, parse(rate), path, category, self.key(subject)
                    ):
                        return await reject(429, "rate_limited")
            except Exception:
                return await reject(503, "rate_limit_unavailable")

        delivered = False

        async def replay():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        async def monitored_send(message):
            if message["type"] == "http.response.start":
                from app.core.monitoring import record_metric

                status = message["status"]
                if status >= 500:
                    await run_in_threadpool(record_metric, "http_5xx")
                    if "/identify/" in path:
                        await run_in_threadpool(record_metric, "ai_failure")
                    if "/media/" in path:
                        await run_in_threadpool(record_metric, "s3_failure")
                elif status in {401, 403}:
                    await run_in_threadpool(record_metric, "http_401_403")
            await send(message)

        await self.app(scope, replay, monitored_send)
