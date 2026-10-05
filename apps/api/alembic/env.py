"""Alembic environment: imports all models so autogenerate sees every table."""

import asyncio
import os
from logging.config import fileConfig

from sqlalchemy.ext.asyncio import create_async_engine

# Import all modules so their models register on Base.metadata.
import app.modules.audit.models
import app.modules.locations.router
import app.modules.media.models
import app.modules.outfits.models
import app.modules.privacy.models
import app.modules.recommendations.models
import app.modules.users.models
import app.modules.wardrobe.models
import app.modules.weather.router  # noqa: F401  (WeatherSnapshot)
from alembic import context
from app.db.session import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def get_url() -> str:
    url = os.environ.get("DATABASE_URL")
    if not url:
        from app.core.config import get_settings

        url = get_settings().database_url
    return url


def run_migrations_offline() -> None:
    context.configure(
        url=get_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = create_async_engine(get_url())
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
