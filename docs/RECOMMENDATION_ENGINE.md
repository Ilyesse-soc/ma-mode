# Moteur de recommandation

## Philosophie

**Déterministe d'abord, IA ensuite.** Les suggestions reposent sur des règles + un scoring explicable — jamais exclusivement sur un LLM. Chaque proposition affiche *pourquoi* elle est proposée.

## Fenêtre météo (origine + destination)

```
now ──────────────────────────────► now + 12 h (ou arrivée + 4 h)
origine : hourly points
destination : hourly points (si déplacement)
      ↓
WeatherWindow {
  min/max feels_like, max precip_probability, max precip_mm, max wind, max uv
}
```

La destination pèse autant que l'origine : un soir froid/pluvieux à Lille change la tenue même si Paris est doux.

## Scoring par pièce (0..1)

| Sous-score | Logique |
|---|---|
| `temperature` | la chaleur de la pièce couvre-t-elle l'écart entre le ressenti minimal et le seuil « froid » de l'utilisateur (+ offset appris), sans surchauffer au plus chaud |
| `rain` | imperméabilité exigée si pluie ≥ 50 % ou ≥ 2 mm (couches externes + chaussures) |
| `wind` | coupe-vent si rafales ≥ 35 km/h ; chapeaux pénalisés |
| `style` | recouvrement avec les styles préférés |
| `color` | couleurs aimées ++, couleurs évitées → multiplicateur ×0.7 |
| `activity` | formel/sport/quotidien ajuste les sous-catégories |
| `recently_worn_penalty` | porté < 48 h → −0.35 |

Poids : température 0.30, pluie 0.18, vent 0.10, style 0.12, couleur 0.10, activité 0.12, disponibilité +0.08.

## Assemblage

1. Trier chaque groupe (haut/base, bas, chaussures, tête, poignets) par score.
2. Choisir une **couche externe** si froid/pluie/vent le justifie.
3. Combinaisons bornées (4 hauts × 4 bas + robes), chaussures meilleures, accessoires.
4. **Compatibilité couleurs** : neutres avec tout, clashes connus pénalisés, > 3 couleurs fortes pénalisé.
5. **Anti-répétition** : les 10 dernières combinaisons portées sont exclues.
6. **3 propositions maximum**, avec explications en français.

## Apprentissage (transparent)

- `too_cold` → `learned_warmth_offset += 1` (borné ±5 °C)
- `too_hot` → `learned_warmth_offset -= 1`
- `like` / `not_today` / `dislike_combination` → marqueurs d'acceptation sur la recommandation.

Aucune boîte noire : l'offset est visible dans l'export RGPD et réinitialisable.

## Tests

`tests/test_engine.py` : froid → couche chaude ; pluie → imperméable ; canicule → pas de manteau ; destination Lille le soir → fenêtre correcte ; couleur évitée pénalisée ; tenue récemment portée non reproposée ; ≤ 3 propositions ; garde-robe vide.
