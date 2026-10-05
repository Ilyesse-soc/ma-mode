"""Consistent API error model and handlers."""

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging import get_logger


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, message: str, details: dict | None = None):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or {}


def _payload(code: str, message: str, details: dict | None = None) -> dict:
    return {"error": {"code": code, "message": message, "details": details or {}}}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def api_error_handler(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=_payload(exc.code, exc.message, exc.details),
            headers={"Retry-After": str(exc.details["retry_after_seconds"])}
            if isinstance(exc.details.get("retry_after_seconds"), int)
            else None,
        )

    @app.exception_handler(StarletteHTTPException)
    async def http_error_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = "not_found" if exc.status_code == status.HTTP_404_NOT_FOUND else "http_error"
        return JSONResponse(status_code=exc.status_code, content=_payload(code, str(exc.detail)))

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            content=_payload(
                "validation_error",
                "Invalid request payload",
                {"errors": [{"loc": list(e["loc"]), "type": e["type"]} for e in exc.errors()]},
            ),
        )

    @app.exception_handler(Exception)
    async def unexpected_error_handler(_: Request, exc: Exception) -> JSONResponse:
        from sqlalchemy.exc import SQLAlchemyError
        from starlette.concurrency import run_in_threadpool

        from app.core.monitoring import record_metric

        if isinstance(exc, SQLAlchemyError):
            await run_in_threadpool(record_metric, "db_failure")
        await run_in_threadpool(record_metric, "http_5xx")
        get_logger("errors").error("api.unexpected_error", error_type=type(exc).__name__)
        return JSONResponse(
            status_code=500,
            content=_payload("internal_error", "Unexpected server error"),
            headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
        )


# Common errors -----------------------------------------------------------------


def not_found(resource: str) -> ApiError:
    return ApiError(status.HTTP_404_NOT_FOUND, f"{resource}_not_found", f"{resource} not found")


def forbidden(message: str = "You do not have access to this resource") -> ApiError:
    return ApiError(status.HTTP_403_FORBIDDEN, "forbidden", message)


def unauthorized(message: str = "Authentication required") -> ApiError:
    return ApiError(status.HTTP_401_UNAUTHORIZED, "unauthorized", message)


def conflict(code: str, message: str) -> ApiError:
    return ApiError(status.HTTP_409_CONFLICT, code, message)


def bad_request(code: str, message: str) -> ApiError:
    return ApiError(status.HTTP_400_BAD_REQUEST, code, message)


def upstream_unavailable(service: str) -> ApiError:
    return ApiError(
        status.HTTP_503_SERVICE_UNAVAILABLE,
        f"{service}_unavailable",
        f"The {service} service is temporarily unavailable",
    )
