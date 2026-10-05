from datetime import timedelta

import sentry_sdk
from sentry_sdk.transport import Transport
from sqlalchemy import select

from app.core.observability import before_send
from app.core.time import utc_now
from app.db.session import get_session_factory
from app.modules.users import service
from app.modules.users.models import User
from tests.conftest import BASE, auth, register_user


async def test_logout_of_rotated_token_revokes_successor(client):
    _, _, refresh = await register_user(client)
    new = (await client.post(f"{BASE}/auth/refresh", json={"refresh_token": refresh})).json()
    assert (await client.post(f"{BASE}/auth/logout", json={"refresh_token": refresh})).status_code == 200
    assert (await client.get(f"{BASE}/me", headers=auth(new["access_token"]))).status_code == 401


async def test_verification_expires_resends_and_is_single_use(client):
    email, _, _ = await register_user(client)
    async with get_session_factory()() as db:
        token = await service.request_email_verification(db, email)
        user = await db.scalar(select(User).where(User.email == email))
        user.email_verification_expires_at = utc_now() - timedelta(seconds=1)
        await db.commit()
    assert (await client.post(f"{BASE}/auth/verify-email", json={"token": token})).status_code == 400
    async with get_session_factory()() as db:
        new = await service.request_email_verification(db, email)
        await db.commit()
    assert (await client.post(f"{BASE}/auth/verify-email", json={"token": new})).status_code == 200
    assert (await client.post(f"{BASE}/auth/verify-email", json={"token": new})).status_code == 400


def test_real_sentry_sdk_captures_and_scrubs_error_without_external_delivery():
    received = []

    class MemoryTransport(Transport):
        def capture_envelope(self, envelope):
            for item in envelope.items:
                event = item.get_event()
                if event:
                    received.append(event)

    sdk_client = sentry_sdk.Client(
        dsn="https://public@example.invalid/1",
        transport=MemoryTransport,
        before_send=before_send,
        send_default_pii=False,
        include_local_variables=False,
    )
    with sentry_sdk.isolation_scope() as scope:
        scope.set_client(sdk_client)
        try:
            raise RuntimeError("private-error-marker")
        except RuntimeError:
            sentry_sdk.capture_exception()
    sdk_client.close()
    assert received
    assert "private-error-marker" not in str(received)
    assert received[0]["exception"]["values"][0]["type"] == "RuntimeError"
