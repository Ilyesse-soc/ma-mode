"""Aggregate counters and bounded SMTP alerts; never attach identities or bodies."""

import smtplib
import ssl
import time
from collections import defaultdict, deque
from email.message import EmailMessage

from app.core.config import get_settings
from app.core.logging import get_logger

THRESHOLDS = {
    "http_5xx": 10,
    "http_401_403": 100,
    "login_failure": 30,
    "refresh_reuse": 1,
    "db_failure": 1,
    "s3_failure": 5,
    "ai_failure": 10,
}
_events: dict[str, deque] = defaultdict(deque)
_last_alert: dict[str, float] = {}


def _redis():
    settings = get_settings()
    if settings.rate_limit_storage_uri.startswith("memory"):
        return None
    import redis

    return redis.Redis.from_url(settings.rate_limit_storage_uri, socket_connect_timeout=2, socket_timeout=2)


def record_metric(name: str):
    if name not in THRESHOLDS:
        raise ValueError("Unknown metric")
    try:
        client = _redis()
        if client is None:
            queue = _events[name]
            now = time.time()
            while queue and queue[0] < now - 300:
                queue.popleft()
            if len(queue) < 1000:
                queue.append(now)
        else:
            bucket = int(time.time() // 300)
            key = f"dressly:metric:{name}:{bucket}"
            client.incr(key)
            client.expire(key, 900)
    except Exception:
        get_logger("monitoring").error("monitoring.counter_unavailable", metric=name)


def check_alerts():
    settings = get_settings()
    if not settings.security_alert_email or not settings.smtp_host:
        return
    client = _redis()
    now = time.time()
    for name, threshold in THRESHOLDS.items():
        if client is None:
            count = sum(timestamp > now - 300 for timestamp in _events[name])
        else:
            bucket = int(now // 300)
            count = sum(
                int(client.get(f"dressly:metric:{name}:{value}") or 0) for value in (bucket, bucket - 1)
            )
        if count < threshold:
            continue
        if client is not None:
            if not client.set(f"dressly:alert:{name}", "pending", nx=True, ex=900):
                continue
        elif now - _last_alert.get(name, 0) < 900:
            continue
        message = EmailMessage()
        message["From"] = settings.smtp_from
        message["To"] = settings.security_alert_email
        message["Subject"] = f"Dressly security signal: {name}"
        message.set_content(
            f"Environment: {settings.environment}\nSignal: {name}\nCount: {count}\n"
            "Inspect redacted logs and the incident response runbook. No personal data is attached."
        )
        try:
            with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as smtp:
                smtp.starttls(context=ssl.create_default_context())
                if settings.smtp_username:
                    smtp.login(settings.smtp_username, settings.smtp_password)
                smtp.send_message(message)
            _last_alert[name] = now
        except (smtplib.SMTPException, OSError):
            if client is not None:
                client.delete(f"dressly:alert:{name}")
            get_logger("monitoring").error("monitoring.alert_delivery_failed", metric=name)
