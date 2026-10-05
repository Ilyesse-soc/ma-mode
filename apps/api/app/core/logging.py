"""Structured logging setup. Never log PII (emails, tokens, coordinates)."""

import logging
import re
import sys

import structlog

from app.core.config import get_settings

_SENSITIVE = re.compile(
    r"password|authorization|cookie|token|api.?key|secret|email|latitude|longitude|^lat$|^lon$|ocr|image|signed.?url",
    re.I,
)


def redact(value):
    if isinstance(value, dict):
        return {
            key: "[REDACTED]" if _SENSITIVE.search(str(key)) else redact(item) for key, item in value.items()
        }
    if isinstance(value, (list, tuple)):
        return [redact(item) for item in value]
    if isinstance(value, str):
        value = re.sub(
            r"https?://[^\s\"<>]+",
            lambda m: m.group(0).split("?")[0] + ("?[REDACTED]" if "?" in m.group(0) else ""),
            value,
        )
        value = re.sub(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[EMAIL]", value)
        value = re.sub(r"(?i)Bearer\s+\S+", "Bearer [REDACTED]", value)
        value = re.sub(
            r"(?i)(password|refresh_token|access_token|api_key|secret|latitude|longitude)\s*[:=]\s*[^\s,;]+",
            r"\1=[REDACTED]",
            value,
        )
        value = re.sub(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[JWT]", value)
    return value


def redact_event(_, __, event):
    return redact(event)


class RedactionFilter(logging.Filter):
    def filter(self, record):
        record.msg = redact(record.getMessage())
        record.args = ()
        # Exception text may contain arbitrary provider bodies or credentials.
        # Detailed frames are sent through the scrubbed error-tracking channel.
        record.exc_info = None
        record.exc_text = None
        return True


def configure_logging() -> None:
    settings = get_settings()
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=settings.log_level.upper(),
    )
    for handler in logging.getLogger().handlers:
        handler.addFilter(RedactionFilter())
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("botocore").setLevel(logging.WARNING)
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            redact_event,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.getLevelName(settings.log_level.upper())),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    return structlog.get_logger(name)
