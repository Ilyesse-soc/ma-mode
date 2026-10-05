# Dressly — À la Mode

Flutter + FastAPI : vraie garde-robe, météo et destinations, recommandations expliquées, dressing 3D, historique, export et suppression de compte. Aucune garde-robe de démonstration n’est chargée au démarrage.

## Tester localement

Sur cette machine : **http://127.0.0.1:18080**. API : `http://127.0.0.1:18000/health` et `/readiness`. Créer son compte et ajouter ses propres vêtements.

```powershell
cd D:\alamode
.\scripts\start-local.ps1
# Pour recharger les modifications serveur :
.\scripts\start-local.ps1 -RestartServices
# Arrêt limité aux processus du projet, données conservées :
.\scripts\stop-local.ps1
```

## Installer depuis GitHub — Windows / PowerShell

Prérequis : Git, Python 3.13, Flutter 3.41.4 dans PATH, Docker Desktop avec conteneurs Linux démarré.

```powershell
git clone https://github.com/Ilyesse-soc/ma-mode.git
cd ma-mode
python -m venv apps/api/.venv
apps/api/.venv/Scripts/python.exe -m pip install pip==26.2.1
apps/api/.venv/Scripts/python.exe -m pip install --require-hashes -r apps/api/requirements-dev.txt
Push-Location apps/mobile
flutter pub get --enforce-lockfile
Pop-Location
# Source officielle MinIO épinglée et Go avec SHA256 vérifié ; compilation locale :
apps/api/.venv/Scripts/python.exe scripts/build_local_minio.py
.\scripts\start-local.ps1
```

La première compilation du stockage peut prendre plusieurs minutes. MinIO amont est archivé : cette instance est réservée aux tests locaux. La production exige un stockage S3 maintenu.

Le lanceur génère RSA, secrets PostgreSQL/Redis/S3 dans `.local/api.env` et `.local/services.env`, ignorés par Git. Il applique Alembic, amorce les seules catégories métier, configure un bucket privé, lance API/worker et exécute `flutter analyze`, `flutter test`, puis construit/sert Flutter web. `-SkipChecks` évite leur répétition pendant le développement sans désactiver de protection. Ports localhost : API 18000, web 18080, PostgreSQL 15432, Redis 16379, S3 19000, console 19001. Les secrets et volumes sont conservés.

## Variables et secrets

[.env.example](.env.example), [apps/api/.env.example](apps/api/.env.example) et [infra/.env.example](infra/.env.example) contiennent les variables complètes, avec secrets vides. **Ne jamais committer `.env`, ses variantes, clés privées ou identifiants.** Le lanceur charge explicitement `.local/api.env` ; un serveur indépendant peut charger son `.env` privé.

Pour l’IA, configurer côté serveur `AI_PROVIDER`, `AI_VISION_MODEL` et une clé : `gemini`/`GEMINI_API_KEY`, `groq`/`GROQ_API_KEY`, ou `openai_compatible`/`AI_API_KEY`/`AI_BASE_URL`. `AI_API_KEY` est prioritaire. Avec Groq, choisir son modèle vision, pas un modèle OpenAI. La clé déjà configurée sur cette machine reste privée. Relancer avec `-RestartServices` après une modification. Les sorties sont strictement validées et demandent confirmation ; la saisie manuelle reste disponible.

Seuls `API_BASE_URL` et `ENVIRONMENT` sont transmis à Flutter, jamais des clés IA/UPC/S3/JWT. SMTP est nécessaire aux vrais emails (`SMTP_HOST`, `SMTP_FROM`, identifiants, lien de compte). Sans SMTP, la récupération annonce son indisponibilité, sans faux envoi. L’inscription locale fonctionne ; la production impose la vérification email et une configuration stricte. Sentry/alertes sont optionnels localement ; signature Android, TLS et informations légales restent requis pour distribuer en production.

## UPCitemdb FREE

`UPCITEMDB_MODE=trial`, `UPCITEMDB_BASE_URL=https://api.upcitemdb.com/prod/trial`, `UPCITEMDB_API_KEY=`. Explorer FREE ne demande ni compte, ni clé, ni carte bancaire. Le backend appelle `/lookup?upc=…`, avec `Accept` et `Content-Type: application/json`, sans `user_key`/`key_type`. [Documentation officielle](https://devs.upcitemdb.com/).

Le quota gratuit combine 100 requêtes/jour. Le backend borne les lookups à six/minute et la recherche texte à deux/minute, lit `X-RateLimit-Limit`, `Remaining`, `Reset`, `Retry-After` et partage le cooldown dans Redis. Les propositions récentes sont mises en cache en base pour leur seul propriétaire (`BARCODE_CACHE_TTL_SECONDS=86400`). Code inconnu, quota et panne conservent les parcours photo/étiquette/manuels. L’enrichissement catalogue est facultatif lorsqu’une extraction OCR a réussi. Le mode payant exige explicitement `UPCITEMDB_MODE=paid` et une clé serveur.

## GPS et dressing 3D

La météo reçoit temporairement les coordonnées précises ; [IGN/BAN](https://ignf.github.io/cartes.gouv.fr-documentation/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/geocodage/) détermine la commune et le département, sans Paris par défaut. Refus, GPS approximatif et erreurs sont affichés ; choix manuel et actualisation restent accessibles. Le géocodage couvre la France ; hors couverture, choisir la destination manuellement. Les coordonnées enregistrées sont arrondies à deux décimales.

« Mon mannequin » est accessible depuis Accueil et Garde-robe. `MannequinViewer` charge `apps/mobile/assets/3d/mannequins/male.glb` ou `female.glb` selon le profil. Les originaux fournis restent inchangés. Rotation, zoom, recentrage et erreur/reprise sont présents. Les vêtements réels peuvent être choisis, remplacés, retirés et sauvegardés via l’API ; les recommandations peuvent aussi être adaptées. `OutfitComposer` crée uniquement en mémoire une représentation générique par catégorie/couleur. Elle ne reproduit pas exactement coupes, marques ou motifs. Le décor du dressing est léger et dessiné en 2D.

## Vérifications

```powershell
Push-Location apps/api
.venv/Scripts/python.exe -m ruff check .
.venv/Scripts/python.exe -m mypy app
.venv/Scripts/python.exe -m pytest -q
Pop-Location
Push-Location apps/mobile
flutter analyze
flutter test
Pop-Location
# Services locaux démarrés ; appels externes et compte temporaire effacé :
apps/api/.venv/Scripts/python.exe scripts/e2e_local.py
apps/api/.venv/Scripts/python.exe scripts/backup_and_restore_local.py
```

La CI contient tests, Gitleaks sur tout l’historique, Bandit, Semgrep, audit des dépendances, Trivy et build Android debug. Le gate production refuse les secrets/configurations incomplets et les mentions légales non renseignées. Authentification, autorisations, rotation des sessions, quotas, stockage privé et protection SSRF restent actifs.

Voir [test local](docs/LOCAL_TESTING.md), [rapport E2E](docs/E2E_LOCAL_CHECK.json), [audit sécurité](docs/SECURITY_AUDIT_REPORT.md), [architecture](docs/ARCHITECTURE.md), [confidentialité](docs/PRIVACY.md) et [mentions légales](docs/LEGAL_CONFIGURATION.md). Caméra/GPS/partage/performance 3D natifs restent à valider sur Android/iOS physiques ; iOS requiert macOS/Xcode. Le navigateur valide les parcours et les gestes web.
