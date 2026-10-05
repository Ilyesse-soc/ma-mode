"""Reserved uploads and durable object-deletion jobs (no image bytes in SQL)."""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.mixins import TimestampMixin
from app.db.session import Base


class MediaUpload(Base, TimestampMixin):
    __tablename__ = "media_uploads"
    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, index=True, nullable=False)
    object_key: Mapped[str] = mapped_column(sa.String(512), unique=True, nullable=False)
    validated: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)


class DeletionTask(Base, TimestampMixin):
    __tablename__ = "media_deletion_tasks"
    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True, default=uuid.uuid4)
    prefix: Mapped[str] = mapped_column(sa.String(512), nullable=False)
    not_before: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    attempts: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
