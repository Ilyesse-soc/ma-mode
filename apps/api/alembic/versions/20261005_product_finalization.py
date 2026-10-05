"""Product image provenance and resumable functional onboarding."""

import sqlalchemy as sa

from alembic import op

revision = "product_final_20261005"
down_revision = "verify_expiry_20261005"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("garments", sa.Column("product_image_url", sa.String(2048), nullable=True))
    op.add_column(
        "garment_images", sa.Column("image_kind", sa.String(16), nullable=False, server_default="garment")
    )
    op.add_column(
        "users",
        sa.Column(
            "onboarding_steps",
            sa.JSON(),
            nullable=False,
            server_default='["profile","preferences","consents"]',
        ),
    )
    # Preserve completed legacy accounts; new registrations start at profile.


def downgrade():
    op.drop_column("users", "onboarding_steps")
    op.drop_column("garment_images", "image_kind")
    op.drop_column("garments", "product_image_url")
