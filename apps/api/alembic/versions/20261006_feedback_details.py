"""Persist neutral reactions and optional explicit feedback reasons."""

import sqlalchemy as sa

from alembic import op

revision = "feedback_20261006"
down_revision = "product_final_20261005"
branch_labels = None
depends_on = None


def upgrade():
    if op.get_bind().dialect.name == "postgresql":
        with op.get_context().autocommit_block():
            op.execute("ALTER TYPE feedback_action ADD VALUE IF NOT EXISTS 'OKAY'")
    op.add_column("recommendation_feedback", sa.Column("reason", sa.String(32), nullable=True))


def downgrade():
    # PostgreSQL cannot remove an enum value without rewriting stored feedback.
    # Keep the additive enum value so a rollback never rewrites user reactions.
    op.drop_column("recommendation_feedback", "reason")
