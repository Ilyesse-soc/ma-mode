"""Run regularly: durable deletion retries and explicit bounded retention."""

import re
from datetime import timedelta

from sqlalchemy import delete, select, update
from starlette.concurrency import run_in_threadpool

from app.core.config import get_settings
from app.core.logging import get_logger
from app.core.time import utc_now
from app.modules.audit.models import AuditEvent
from app.modules.media import storage
from app.modules.media.models import DeletionTask, MediaUpload
from app.modules.users.models import Session, User
from app.modules.wardrobe.models import GarmentIdentificationCandidate, GarmentImage
from app.modules.weather.router import WeatherSnapshot


def purge(prefix):
    if not re.fullmatch(
        r"users/[0-9a-f-]{36}/(?:quarantine/|validated/)?(?:[0-9a-f]{32}\.(?:jpg|jpeg|png|webp|bin))?", prefix
    ):
        raise ValueError("Invalid deletion prefix")
    if not prefix.endswith("/"):
        return storage.delete_object(prefix)
    client = storage._client()
    settings = get_settings()
    for page in client.get_paginator("list_objects_v2").paginate(Bucket=settings.s3_bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            client.delete_object(Bucket=settings.s3_bucket, Key=item["Key"])


async def run_once(db):
    settings = get_settings()
    now = utc_now()
    tasks = list(
        await db.scalars(
            select(DeletionTask)
            .where(DeletionTask.completed_at.is_(None), DeletionTask.not_before <= now)
            .limit(100)
            .with_for_update(skip_locked=True)
        )
    )
    for task in tasks:
        task.attempts += 1
        try:
            await run_in_threadpool(purge, task.prefix)
            task.completed_at = now
        except Exception:
            from app.core.monitoring import record_metric

            await run_in_threadpool(record_metric, "s3_failure")
            task.not_before = now + timedelta(seconds=min(3600, 60 * 2 ** min(task.attempts, 6)))
            get_logger("cleanup").error("storage.deletion_retry", attempts=task.attempts)
    await db.execute(
        delete(AuditEvent).where(AuditEvent.created_at < now - timedelta(days=settings.audit_retention_days))
    )
    await db.execute(
        delete(WeatherSnapshot).where(
            WeatherSnapshot.created_at < now - timedelta(days=settings.weather_retention_days)
        )
    )
    await db.execute(delete(DeletionTask).where(DeletionTask.completed_at < now - timedelta(days=1)))
    # Proposals are transient processing metadata, not permanent wardrobe fields.
    await db.execute(
        delete(GarmentIdentificationCandidate).where(
            GarmentIdentificationCandidate.created_at < now - timedelta(days=settings.draft_retention_days)
        )
    )
    await db.execute(update(GarmentIdentificationCandidate).values(raw_excerpt=None))
    # Keep rotation ancestry until its absolute expiry so replay detection remains effective.
    await db.execute(delete(Session).where(Session.expires_at < now - timedelta(days=1)))
    await db.execute(
        update(User)
        .where(User.password_reset_expires_at < now)
        .values(password_reset_token_hash=None, password_reset_expires_at=None)
    )
    await db.execute(
        update(User)
        .where(User.email_verification_expires_at < now)
        .values(email_verification_token_hash=None, email_verification_expires_at=None)
    )
    orphans = list(
        await db.scalars(
            select(MediaUpload)
            .where(
                MediaUpload.created_at < now - timedelta(days=settings.draft_retention_days),
                ~MediaUpload.object_key.in_(select(GarmentImage.object_key)),
            )
            .limit(100)
        )
    )
    for upload in orphans:
        db.add(DeletionTask(prefix=upload.object_key, not_before=now))
        if "/quarantine/" in upload.object_key:
            canonical = upload.object_key.replace("/quarantine/", "/validated/").rsplit(".", 1)[0] + ".jpg"
            db.add(DeletionTask(prefix=canonical, not_before=now))
        await db.delete(upload)
    await db.commit()
    from app.core.monitoring import check_alerts

    await run_in_threadpool(check_alerts)
