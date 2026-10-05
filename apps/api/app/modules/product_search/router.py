"""Product search routes: barcode lookup + text search via provider chain."""

from fastapi import APIRouter, Depends, Path
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.validation import StrictModel
from app.db.session import get_db
from app.modules.product_search.cache import barcode_candidates
from app.modules.product_search.providers import get_product_search_providers
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User

router = APIRouter(tags=["product-search"])


class CandidateDto(BaseModel):
    name: str
    brand: str | None
    reference: str | None
    color: str | None
    confidence: float
    source: str


class SearchResponse(BaseModel):
    status: str  # "matched" | "not_found"
    candidates: list[CandidateDto]


@router.get("/product-search/barcode/{barcode}", response_model=SearchResponse)
async def lookup_barcode(
    barcode: str = Path(min_length=6, max_length=32, pattern=r"^[0-9A-Za-z\-]+$"),
    current: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    cached = await barcode_candidates(db, current.id, barcode)
    for provider in get_product_search_providers():
        results = cached or await provider.search_by_barcode(barcode)
        if results:
            return SearchResponse(
                status="matched",
                candidates=[CandidateDto(**vars(c)) for c in results],
            )
    return SearchResponse(status="not_found", candidates=[])


class TextSearchIn(StrictModel):
    query: str = Field(min_length=2, max_length=200)


@router.post("/product-search/text", response_model=SearchResponse)
async def search_text(payload: TextSearchIn, _: User = Depends(get_current_user)):
    for provider in get_product_search_providers():
        results = await provider.search_by_text(payload.query)
        if results:
            return SearchResponse(
                status="matched",
                candidates=[CandidateDto(**vars(c)) for c in results],
            )
    return SearchResponse(status="not_found", candidates=[])
