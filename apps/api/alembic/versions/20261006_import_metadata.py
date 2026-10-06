"""Keep private image provenance and honest product identification decisions."""

import sqlalchemy as sa

from alembic import op

revision = "import_v2_20261006"
down_revision = "feedback_20261006"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("garments", sa.Column("import_metadata", sa.JSON(), nullable=True))


def downgrade():
    op.drop_column("garments", "import_metadata")
