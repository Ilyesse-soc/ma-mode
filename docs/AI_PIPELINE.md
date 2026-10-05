# Pipeline IA d'identification produit

```
photo / code-barres
   ↓
upload validé (MIME réel via Pillow, taille ≤ 10 Mo, URL signée)
   ↓
AIProvider (clé SERVEUR uniquement) — sortie JSON structurée
   ↓
validation Pydantic stricte (LabelExtraction / GarmentVisualAnalysis)
   ↓
normalisation + recherche produit (ProductSearchProvider chain)
   ↓
candidats + confidence score (borné ≤ 0.95)
   ↓
CONFIRMATION UTILISATEUR  → application des champs
```

## Règle absolue

L'IA **n'invente jamais une référence produit** :

- le prompt vision exige « reference ONLY if clearly printed — never guess » ;
- la confiance est bornée à 0.95 ;
- confiance ≥ 0.85 → « matched » ; 0.5–0.85 → « Nous pensons avoir trouvé ce produit » (candidats affichés) ; < 0.5 → « not_found », l'utilisateur complète ;
- rien n'est appliqué sans `POST /garments/{id}/candidates/{cid}/confirm` ;
- chaque candidat garde `source`, `confidence`, `status` (pending/confirmed/rejected).

## Providers

`AIProvider` (registre) : `openai_compatible` (défaut, `AI_BASE_URL` + `AI_VISION_MODEL` configurables — compatible OpenAI, Azure OpenAI, proxies locaux type Ollama/LiteLLM). Ajouter un provider = une classe + une entrée de registre.

`ProductSearchProvider` : `upcitemdb` (base publique de codes-barres). **Pas de scraping contraire aux CGU** — uniquement des APIs autorisées.

## Validation

- Toute réponse IA est re-parsée par Pydantic ; JSON invalide → `503 ai_unavailable` (jamais de valeur fabriquée).
- L'image n'est jamais persistée par le provider ; seul un extrait textuel court (`raw_excerpt` ≤ 2000 car.) est stocké.
