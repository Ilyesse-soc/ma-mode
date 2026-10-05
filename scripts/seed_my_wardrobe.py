"""Opt-in, account-scoped local test wardrobe. No credentials or global seed."""

import asyncio
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps" / "api"))

# Product references and photographs are deliberately not invented.
# name, brand, category, color, season, warmth, rain, style
PIECES = [
    ("T-shirt noir", "Nike", "tshirt", "black", "summer", 1, False, "streetwear"),
    ("T-shirt blanc", "Uniqlo", "tshirt", "white", "summer", 1, False, "casual"),
    ("T-shirt gris", "Adidas", "tshirt", "grey", "summer", 1, False, "sport"),
    (
        "Pull beige",
        "Ralph Lauren",
        "sweater",
        "beige",
        "winter",
        5,
        False,
        "smart_casual",
    ),
    ("Pull col rond noir", "Uniqlo", "sweater", "black", "autumn", 3, False, "casual"),
    ("Pull anthracite", "Zara", "sweater", "grey", "winter", 4, False, "smart_casual"),
    ("Hoodie gris", "Nike", "hoodie", "grey", "winter", 4, False, "streetwear"),
    ("Hoodie noir", "Adidas", "hoodie", "black", "autumn", 3, False, "sport"),
    ("Chemise blanche", "Zara", "shirt", "white", "spring", 2, False, "chic"),
    (
        "Chemise bleu clair",
        "Uniqlo",
        "shirt",
        "light_blue",
        "spring",
        2,
        False,
        "smart_casual",
    ),
    ("Polo marine", "Lacoste", "polo", "navy", "summer", 1, False, "smart_casual"),
    ("Veste beige", "Zara", "jacket", "beige", "spring", 2, False, "casual"),
    (
        "Bomber noir",
        "Alpha Industries",
        "jacket",
        "black",
        "autumn",
        3,
        False,
        "streetwear",
    ),
    (
        "Doudoune noire",
        "The North Face",
        "puffer",
        "black",
        "winter",
        5,
        False,
        "casual",
    ),
    ("Manteau camel", "Mango", "coat", "camel", "winter", 5, False, "chic"),
    ("Veste imperméable noire", None, "jacket", "black", "all", 3, True, "casual"),
    ("Jean 501 bleu", "Levi's", "jeans", "blue", "all", 3, False, "casual"),
    ("Jean noir", "Levi's", "jeans", "black", "all", 3, False, "streetwear"),
    ("Jean gris", "Zara", "jeans", "grey", "all", 3, False, "casual"),
    ("Cargo beige", "Carhartt", "cargo", "beige", "autumn", 3, False, "streetwear"),
    ("Cargo noir", "Zara", "cargo", "black", "autumn", 3, False, "streetwear"),
    ("Pantalon habillé noir", None, "trousers", "black", "all", 3, False, "chic"),
    (
        "Pantalon habillé gris",
        None,
        "trousers",
        "grey",
        "all",
        3,
        False,
        "smart_casual",
    ),
    ("Jogging gris", "Nike", "joggers", "grey", "winter", 4, False, "sport"),
    ("Jogging noir", "Adidas", "joggers", "black", "autumn", 3, False, "sport"),
    ("Short noir", "Nike", "shorts", "black", "summer", 1, False, "sport"),
    ("Short beige", "Zara", "shorts", "beige", "summer", 1, False, "casual"),
    ("Air Max noires", "Nike", "sneakers", "black", "all", 2, False, "streetwear"),
    ("Samba blanches", "Adidas", "sneakers", "white", "summer", 1, False, "casual"),
    ("Sneakers grises", "New Balance", "sneakers", "grey", "all", 2, False, "casual"),
    ("Mocassins noirs", None, "dress_shoes", "black", "all", 2, False, "chic"),
    (
        "Bottines marron foncé",
        None,
        "boots",
        "brown",
        "winter",
        4,
        True,
        "smart_casual",
    ),
]
for name, category, color, season, warmth in [
    ("Bonnet noir", "beanie", "black", "winter", 5),
    ("Bonnet gris", "beanie", "grey", "winter", 4),
    ("Casquette noire", "cap", "black", "summer", 1),
    ("Casquette beige", "cap", "beige", "summer", 1),
    ("Lunettes de soleil noires", "sunglasses", "black", "summer", 1),
    ("Montre argentée", "watch", "silver", "all", 1),
    ("Montre noire", "watch", "black", "all", 1),
    ("Ceinture noire", "belt", "black", "all", 1),
    ("Sac noir", "bag", "black", "all", 1),
    ("Chaussettes noires", "socks", "black", "winter", 4),
    ("Chaussettes blanches", "socks", "white", "summer", 1),
    ("Chaussettes grises", "socks", "grey", "autumn", 3),
    ("Chaussettes marine", "socks", "navy", "winter", 4),
]:
    PIECES.append((name, None, category, color, season, warmth, False, "casual"))


