# Déploiement

## Environnements

| Env | API | DB | Notes |
|---|---|---|---|
| development | `docker compose` local | PostgreSQL local (container) | Open-Meteo sans clé, MinIO |
| staging | VM/managé | PostgreSQL managé | clés réelles, domaine staging |
| production | managé + TLS | PostgreSQL managé + backups | `/docs` désactivé, HSTS |

## Backend (container)

```bash
docker build -t alamode-api apps/api
docker run --env-file .env -p 8000:8000 alamode-api
```

Le conteneur exécute `alembic upgrade head` au démarrage puis `uvicorn`. Utilisateur non-root, healthcheck `/health`, readiness `/readiness`.

### Variables production

Voir `apps/api/.env.example`. En production :

- `ENVIRONMENT=production`
- `DATABASE_URL` managé (TLS)
- `JWT_*_KEY_PEM` depuis le secret manager
- `S3_*` bucket réel avec politique privée (accès uniquement par URL signées)
- `CORS_ALLOWED_ORIGINS` restreint à vos domaines

## Mobile

```bash
# Android (SDK Android requis)
cd apps/mobile
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com/api/v1
# ou appbundle pour le Play Store
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.example.com/api/v1

# iOS (macOS + Xcode requis)
flutter build ipa --release --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

Signer via les mécanismes standards (Play App Signing / Xcode signing). Ne jamais embarquer de clé API : tout passe par le backend.

## Base de données

```bash
alembic upgrade head     # appliquer
alembic revision --autogenerate -m "..."   # nouvelle migration après changement de modèle
```

## Observabilité

- Logs JSON structurés (stdout) → collecteur de la plateforme.
- `SENTRY_DSN` (optionnel) pour l'error tracking.
- Health `/health`, readiness `/readiness` (vérifie la DB).
