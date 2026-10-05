"""Wardrobe routes: garments CRUD, images, identification pipeline."""

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app.core.errors import conflict, not_found
from app.core.time import utc_now
from app.core.validation import StrictModel
from app.db.session import get_db
from app.domain.enums import IdentificationSource
from app.modules.media import storage
from app.modules.media.models import DeletionTask, MediaUpload
from app.modules.product_recognition import pipeline
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User
from app.modules.wardrobe import service
from app.modules.wardrobe.catalog import SILHOUETTE_ZONE_MAP
from app.modules.wardrobe.models import GarmentImage
from app.modules.wardrobe.schemas import (
    CandidateOut,
    CategoryOut,
    ConfirmCandidateIn,
    GarmentCreate,
    GarmentImageOut,
    GarmentOut,
    GarmentPage,
    GarmentUpdate,
    IdentifyBarcodeIn,
    IdentifyLabelIn,
    IdentifyPhotoIn,
    IdentifyResult,
)

router = APIRouter(tags=["wardrobe"])


def _serialize_garment(garment) -> GarmentOut:
    out = GarmentOut.model_validate(garment)
    for img in out.images:
        try:
            img.download_url = storage.create_presigned_download(
                garment.images[[i.id for i in garment.images].index(img.id)].object_key
            )
        except Exception:
            img.download_url = None
    return out


@router.get("/garment-categories", response_model=list[CategoryOut])
async def list_categories(db: AsyncSession = Depends(get_db), _: User = Depends(get_current_user)):
    return await service.list_categories(db)


@router.get("/garment-categories/silhouette-map")
async def silhouette_map(_: User = Depends(get_current_user)):
    return SILHOUETTE_ZONE_MAP


@router.get("/garments", response_model=GarmentPage)
async def list_garments(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=100),
    category: str | None = None,
    include_archived: bool = False,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    items, total = await service.list_garments(db, current.id, page, page_size, category, include_archived)
    return GarmentPage(
        items=[_serialize_garment(g) for g in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.post("/garments", response_model=GarmentOut, status_code=201)
async def create_garment(
    payload: GarmentCreate,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    garment = await service.create_garment(db, current.id, payload)
    await db.commit()
    return _serialize_garment(garment)


@router.get("/garments/{garment_id}", response_model=GarmentOut)
async def get_garment(
    garment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    garment = await service.get_garment(db, current.id, garment_id)
    return _serialize_garment(garment)


@router.patch("/garments/{garment_id}", response_model=GarmentOut)
async def update_garment(
    garment_id: uuid.UUID,
    payload: GarmentUpdate,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    garment = await service.update_garment(db, current.id, garment_id, payload)
    await db.commit()
    return _serialize_garment(garment)


@router.delete("/garments/{garment_id}", status_code=204)
async def delete_garment(
    garment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    garment = await service.delete_garment(db, current.id, garment_id)
    for image in garment.images:
        db.add(DeletionTask(prefix=image.object_key, not_before=utc_now()))
    await db.commit()


class AttachImagePayload(StrictModel):
    object_key: str
    content_type: str
    byte_size: int
    width: int | None = None
    height: int | None = None


@router.post("/garments/{garment_id}/images", response_model=GarmentImageOut, status_code=201)
async def attach_image(
    garment_id: uuid.UUID,
    payload: AttachImagePayload,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    await service.get_garment(db, current.id, garment_id)
    storage.validate_object_key(current.id, payload.object_key)
    upload = await db.scalar(
        select(MediaUpload)
        .where(MediaUpload.user_id == current.id, MediaUpload.object_key == payload.object_key)
        .with_for_update()
    )
    if upload is None:
        raise not_found("object")
    if await db.scalar(select(GarmentImage.id).where(GarmentImage.object_key == payload.object_key)):
        raise conflict("image_attached", "This image is already attached")
    raw = await run_in_threadpool(storage.read_object, upload.object_key)
    clean, content_type, width, height = await run_in_threadpool(storage.sanitize_image, raw)
    old_key = upload.object_key
    if not upload.validated:
        upload.object_key = old_key.replace("/quarantine/", "/validated/").rsplit(".", 1)[0] + ".jpg"
    await run_in_threadpool(
        storage._client().put_object,
        Bucket=storage.get_settings().s3_bucket,
        Key=upload.object_key,
        Body=clean,
        ContentType=content_type,
    )
    upload.validated = True
    image = await service.attach_image(
        db,
        current.id,
        garment_id,
        upload.object_key,
        content_type,
        len(clean),
        width,
        height,
    )
    if old_key != upload.object_key:
        db.add(DeletionTask(prefix=old_key, not_before=utc_now()))
    await db.commit()
    out = GarmentImageOut.model_validate(image)
    out.download_url = storage.create_presigned_download(image.object_key)
    return out


# --- Identification pipeline ---------------------------------------------------


@router.post("/garments/identify/barcode", response_model=IdentifyResult)
async def identify_barcode(
    payload: IdentifyBarcodeIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """Creates a draft garment populated from the best barcode candidate."""
    from app.modules.product_search.cache import barcode_candidates
    from app.modules.product_search.providers import get_product_search_providers

    cached = await barcode_candidates(db, current.id, payload.barcode)
    for provider in get_product_search_providers():
        results = cached or await provider.search_by_barcode(payload.barcode)
        if results:
            best = results[0]
            garment = await service.create_garment(
                db,
                current.id,
                GarmentCreate(
                    category_slug="top_other",
                    name=best.name or "Article scanné",
                    brand=best.brand,
                    color=best.color or "unknown",
                    reference=best.reference,
                    barcode=payload.barcode,
                    is_archived=True,
                ),
            )
            candidate = await service.add_candidate(
                db,
                garment.id,
                source=IdentificationSource.BARCODE,
                confidence=best.confidence,
                proposed={
                    "name": best.name,
                    "brand": best.brand,
                    "reference": best.reference,
                    "color": best.color,
                    "category_hint": best.category_hint,
                    "ean": best.ean,
                    "upc": best.upc,
                    "gtin": best.gtin,
                    "images": best.images,
                },
            )
            await db.commit()
            return IdentifyResult(
                garment_id=garment.id,
                status="candidates",
                candidates=[CandidateOut.model_validate(candidate)],
                message="Nous pensons avoir trouvé ce produit — confirme les détails",
            )
    return IdentifyResult(
        status="not_found",
        candidates=[],
        message="Code-barres inconnu — renseigne le vêtement manuellement",
    )


@router.post("/garments/{garment_id}/identify/label", response_model=IdentifyResult)
async def identify_label(
    garment_id: uuid.UUID,
    payload: IdentifyLabelIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    from app.modules.privacy.router import require_ai_consent

    await require_ai_consent(db, current.id)
    result = await pipeline.analyze_label(db, current.id, garment_id, payload.image_id)
    await db.commit()
    return result


@router.post("/garments/{garment_id}/identify/photo", response_model=IdentifyResult)
async def identify_photo(
    garment_id: uuid.UUID,
    payload: IdentifyPhotoIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    from app.modules.privacy.router import require_ai_consent

    await require_ai_consent(db, current.id)
    result = await pipeline.analyze_photo(db, current.id, garment_id, payload.image_id)
    await db.commit()
    return result


@router.post("/garments/{garment_id}/candidates/{candidate_id}/confirm", response_model=CandidateOut)
async def confirm_candidate(
    garment_id: uuid.UUID,
    candidate_id: uuid.UUID,
    payload: ConfirmCandidateIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    candidate = await service.confirm_candidate(
        db, current.id, garment_id, candidate_id, payload.apply_fields
    )
    await db.commit()
    return candidate
