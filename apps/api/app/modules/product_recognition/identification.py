"""Owner-scoped cumulative evidence; scores measure matching fields, not probability."""

import re

from sqlalchemy import select

from app.core.errors import ApiError
from app.domain.enums import IdentificationSource
from app.modules.product_search.providers import ProductCandidate, get_product_search_providers
from app.modules.wardrobe import service
from app.modules.wardrobe.models import GarmentIdentificationCandidate
from app.modules.wardrobe.schemas import CandidateOut, IdentifyResult


def normalized(value):
    return re.sub(r"[^a-z0-9]", "", str(value or "").casefold())


def match_score(evidence: dict, hit: ProductCandidate) -> tuple[float, list[str]]:
    checks = []
    for field, actual in [("brand", hit.brand), ("reference", hit.reference), ("color", hit.color)]:
        expected = evidence.get(field)
        if expected and actual:
            checks.append((field, normalized(expected) == normalized(actual)))
    if evidence.get("barcode"):
        codes = [hit.ean, hit.upc, hit.gtin]
        checks.append(
            (
                "barcode",
                any(
                    normalized(x).lstrip("0") == normalized(evidence["barcode"]).lstrip("0")
                    for x in codes
                    if x
                ),
            )
        )
    if not checks:
        return 0.0, []
    return sum(1 for _, matched in checks if matched) / len(checks), [
        field for field, matched in checks if matched
    ]


async def result_for(db, user_id, garment_id):
    garment = await service.get_garment(db, user_id, garment_id)
    rows = list(
        await db.scalars(
            select(GarmentIdentificationCandidate)
            .where(GarmentIdentificationCandidate.garment_id == garment.id)
            .order_by(GarmentIdentificationCandidate.created_at.desc())
            .limit(100)
        )
    )
    rows.reverse()
    evidence = {}
    for row in rows:
        # Catalog guesses must never become input evidence for a later search.
        if row.proposed.get("provider") or row.status.value == "rejected":
            continue
        for key in (
            "brand",
            "reference",
            "color",
            "name",
            "category_slug",
            "size",
            "material",
            "department",
            "cut",
            "visible_logo",
            "distinctive_features",
            "styles",
        ):
            if row.proposed.get(key):
                evidence[key] = row.proposed[key]
    if garment.barcode:
        evidence["barcode"] = garment.barcode
    missing = [field for field in ("brand", "reference", "color") if not evidence.get(field)]
    actions = []
    if "brand" in missing:
        actions.append("select_brand")
    if "reference" in missing:
        actions.append("take_label_photo")
    if "color" in missing:
        actions.append("select_color")
    if not any(image.image_kind == "garment" for image in garment.images):
        actions.append("take_garment_photo")
    ranked = sorted(
        (row for row in rows if row.status.value != "rejected"), key=lambda c: c.confidence, reverse=True
    )
    status = "candidates" if ranked else "not_found"
    if garment.import_metadata:
        garment.import_metadata = {
            **garment.import_metadata,
            "detected_brand": evidence.get("brand"),
            "detected_category": evidence.get("category_slug"),
            "detected_color": evidence.get("color"),
            "evidence": evidence,
            "candidates": [
                {
                    "id": str(c.id),
                    "source": c.source.value,
                    "status": c.status.value,
                    "confidence": c.confidence,
                    "proposed": c.proposed,
                }
                for c in rows
            ],
        }
    return IdentifyResult(
        garment_id=garment.id,
        status=status,
        candidates=[CandidateOut.model_validate(c) for c in ranked],
        message="Nous pensons avoir trouvé ton vêtement"
        if ranked
        else "Je n'ai pas encore trouvé le vêtement exact. Aide-moi avec quelques détails.",
        missing_fields=missing,
        recommended_actions=actions,
        evidence=evidence,
        confidence_kind="evidence_match"
        if any(c.proposed.get("provider") for c in rows)
        else "model_estimate",
    )


async def search_evidence(db, user_id, garment_id):
    result = await result_for(db, user_id, garment_id)
    evidence = result.evidence
    if not any(evidence.get(k) for k in ("reference", "name", "category_slug")):
        return result
    garment = await service.get_garment(db, user_id, garment_id)
    query = " ".join(
        str(evidence.get(key) or "")
        for key in ("brand", "reference", "name", "category_slug", "color", "department")
    ).strip()[:250]
    if garment.import_metadata:
        garment.import_metadata = {**garment.import_metadata, "search_query_used": query}
    for provider in get_product_search_providers():
        try:
            hits = await provider.search_by_text(query)
        except ApiError as error:
            if error.status_code != 503:
                raise
            continue
        existing = {
            str(c.proposed.get("provider")) + str(c.proposed.get("name")) + str(c.proposed.get("reference"))
            for c in result.candidates
        }
        for hit in hits[:5]:
            score, matched = match_score(evidence, hit)
            fingerprint = hit.source + hit.name + str(hit.reference)
            if fingerprint in existing:
                continue
            proposed = hit.model_dump(exclude_none=True)
            proposed.update(
                name=hit.name, provider=hit.source, matched_fields=matched, confidence_kind="evidence_match"
            )
            await service.add_candidate(db, garment_id, IdentificationSource.LABEL_OCR, score, proposed)
        if hits:
            break
    return await result_for(db, user_id, garment_id)
