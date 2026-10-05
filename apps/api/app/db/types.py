"""JSON column type portable: JSONB on PostgreSQL, generic JSON elsewhere."""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

JsonVariant = sa.JSON().with_variant(postgresql.JSONB, "postgresql")
