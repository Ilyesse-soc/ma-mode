"""Opt-in real Sentry instrumentation with privacy filters."""

from app.core.config import get_settings
from app.core.logging import redact


def before_send(event, hint):
    event = redact(event)
    event.pop("user", None)
    event.pop("request", None)
    # Do not transmit locals, request bodies, images or raw provider responses.
    for exception in event.get("exception", {}).get("values", []):
        exception["value"] = exception.get("type", "Error")
        for frame in exception.get("stacktrace", {}).get("frames", []):
            frame.pop("vars", None)
            for key in ("pre_context", "post_context", "context_line", "abs_path"):
                frame.pop(key, None)
    return event


def configure_error_tracking():
    settings = get_settings()
    if not settings.sentry_dsn:
        return
    import sentry_sdk

    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.environment,
        release="alamode-api@1.0.0",
        send_default_pii=False,
        include_local_variables=False,
        traces_sample_rate=0,
        before_send=before_send,
        before_breadcrumb=lambda crumb, _: redact(crumb),
    )
