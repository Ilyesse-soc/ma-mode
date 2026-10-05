"""Recommendation routes: generate, feedback, last."""

import uuid

from fastapi import APIRouter, Depends
from pydantic import Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.validation import StrictModel
from app.db.session import get_db
from app.domain.enums import ActivityContext, FeedbackAction
from app.modules.recommendations import service
from app.modules.users.dependencies import get_current_user
from app.modules.users.models import User

router = APIRouter(tags=["recommendations"])


class GenerateIn(StrictModel):
    origin_latitude: float = Field(ge=-90, le=90)
    origin_longitude: float = Field(ge=-180, le=180)
    origin_label: str | None = Field(default=None, max_length=160)
    destination_latitude: float | None = Field(default=None, ge=-90, le=90)
    destination_longitude: float | None = Field(default=None, ge=-180, le=180)
    destination_label: str | None = Field(default=None, max_length=160)
    arrival_timestamp: int | None = Field(default=None, gt=0)
    activity: ActivityContext = ActivityContext.EVERYDAY


class ProposalOut(StrictModel):
    rank: int
    score: float
    garment_ids: list[str]
    explanations: list[str]
    breakdown: dict


class RecommendationOut(StrictModel):
    id: uuid.UUID
    origin_label: str | None
    destination_label: str | None
    activity: str
    weather_summary: dict
    proposals: list[ProposalOut]


def _to_out(reco) -> RecommendationOut:
    return RecommendationOut(
        id=reco.id,
        origin_label=reco.origin_label,
        destination_label=reco.destination_label,
        activity=reco.activity.value,
        weather_summary=reco.weather_summary,
        proposals=[
            ProposalOut(
                rank=i.rank,
                score=i.score,
                garment_ids=i.garment_ids,
                explanations=i.explanations,
                breakdown=i.breakdown,
            )
            for i in sorted(reco.items, key=lambda x: x.rank)
        ],
    )


@router.post("/recommendations/generate", response_model=RecommendationOut, status_code=201)
async def generate(
    payload: GenerateIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    if (payload.destination_latitude is None) != (payload.destination_longitude is None):
        from app.core.errors import bad_request

        raise bad_request("incomplete_destination", "Destination requires latitude AND longitude")
    reco = await service.generate_recommendations(
        db,
        current.id,
        payload.origin_latitude,
        payload.origin_longitude,
        payload.origin_label,
        payload.destination_latitude,
        payload.destination_longitude,
        payload.destination_label,
        payload.arrival_timestamp,
        payload.activity,
    )
    await db.commit()
    return _to_out(reco)


class FeedbackIn(StrictModel):
    action: FeedbackAction
    garment_id: uuid.UUID | None = None


@router.post("/recommendations/{recommendation_id}/feedback", status_code=201)
async def feedback(
    recommendation_id: uuid.UUID,
    payload: FeedbackIn,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    await service.record_feedback(db, current.id, recommendation_id, payload.action, payload.garment_id)
    await db.commit()
    return {"message": "Merci pour ton retour"}


@router.get("/recommendations/last", response_model=RecommendationOut | None)
async def last_recommendation(db: AsyncSession = Depends(get_db), current: User = Depends(get_current_user)):
    reco = await service.get_last_recommendation(db, current.id)
    return _to_out(reco) if reco else None
