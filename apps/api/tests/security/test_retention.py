import uuid
from datetime import timedelta

from sqlalchemy import select

from app.core.time import utc_now
from app.db.session import get_session_factory
from app.domain.enums import IdentificationSource
from app.modules.media.cleanup import run_once
from app.modules.wardrobe.models import GarmentIdentificationCandidate
from tests.conftest import BASE, auth, register_user


async def test_processing_proposals_expire_and_legacy_ocr_is_scrubbed(client):
    _, access, _ = await register_user(client)
    response = await client.post(
        f"{BASE}/garments",
        headers=auth(access),
        json={"category_slug": "top_other", "name": "Retained wardrobe item", "color": "white"},
    )
    garment_id = uuid.UUID(response.json()["id"])
    async with get_session_factory()() as db:
        old = GarmentIdentificationCandidate(
            garment_id=garment_id,
            source=IdentificationSource.PHOTO_VISION,
            confidence=0.5,
            proposed={},
            created_at=utc_now() - timedelta(days=8),
        )
        fresh = GarmentIdentificationCandidate(
            garment_id=garment_id,
            source=IdentificationSource.LABEL_OCR,
            confidence=0.5,
            proposed={},
            raw_excerpt="legacy private label text",
        )
        db.add_all([old, fresh])
        await db.commit()
        await run_once(db)
        rows = list(await db.scalars(select(GarmentIdentificationCandidate)))
        assert len(rows) == 1 and rows[0].id == fresh.id
        assert rows[0].raw_excerpt is None
    assert (await client.get(f"{BASE}/garments/{garment_id}", headers=auth(access))).status_code == 200
