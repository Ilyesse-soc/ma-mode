"""Reserved media uploads, durable deletion jobs and optional AI consent."""

import sqlalchemy as sa

from alembic import op

revision = "security_20261005"
down_revision = "222a60266b0a"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "media_uploads",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), nullable=False, index=True),
        sa.Column("object_key", sa.String(512), nullable=False, unique=True),
        sa.Column("validated", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_table(
        "media_deletion_tasks",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("prefix", sa.String(512), nullable=False),
        sa.Column("not_before", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_table(
        "user_consents",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), nullable=False, index=True),
        sa.Column("consent_type", sa.String(32), nullable=False),
        sa.Column("version", sa.String(32), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("withdrawn_at", sa.DateTime(timezone=True)),
    )


def downgrade():
    for table in ["user_consents", "media_deletion_tasks", "media_uploads"]:
        op.drop_table(table)
