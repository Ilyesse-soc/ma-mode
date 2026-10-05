"""Local demo seed (development only — never used by production paths).

Creates a demo user with a small wardrobe so the app can be tried quickly.
Idempotent: safe to run multiple times.
"""

import asyncio

from sqlalchemy import select

from app.core.security import hash_password
from app.db.session import dispose_engine, get_session_factory, init_engine
from app.domain.enums import MannequinPresentation
from app.modules.users.models import User, UserPreference
from app.modules.wardrobe.catalog import CATEGORY_SEED
from app.modules.wardrobe.models import Garment, GarmentCategory

DEMO_EMAIL = "demo@alamode.app"


async def seed() -> None:
    init_engine()
    factory = get_session_factory()
    async with factory() as db:
        # Reference catalog (idempotent upsert).
        for i, entry in enumerate(CATEGORY_SEED):
            existing = await db.scalar(select(GarmentCategory).where(GarmentCategory.slug == entry["slug"]))
            if existing is None:
                db.add(GarmentCategory(**entry, sort_order=i))
        await db.flush()

        user = await db.scalar(select(User).where(User.email == DEMO_EMAIL))
        if user is None:
            user = User(
                first_name="Alex",
                email=DEMO_EMAIL,
                password_hash=hash_password("demo-password-123"),
                mannequin_presentation=MannequinPresentation.MALE,
                email_verified=True,
            )
            db.add(user)
            await db.flush()
            db.add(
                UserPreference(
                    user_id=user.id,
                    preferred_styles=["casual", "minimalist"],
                    liked_colors=["navy", "black", "white"],
                    cold_threshold_celsius=12.0,
                    hot_threshold_celsius=24.0,
                )
            )

        categories = {c.slug: c for c in (await db.scalars(select(GarmentCategory))).all()}
        existing = await db.scalar(select(Garment).where(Garment.user_id == user.id).limit(1))
        if existing is None:
            demo_garments = [
                ("tshirt", "T-shirt blanc", "white", 2, False, False),
                ("shirt", "Chemise oxford", "navy", 3, False, False),
                ("sweater", "Pull mérinos", "grey", 4, False, False),
                ("jacket", "Veste imperméable", "black", 3, True, True),
                ("coat", "Manteau laine", "beige", 5, False, True),
                ("jeans", "Jean brut", "navy", 3, False, False),
                ("trousers", "Pantalon chino", "beige", 2, False, False),
                ("sneakers", "Sneakers blanches", "white", 2, False, False),
                ("boots", "Bottes cuir", "brown", 3, True, False),
                ("watch", "Montre acier", "silver", 1, False, False),
            ]
            for slug, name, color, warmth, waterproof, windproof in demo_garments:
                db.add(
                    Garment(
                        user_id=user.id,
                        category_id=categories[slug].id,
                        name=name,
                        color=color,
                        warmth_level=warmth,
                        waterproof=waterproof,
                        windproof=windproof,
                        styles=["casual", "minimalist"],
                    )
                )
        await db.commit()
        print(f"Seed OK — demo user: {DEMO_EMAIL} / demo-password-123")
    await dispose_engine()


if __name__ == "__main__":
    asyncio.run(seed())
