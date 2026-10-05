"""Explicit renewable verification-link expiry."""

import sqlalchemy as sa

from alembic import op

revision = "verify_expiry_20261005"
down_revision = "security_20261005"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "users", sa.Column("email_verification_expires_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade():
    op.drop_column("users", "email_verification_expires_at")
