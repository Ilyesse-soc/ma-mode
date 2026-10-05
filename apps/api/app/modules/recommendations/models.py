"""Recommendation persistence models."""

import uuid

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.mixins import BigIntPk, TimestampMixin, utcnow
from app.db.session import Base
from app.db.types import JsonVariant
from app.domain.enums import ActivityContext, FeedbackAction


class Recommendation(Base, TimestampMixin):
    __tablename__ = "recommendations"

    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    origin_label: Mapped[str | None] = mapped_column(sa.String(160))
    destination_label: Mapped[str | None] = mapped_column(sa.String(160))
    activity: Mapped[ActivityContext] = mapped_column(
        sa.Enum(ActivityContext, name="reco_activity"), default=ActivityContext.EVERYDAY, nullable=False
    )
    weather_summary: Mapped[dict] = mapped_column(JsonVariant, nullable=False)
    accepted: Mapped[bool | None] = mapped_column(sa.Boolean)  # None = pending

    items: Mapped[list["RecommendationItem"]] = relationship(
        back_populates="recommendation", cascade="all, delete-orphan", lazy="selectin"
    )


class RecommendationItem(Base):
    """One proposed outfit (rank) with its garments and explanation."""

    __tablename__ = "recommendation_items"

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    recommendation_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("recommendations.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    rank: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    score: Mapped[float] = mapped_column(sa.Float, nullable=False)
    garment_ids: Mapped[list] = mapped_column(sa.JSON, nullable=False)
    explanations: Mapped[list] = mapped_column(sa.JSON, default=list, nullable=False)
    breakdown: Mapped[dict] = mapped_column(sa.JSON, default=dict, nullable=False)

    recommendation: Mapped[Recommendation] = relationship(back_populates="items")


class RecommendationFeedback(Base):
    __tablename__ = "recommendation_feedback"

    id: Mapped[int] = mapped_column(BigIntPk, primary_key=True, autoincrement=True)
    recommendation_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("recommendations.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), index=True, nullable=False)
    action: Mapped[FeedbackAction] = mapped_column(
        sa.Enum(FeedbackAction, name="feedback_action"), nullable=False
    )
    garment_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid(as_uuid=True))
    reason: Mapped[str | None] = mapped_column(sa.String(32))
    created_at: Mapped[object] = mapped_column(
        sa.DateTime(timezone=True), default=utcnow, server_default=sa.func.now(), nullable=False
    )
