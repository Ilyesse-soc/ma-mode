"""Garment category catalog — extensible (DB-backed). Seeded at migration time."""

from app.domain.enums import GarmentCategoryGroup

CATEGORY_SEED: list[dict] = [
    # HEAD
    {"slug": "cap", "label": "Casquette", "group": GarmentCategoryGroup.HEAD},
    {"slug": "beanie", "label": "Bonnet", "group": GarmentCategoryGroup.HEAD},
    {"slug": "hat", "label": "Chapeau", "group": GarmentCategoryGroup.HEAD},
    {"slug": "glasses", "label": "Lunettes", "group": GarmentCategoryGroup.HEAD},
    {"slug": "sunglasses", "label": "Lunettes de soleil", "group": GarmentCategoryGroup.HEAD},
    {"slug": "earrings", "label": "Boucles d'oreilles", "group": GarmentCategoryGroup.HEAD},
    {"slug": "head_accessory", "label": "Accessoire de tête", "group": GarmentCategoryGroup.HEAD},
    # TOP
    {"slug": "tshirt", "label": "T-shirt", "group": GarmentCategoryGroup.TOP},
    {"slug": "polo", "label": "Polo", "group": GarmentCategoryGroup.TOP},
    {"slug": "shirt", "label": "Chemise", "group": GarmentCategoryGroup.TOP},
    {"slug": "sweater", "label": "Pull", "group": GarmentCategoryGroup.TOP},
    {"slug": "hoodie", "label": "Hoodie", "group": GarmentCategoryGroup.TOP},
    {"slug": "cardigan", "label": "Cardigan", "group": GarmentCategoryGroup.TOP},
    {"slug": "jacket", "label": "Veste", "group": GarmentCategoryGroup.TOP},
    {"slug": "blazer", "label": "Blazer", "group": GarmentCategoryGroup.TOP},
    {"slug": "coat", "label": "Manteau", "group": GarmentCategoryGroup.TOP},
    {"slug": "puffer", "label": "Doudoune", "group": GarmentCategoryGroup.TOP},
    {"slug": "top_other", "label": "Autre haut", "group": GarmentCategoryGroup.TOP},
    # BOTTOM
    {"slug": "jeans", "label": "Jean", "group": GarmentCategoryGroup.BOTTOM},
    {"slug": "trousers", "label": "Pantalon", "group": GarmentCategoryGroup.BOTTOM},
    {"slug": "cargo", "label": "Cargo", "group": GarmentCategoryGroup.BOTTOM},
    {"slug": "joggers", "label": "Jogging", "group": GarmentCategoryGroup.BOTTOM},
    {"slug": "shorts", "label": "Short", "group": GarmentCategoryGroup.BOTTOM},
    {"slug": "skirt", "label": "Jupe", "group": GarmentCategoryGroup.BOTTOM},
    {"slug": "dress", "label": "Robe", "group": GarmentCategoryGroup.BOTTOM},
    {"slug": "bottom_other", "label": "Autre bas", "group": GarmentCategoryGroup.BOTTOM},
    # SHOES
    {"slug": "sneakers", "label": "Sneakers", "group": GarmentCategoryGroup.SHOES},
    {"slug": "dress_shoes", "label": "Chaussures de ville", "group": GarmentCategoryGroup.SHOES},
    {"slug": "boots", "label": "Bottes", "group": GarmentCategoryGroup.SHOES},
    {"slug": "sandals", "label": "Sandales", "group": GarmentCategoryGroup.SHOES},
    {"slug": "shoes_other", "label": "Autres chaussures", "group": GarmentCategoryGroup.SHOES},
    # WRIST
    {"slug": "watch", "label": "Montre", "group": GarmentCategoryGroup.WRIST},
    {"slug": "bracelet", "label": "Bracelet", "group": GarmentCategoryGroup.WRIST},
    {"slug": "wrist_other", "label": "Autre accessoire poignet", "group": GarmentCategoryGroup.WRIST},
    # OTHER
    {"slug": "bag", "label": "Sac", "group": GarmentCategoryGroup.OTHER},
    {"slug": "belt", "label": "Ceinture", "group": GarmentCategoryGroup.OTHER},
    {"slug": "jewelry", "label": "Bijoux", "group": GarmentCategoryGroup.OTHER},
    {"slug": "socks", "label": "Chaussettes", "group": GarmentCategoryGroup.OTHER},
    {"slug": "misc_accessory", "label": "Accessoire", "group": GarmentCategoryGroup.OTHER},
]

# Silhouette zone → category slugs (used by the mobile interactive silhouette).
SILHOUETTE_ZONE_MAP: dict[str, list[str]] = {
    "head": ["cap", "beanie", "hat", "head_accessory"],
    "face": ["glasses", "sunglasses"],
    "ears": ["earrings"],
    "torso": [
        "tshirt",
        "polo",
        "shirt",
        "sweater",
        "hoodie",
        "cardigan",
        "jacket",
        "blazer",
        "coat",
        "puffer",
        "dress",
        "top_other",
    ],
    "arms": ["top_other"],
    "wrists": ["watch", "bracelet", "wrist_other"],
    "waist": ["belt"],
    "legs": ["jeans", "trousers", "cargo", "joggers", "shorts", "skirt", "dress", "bottom_other", "socks"],
    "feet": ["sneakers", "dress_shoes", "boots", "sandals", "shoes_other"],
}
