from datetime import timedelta

from sqlalchemy import select

from app.core.time import utc_now
from app.db.session import get_session_factory
from app.modules.media import cleanup
from app.modules.media.models import DeletionTask
from app.modules.users.models import Session, User
from app.modules.wardrobe.models import Garment
from tests.conftest import BASE, auth, register_user


async def test_sql_erasure_session_revocation_and_durable_s3_retry(client, monkeypatch):
    email, access, refresh = await register_user(client)
    await client.post(
        f"{BASE}/garments",
        headers=auth(access),
        json={"category_slug": "top_other", "name": "Private", "color": "white"},
    )
    response = await client.request(
        "DELETE", f"{BASE}/me", headers=auth(access), json={"password": "super-secret-10"}
    )
    assert response.status_code == 200
    assert (await client.get(f"{BASE}/me", headers=auth(access))).status_code == 401
    assert (await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})).status_code == 401
    async with get_session_factory()() as db:
        assert await db.scalar(select(User).where(User.email == email)) is None
        assert not list(await db.scalars(select(Session)))
        assert not list(await db.scalars(select(Garment)))
        tasks = list(await db.scalars(select(DeletionTask)))
        assert len(tasks) == 2

        def outage(_):
            raise OSError("S3 temporarily unavailable")

        monkeypatch.setattr(cleanup, "purge", outage)
        await cleanup.run_once(db)
        assert tasks[0].completed_at is None
        pending = [t for t in tasks if t.attempts]
        assert len(pending) == 1
        pending[0].not_before = utc_now() - timedelta(seconds=1)
        await db.commit()
        removed = []
        monkeypatch.setattr(cleanup, "purge", removed.append)
        await cleanup.run_once(db)
        assert pending[0].completed_at is not None and removed
