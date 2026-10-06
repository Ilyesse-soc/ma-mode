"""Identification pipeline (section 10 of the spec).

photo → download from object storage → vision/OCR → extraction → normalization
→ product search → candidates with confidence → USER VALIDATION.

The AI never writes directly to the garment; it only creates candidates.
"""

import uuid

from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app.core.errors import ApiError, not_found, upstream_unavailable
from app.domain.enums import IdentificationSource
from app.modules.media import storage
from app.modules.product_recognition.providers import GarmentVisualAnalysis, LabelExtraction, get_ai_provider
from app.modules.product_search.providers import get_product_search_providers
from app.modules.wardrobe import service as wardrobe_service
from app.modules.wardrobe.models import GarmentIdentificationCandidate
from app.modules.wardrobe.schemas import IdentifyResult

HIGH_CONFIDENCE = 0.85
LOW_CONFIDENCE = 0.5


def _download_bytes(object_key: str) -> bytes:
    return storage.read_object(object_key)


async def analyze_label(
    db: AsyncSession, user_id: uuid.UUID, garment_id: uuid.UUID, image_id: uuid.UUID
) -> IdentifyResult:
    image = await wardrobe_service.get_image_for_user(db, user_id, image_id)
    await wardrobe_service.get_garment(db, user_id, garment_id)
    if image.garment_id != garment_id:
        raise not_found("image")
    data = await run_in_threadpool(_download_bytes, image.object_key)
    result = await get_ai_provider().analyze_label(data)
    if not isinstance(result.parsed, LabelExtraction):
        raise upstream_unavailable("ai")
    extraction = result.parsed
    confidence = min(extraction.confidence, 0.95)
    proposed = extraction.model_dump(exclude={"confidence"}, exclude_none=True)
    if "product_name" in proposed:
        proposed["name"] = proposed.pop("product_name")

    # Enrich with product search when a reference or brand+name was read.
    # Keep evidence actually read from the user's label as the first proposal.
    # A catalogue search for a generic SKU can otherwise replace it with an
    # unrelated product and lose the confirmed size/material.
    candidates_out: list[GarmentIdentificationCandidate] = [
        await wardrobe_service.add_candidate(
            db,
            garment_id,
            IdentificationSource.LABEL_OCR,
            confidence=confidence,
            proposed=proposed,
        )
    ]
    search_query = extraction.reference or " ".join(
        p for p in [extraction.brand, extraction.product_name] if p
    )
    if search_query:
        for provider in get_product_search_providers():
            try:
                hits = await provider.search_by_text(search_query)
            except ApiError as exc:
                if exc.status_code != 503:
                    raise
                # Catalogue enrichment is optional: keep the genuine OCR extraction
                # available when the FREE catalogue quota or network is exhausted.
                hits = []
            for hit in hits:
                from app.modules.product_recognition.identification import match_score

                score, matched = match_score(proposed, hit)
                c = await wardrobe_service.add_candidate(
                    db,
                    garment_id,
                    IdentificationSource.LABEL_OCR,
                    confidence=score,
                    proposed={
                        **hit.model_dump(exclude_none=True),
                        "provider": hit.source,
                        "matched_fields": matched,
                        "confidence_kind": "evidence_match",
                    },
                )
                candidates_out.append(c)
            if hits:
                break

    if confidence >= HIGH_CONFIDENCE and candidates_out:
        status, message = "matched", "Produit identifié avec forte confiance"
    elif confidence >= LOW_CONFIDENCE:
        status, message = "candidates", "Nous pensons avoir trouvé ce produit"
    else:
        status, message = "not_found", "Confiance insuffisante — merci de compléter"
    from app.modules.product_recognition.identification import result_for

    enriched = await result_for(db, user_id, garment_id)
    enriched.status, enriched.message = status, message
    return enriched


async def analyze_photo(
    db: AsyncSession, user_id: uuid.UUID, garment_id: uuid.UUID, image_id: uuid.UUID
) -> IdentifyResult:
    image = await wardrobe_service.get_image_for_user(db, user_id, image_id)
    await wardrobe_service.get_garment(db, user_id, garment_id)
    if image.garment_id != garment_id:
        raise not_found("image")
    data = await run_in_threadpool(_download_bytes, image.object_key)
    result = await get_ai_provider().analyze_garment_photo(data)
    if not isinstance(result.parsed, GarmentVisualAnalysis):
        raise upstream_unavailable("ai")
    analysis = result.parsed
    proposed = {
        k: v
        for k, v in {
            "category_slug": analysis.category_hint,
            "color": analysis.color,
            "secondary_colors": analysis.secondary_colors,
            "material": analysis.material_guess,
            "styles": analysis.style_hints,
            "brand": analysis.brand,
            "name": analysis.product_name,
            "reference": analysis.reference,
            "cut": analysis.cut,
            "visible_logo": analysis.visible_logo,
            "distinctive_features": analysis.distinctive_features,
        }.items()
        if v
    }
    await wardrobe_service.add_candidate(
        db,
        garment_id,
        IdentificationSource.PHOTO_VISION,
        confidence=analysis.confidence,
        proposed=proposed,
    )
    if analysis.confidence >= LOW_CONFIDENCE:
        status, message = "candidates", "Analyse terminée — confirme les détails"
    else:
        status, message = "not_found", "Analyse incertaine — complète manuellement"
    from app.modules.product_recognition.identification import search_evidence

    enriched = await search_evidence(db, user_id, garment_id)
    enriched.status, enriched.message = status, message
    return enriched
