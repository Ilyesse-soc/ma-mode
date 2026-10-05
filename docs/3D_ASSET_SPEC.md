# Spécification des assets 3D (Blender → app)

L'app charge les assets par **convention de nommage** — aucun code ne dépend d'un modèle précis. Remplacer un fichier suffit.

## Arborescence

```
assets/3d/
  mannequins/     female.glb, male.glb          (modèles finaux fournis par l'utilisateur)
  clothing/       <category_slug>_<variant>.glb (ex. coat_rain_black.glb)
  environments/   studio_neutral.glb (optionnel)
  textures/       *.webp / *.png (KTX2 accepté)
```

## Conventions

| Règle | Valeur |
|---|---|
| Unités | **mètres** (1 BU = 1 m) |
| Orientation | **Y-up, −Z forward**, mannequin face caméra à rotation 0 |
| Origine | pieds au sol (0,0,0), centré X/Z |
| Taille | mannequin ≈ 1,70 m (female) / 1,80 m (male) |
| Formats | GLB (glTF 2.0 binaire) ; USDZ optionnel pour AR iOS |
| Nommage | `snake_case`, jamais d'espaces ni d'accents |

## Mannequins

Les modèles intégrés le 5 octobre 2026 sont conservés sans transformation : deux meshes `Mannequin_Body` et `Mannequin_Briefs`, matériaux mats, sans textures ni rig. Ils dépassent le budget initial ci-dessous (126 691 / 154 102 triangles). Ce budget reste un objectif de performance, pas une description des fichiers livrés. Voir `MANNEQUIN_INTEGRATION.md` pour les vérifications et limites. Le générateur de placeholders a été retiré pour éviter d'écraser ces fichiers.

- Mesh unique skinné, **rig humanoïde** (Hips → Spine → … → Head, bras/jambes) pour poses futures.
- Polycount : ≤ 25 000 tris (LOD1 ≤ 8 000 si fourni : `female_lod1.glb`).
- UV unwrap propre, **aucune texture requise** (matériau PBR matte uni).
- Points d'ancrage (empties) : `anchor_head`, `anchor_face`, `anchor_ears_l/r`, `anchor_torso`, `anchor_wrist_l/r`, `anchor_waist`, `anchor_legs`, `anchor_feet` — utilisés pour poser les vêtements génériques.

## Vêtements (Level 1 — génériques par catégorie/couleur)

- Un GLB par **catégorie** (slug API) : `tshirt.glb`, `coat.glb`, `jeans.glb`, `sneakers.glb`, `watch.glb`, `beanie.glb`, `sunglasses.glb`, `dress.glb`, …
- Colorisés à runtime via `baseColorFactor` → **modéliser en gris neutre**, matériau PBR `metallic=0`, `roughness 0.6–0.95`.
- Chaque asset doit référencer l'ancre correspondante du mannequin et être pré-positionné pour un mannequin 1,70/1,80 m.
- Polycount : ≤ 8 000 tris par pièce.

## Textures (si motifs)

- WebP (ou KTX2/basisu pour la compression GPU), 1024² max, sRGB pour baseColor, linéaire pour normal/roughness.
- UV sans chevauchement pour les zones texturées.

## Niveaux de représentation (`visual_representation_level`)

| Niveau | Sens | Asset |
|---|---|---|
| `generic` | fidèle catégorie + couleur | `clothing/<slug>.glb` teinté |
| `approximate` | modèle proche du produit | `clothing/<slug>_<variant>.glb` |
| `exact` | modèle 3D du vrai produit | asset dédié, `asset_key` côté API |

L'UI affiche honnêtement le niveau au utilisateur ; jamais de prétention de « simulation textile parfaite » depuis une photo.

## Export Blender

1. `File → Export → glTF 2.0 (.glb)` — *Include: selected objects*, *+Y up*, *Apply modifiers*.
2. Draco compression optionnelle (`compression: meshopt/Draco` supportée côté viewer).
3. Vérifier dans https://gltf-viewer.donmccurdy.com avant livraison.
