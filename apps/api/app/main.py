"""FastAPI application factory."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging, get_logger
from app.core.request_policy import RequestPolicyMiddleware
from app.db.session import dispose_engine, init_engine
from app.modules.locations.router import router as locations_router
from app.modules.media.router import router as media_router
from app.modules.notifications.router import router as notifications_router
from app.modules.outfits.router import router as outfits_router
from app.modules.privacy.router import router as privacy_router
from app.modules.product_search.router import router as product_search_router
from app.modules.recommendations.router import router as recommendations_router
from app.modules.users.router import limiter as auth_limiter
from app.modules.users.router import router as auth_router
from app.modules.wardrobe.router import router as wardrobe_router
from app.modules.weather.router import router as weather_router

log = get_logger("app")


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; frame-ancestors 'none'"
            if get_settings().is_production
            else "frame-ancestors 'none'"
        )
        response.headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()"
        if get_settings().is_production:
            response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
        return response


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging()
    from app.core.observability import configure_error_tracking

    configure_error_tracking()
    init_engine()
    if get_settings().is_production:
        from sqlalchemy import text
        from starlette.concurrency import run_in_threadpool

        from app.db.session import get_session_factory
        from app.modules.media.storage import verify_private_bucket

        await run_in_threadpool(verify_private_bucket)
        async with get_session_factory()() as db:
            privileged = await db.scalar(
                text(
                    "SELECT rolsuper OR rolcreaterole OR rolcreatedb "
                    "FROM pg_roles WHERE rolname = current_user"
                )
            )
            if privileged is not False:
                raise RuntimeError("Privileged application database role prohibited")
    log.info("app.started", environment=get_settings().environment)
    yield
    await dispose_engine()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.project_name,
        version="1.0.0",
        docs_url="/docs" if not settings.is_production else None,
        redoc_url=None,
        openapi_url="/openapi.json" if not settings.is_production else None,
        lifespan=lifespan,
    )

    app.state.limiter = auth_limiter

    def rate_limit_handler(request: Request, exc: Exception) -> Response:
        if not isinstance(exc, RateLimitExceeded):
            raise exc
        return _rate_limit_exceeded_handler(request, exc)

    app.add_exception_handler(RateLimitExceeded, rate_limit_handler)
    app.add_middleware(SlowAPIMiddleware)
    app.add_middleware(RequestPolicyMiddleware)
    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )
    register_error_handlers(app)

    prefix = settings.api_v1_prefix
    app.include_router(auth_router, prefix=prefix)
    app.include_router(wardrobe_router, prefix=prefix)
    app.include_router(outfits_router, prefix=prefix)
    app.include_router(weather_router, prefix=prefix)
    app.include_router(locations_router, prefix=prefix)
    app.include_router(recommendations_router, prefix=prefix)
    app.include_router(product_search_router, prefix=prefix)
    app.include_router(media_router, prefix=prefix)
    app.include_router(notifications_router, prefix=prefix)
    app.include_router(privacy_router, prefix=prefix)

    @app.get("/health", tags=["ops"])
    async def health() -> dict:
        return {"status": "ok"}

    @app.get("/readiness", tags=["ops"])
    async def readiness() -> dict:
        from sqlalchemy import text

        from app.db.session import get_session_factory

        try:
            async with get_session_factory()() as session:
                await session.execute(text("SELECT 1"))
            return {"status": "ready"}
        except Exception:
            from fastapi import status as http_status
            from fastapi.responses import JSONResponse

            return JSONResponse(
                status_code=http_status.HTTP_503_SERVICE_UNAVAILABLE,
                content={"status": "not_ready"},
            )  # type: ignore[return-value]

    return app


app = create_app()