async def seed():
    from dotenv import load_dotenv
    from sqlalchemy import select

    load_dotenv(ROOT / ".local" / "api.env", override=False)
    load_dotenv(ROOT / ".local" / "seed.env", override=False)
    from app.core.config import get_settings
    from app.db.session import dispose_engine, get_session_factory
    from app.domain.enums import Season
    from app.modules.outfits.models import Outfit, OutfitItem
    from app.modules.users.models import User
    from app.modules.wardrobe.models import Garment, GarmentCategory

    settings = get_settings()
    if settings.environment != "development":
        raise RuntimeError("Refus : uniquement en environnement development.")
    from urllib.parse import urlparse

    if urlparse(settings.database_url).hostname not in {
        "localhost",
        "127.0.0.1",
        "::1",
    }:
        raise RuntimeError("Refus : la base doit être locale.")
    email = os.environ.get("SEED_USER_EMAIL", "").strip().lower()
    if not email:
        raise RuntimeError("Définir SEED_USER_EMAIL dans .local/seed.env.")
    try:
        async with get_session_factory()() as db:
            user = await db.scalar(
                select(User)
                .where(User.email == email, User.is_active.is_(True))
                .with_for_update()
            )
            if user is None:
                raise RuntimeError(
                    "Compte local introuvable : créer le compte dans l'application puis relancer."
                )
            categories = {
                c.slug: c.id for c in await db.scalars(select(GarmentCategory))
            }
            if any(p[2] not in categories for p in PIECES):
                raise RuntimeError(
                    "Catalogue incomplet : lancer start-local.ps1 d'abord."
                )
            existing = set(
                await db.execute(
                    select(Garment.name, Garment.brand).where(
                        Garment.user_id == user.id
                    )
                )
            )
            created = 0
            for name, brand, category, color, season, warmth, rain, style in PIECES:
                if (name, brand) in existing:
                    continue
                db.add(
                    Garment(
                        user_id=user.id,
                        category_id=categories[category],
                        name=name,
                        brand=brand,
                        color=color,
                        season=Season(season),
                        warmth_level=warmth,
                        waterproof=rain,
                        windproof=category in {"jacket", "coat", "puffer"},
                        styles=[style],
                        notes="Garde-robe de test locale personnelle. Référence produit non vérifiée. "
                        + (
                            "Tenue habillée." if style == "chic" else "Usage quotidien."
                        ),
                    )
                )
                created += 1
            await db.flush()
            # Saved test looks only: never fabricate dates or worn history.
            owned = list(
                await db.scalars(select(Garment).where(Garment.user_id == user.id))
            )
            by_name = {g.name: g.id for g in owned}
            look_names = set(
                await db.scalars(select(Outfit.name).where(Outfit.user_id == user.id))
            )
            looks = {
                "Test local · Casual froid": [
                    "Pull beige",
                    "Jean 501 bleu",
                    "Doudoune noire",
                    "Bottines marron foncé",
                ],
                "Test local · Streetwear": [
                    "Hoodie gris",
                    "Cargo noir",
                    "Air Max noires",
                ],
                "Test local · Smart casual": [
                    "Chemise blanche",
                    "Pantalon habillé noir",
                    "Mocassins noirs",
                ],
                "Test local · Pluie": [
                    "Pull anthracite",
                    "Veste imperméable noire",
                    "Jean noir",
                    "Bottines marron foncé",
                ],
                "Test local · Été": ["T-shirt blanc", "Short beige", "Samba blanches"],
            }
            created_looks = 0
            for look_name, pieces in looks.items():
                if look_name in look_names:
                    continue
                outfit = Outfit(
                    user_id=user.id, name=look_name, is_favorite=created_looks < 2
                )
                db.add(outfit)
                await db.flush()
                for layer, piece_name in enumerate(pieces):
                    db.add(
                        OutfitItem(
                            outfit_id=outfit.id,
                            garment_id=by_name[piece_name],
                            layer_order=layer,
                        )
                    )
                created_looks += 1
            await db.commit()
            print(
                f"Compte ciblé : {user.id}; créés : {created}; doublons évités : {len(PIECES) - created}; total catalogue : {len(PIECES)}."
            )
            print(
                f"Tenues de test sauvegardées : {created_looks}; doublons évités : {len(looks) - created_looks}."
            )
    finally:
        await dispose_engine()


if __name__ == "__main__":
    asyncio.run(seed())
