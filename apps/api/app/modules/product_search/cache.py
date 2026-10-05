"""Reuse only recent catalogue proposals belonging to the requesting account."""

from datetime import timedelta

from sqlalchemy import select

from app.core.config import get_settings
from app.core.time import utc_now
from app.domain.enums import IdentificationSource, IdentificationStatus
from app.modules.product_search.providers import ProductCandidate
from app.modules.wardrobe.models import Garment, GarmentIdentificationCandidate


async def barcode_candidates(db, user_id, barcode):
    rows = list(
        await db.scalars(
            select(GarmentIdentificationCandidate)
            .join(Garment)
            .where(
                Garment.user_id == user_id,
                Garment.barcode == barcode,
                GarmentIdentificationCandidate.source == IdentificationSource.BARCODE,
                GarmentIdentificationCandidate.status != IdentificationStatus.REJECTED,
                GarmentIdentificationCandidate.created_at
                > utc_now() - timedelta(seconds=get_settings().barcode_cache_ttl_seconds),
            )
            .order_by(GarmentIdentificationCandidate.created_at.desc())
            .limit(25)
        )
    )
    unique = []
    fingerprints = set()
    for row in rows:
        fingerprint = (row.proposed.get("name"), row.proposed.get("reference"), row.proposed.get("provider"))
        if fingerprint not in fingerprints:
            fingerprints.add(fingerprint)
            unique.append(row)
        if len(unique) == 5:
            break
    return [
        ProductCandidate(
            name=r.proposed.get("name") or "",
            brand=r.proposed.get("brand"),
            reference=r.proposed.get("reference"),
            color=r.proposed.get("color"),
            category_hint=r.proposed.get("category_hint"),
            ean=r.proposed.get("ean"),
            upc=r.proposed.get("upc"),
            gtin=r.proposed.get("gtin"),
            images=r.proposed.get("images", []),
            url=r.proposed.get("url"),
            confidence=r.confidence,
            source=r.proposed.get("provider") or "upcitemdb",
        )
        for r in unique
    ]
