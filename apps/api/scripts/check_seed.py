"""Check that the category catalog is seeded after migration."""

import asyncio

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import create_async_engine


async def main() -> None:
    eng = create_async_engine("sqlite+aiosqlite:///./migration_check.db")
    async with eng.connect() as conn:
        result = await conn.execute(sa.text("SELECT count(*) FROM garment_categories"))
        print("categories seeded:", result.scalar())
    await eng.dispose()


asyncio.run(main())
