# Corrections UX et préparation du test local — 5 octobre 2026

## Fonctionnalités livrées

- GPS : coordonnées précises transmises temporairement à la météo et au géocodage IGN/BAN ; Poissy/Yvelines vérifié avec le service réel. Aucun Paris par défaut. Position approximative, refus, GPS désactivé et échec distincts, choix manuel, actualisation et protection contre une réponse tardive après logout. Arrondi à deux décimales avant persistance seulement ; textes de confidentialité actualisés.
- Design : hiérarchie display/headline/title/body/label explicite, Inter embarquée et police système iOS. Les quatre images fournies servent au splash et aux trois pages d’onboarding ; teintes sombres et boutons beige conservés.
- Garde-robe vide : un seul bouton principal d’ajout. Les quatre méthodes donnent leur usage. Guides avant la caméra : exemples d’étiquettes illustratifs et conseils pour la photo entière. Sans étiquette, photo vêtement ou saisie manuelle.
- Mon mannequin : accessible Accueil/Garde-robe, vrais GLB suivant le profil, neutral pose, commandes de zones, filtres Tout/Hauts/Bas/Vestes/Chaussures/Accessoires, uniquement les pièces du compte. Choix, remplacement dans un slot, retrait, sauvegarde et port via les vrais endpoints. Une robe remplace haut/bas tout en conservant une veste éventuelle. Ajouter depuis une catégorie vide préremplit celle-ci.
- Habillage : `OutfitComposer` crée un GLB dérivé seulement en mémoire. Géométrie générique par catégorie/couleur ; aucun original ni mesh `Mannequin_Body`/`Mannequin_Briefs` modifié. Hauts, bas, robes/jupes, chaussures et accessoires ont une représentation de niveau 1. La couleur inconnue est neutre, pas devinée ; coupe/motifs/marque exacts ne sont pas affirmés. Les bijoux/accessoires non spécifiques utilisent une forme générique signalée par ce niveau.
- Dressing : décor léger dessiné en 2D, éclairage neutre, chargement à l’ouverture, une composition par sélection. Rotation manuelle avec inertie, zoom, recentrage double-tap, indicateur de chargement et erreur/réessai, aucune rotation automatique imposée.
- Recommandation : les vrais identifiants de la proposition habillent le même composant ; modifier une pièce conserve les autres puis sauvegarde/porte la sélection réelle. Les explications de la proposition initiale sont identifiées comme telles après personnalisation.
- UPCitemdb gratuit : route trial sans clé, quotas partagés Redis, lecture des en-têtes, timeout, 404/429 et fallback ; cache récent limité au propriétaire. L’enrichissement catalogue ne bloque plus une extraction OCR réelle. Le JSON Gemini utilise un schéma strict et un raisonnement minimal pour réserver son budget borné à la réponse.
- Local : lanceurs démarrage/arrêt, rechargement explicite du backend, gestion des processus enfants Windows, documentation depuis un clone neuf. `.env` privé jamais publié ; trois `.env.example` complets avec secrets vides.

## Preuves et périmètre

- Backend : 103 tests réussis, Ruff et mypy réussis (67 fichiers).
- Flutter : `flutter analyze` sans problème, 35 tests réussis ; build web JavaScript réussi. La vérification WASM signale les APIs web du stockage sécurisé ; le build JavaScript reste fonctionnel.
- [E2E local réel](E2E_LOCAL_CHECK.json) : PostgreSQL, Redis, MinIO privé, UPC connu et EAN valide inconnu, images de test réellement envoyées à Gemini avec consentement, confirmation, destination, météo, recommandation, feedback, tenue/historique, ZIP, logout/relogin et suppression du seul compte de test.
- [Rendu 3D](DRESSING_RENDER_CHECK.json) : deux GLB composés, rotations 90/180/270/360°, zoom, dimensions/centrage et échec d’asset. Les mesures de chargement sont celles d’Edge sur ce poste, pas celles d’un téléphone.
- [Navigateur Flutter](DRESSING_BROWSER_CHECK.json) : interactions réelles à 390 × 844 ; registre des contrôles vérifiés, distinct des tests API et widget.
- Scans : Gitleaks, Bandit, Semgrep, pip-audit et Trivy. Les rapports JSON figurent dans `docs/`. Le gate production reste bloquant sur les paramètres et informations externes manquants.

## Fichiers principaux de cette correction

`apps/api/app/core/config.py`, `errors.py`, `outbound.py` ; `modules/locations/geocoding.py`/`router.py` ; `modules/product_search/providers.py`/`budget.py`/`cache.py`/`router.py` ; `modules/product_recognition/providers.py`/`pipeline.py` ; `modules/wardrobe/router.py` ; `tests/test_upcitemdb_and_location.py`.

`apps/mobile/lib/core/theme/app_theme.dart`, `core/router.dart` ; `features/location/location_controller.dart`/`destination_screen.dart` ; `features/home/home_screen.dart` ; `features/wardrobe/screens/wardrobe_screen.dart`/`add_garment_screen.dart`/`photo_guide_screen.dart` ; `features/mannequin/mannequin_screen.dart`/`mannequin_viewer.dart`/`outfit_composer.dart` ; `features/recommendation/outfit_flow_screen.dart` ; `features/onboarding/onboarding_screen.dart` ; `features/splash/splash_screen.dart` ; `web/index.html`/`web/mannequin-runtime.js` (chargement local du renderer, cycle de chargement et erreur/r?essai web) ; `pubspec.yaml` ; `test/product_ux_test.dart`/`mannequin_viewer_test.dart`.

`.gitignore`, `.env.example`, `apps/api/.env.example`, `infra/.env.example`, `.github/workflows/ci.yml`, `scripts/local_runtime.py`, `local-processes.ps1`, `start-local.ps1`, `stop-local.ps1`, `build_local_minio.py`, `e2e_local.py`, `check_tracked_secrets.py`, `README.md`, documents et rapports associés. Les véritables GLB sont conservés à leurs chemins canoniques.

## Limites restantes

Aucun appareil Android/iOS connecté : GPS/caméra physiques, pinch/touch natifs, performances/FPS/mémoire GPU, signature release et partage restent à vérifier sur appareil. Les interactions 3D navigateur utilisent le vrai renderer, sans constituer une mesure mobile. Les modèles ne sont pas riggés : pas d’autre pose animée. Les commandes de zones filtrent la garde-robe ; elles ne réalisent pas un picking précis des triangles anatomiques. Assets exacts de vêtements, coupes et motifs restent à fournir si le niveau 3 est souhaité ; niveau 1 disponible.

SMTP, alertes, Sentry, mentions légales et TLS/signature production restent à configurer pour une distribution publique. Le géocodage IGN couvre la France, avec saisie manuelle hors couverture. Une reprise entièrement hors ligne après fermeture n’est pas certifiée ; le cache de garde-robe et les erreurs réseau sont testés séparément. Les erreurs temporaires de fournisseurs restent possibles ; aucune réponse n’est remplacée par une donnée de démonstration.
