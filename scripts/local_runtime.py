"""Local services with generated secrets. Never print credentials or tokens."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import secrets
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".local"
sys.path.insert(0, str(ROOT / "apps" / "api"))


def prepare():
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from dotenv import dotenv_values

    LOCAL.mkdir(exist_ok=True)
    if (LOCAL / "api.env").exists():
        existing = dotenv_values(LOCAL / "api.env")
        additions = {
            "UPCITEMDB_MODE": "trial",
            "UPCITEMDB_BASE_URL": "https://api.upcitemdb.com/prod/trial",
            "UPCITEMDB_API_KEY": "",
            "BARCODE_CACHE_TTL_SECONDS": "86400",
            "GEOCODING_BASE_URL": "https://data.geopf.fr/geocodage",
        }
        with (LOCAL / "api.env").open("a", encoding="utf8") as configuration:
            for name, value in additions.items():
                if name not in existing:
                    configuration.write(name + "=" + json.dumps(value) + "\n")
        print("Existing local secrets preserved.")
        return
    credentials = {"POSTGRES_ADMIN_PASSWORD": secrets.token_urlsafe(32), "POSTGRES_APP_PASSWORD": secrets.token_urlsafe(32), "REDIS_PASSWORD": secrets.token_urlsafe(32), "MINIO_ROOT_USER": "dressly-" + secrets.token_hex(6), "MINIO_ROOT_PASSWORD": secrets.token_urlsafe(32)}
    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    legacy = dotenv_values(ROOT / "infra" / ".env")
    values = {
        "ENVIRONMENT": "development", "APP_DEBUG": "false", "ALLOW_DEV_TOKENS": "false",
        "DATABASE_URL": f"postgresql+asyncpg://dressly_app:{credentials['POSTGRES_APP_PASSWORD']}@127.0.0.1:15432/dressly",
        "JWT_PRIVATE_KEY_PEM": key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode(),
        "JWT_PUBLIC_KEY_PEM": key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode(),
        "RATE_LIMIT_STORAGE_URI": f"redis://:{credentials['REDIS_PASSWORD']}@127.0.0.1:16379/0",
        "RATE_LIMIT_KEY_SECRET": secrets.token_urlsafe(48),
        "CORS_ALLOWED_ORIGINS": "http://127.0.0.1:18080,http://localhost:18080",
        "PUBLIC_API_URL": "http://127.0.0.1:18000",
        "WEATHER_PROVIDER": "openmeteo", "PRODUCT_SEARCH_PROVIDERS": "upcitemdb",
        "S3_ENDPOINT_URL": "http://127.0.0.1:19000", "S3_PUBLIC_ENDPOINT_URL": "http://127.0.0.1:19000",
        "S3_ACCESS_KEY": credentials["MINIO_ROOT_USER"], "S3_SECRET_KEY": credentials["MINIO_ROOT_PASSWORD"], "S3_BUCKET": "dressly-local-media",
        "AI_PROVIDER": legacy.get("AI_PROVIDER") or "openai_compatible",
        "AI_VISION_MODEL": legacy.get("AI_VISION_MODEL") or "gpt-4o-mini",
        "AI_API_KEY": legacy.get("AI_API_KEY") or "",
        "GEMINI_API_KEY": legacy.get("GEMINI_API_KEY") or "",
        "GROQ_API_KEY": legacy.get("GROQ_API_KEY") or "",
        "AI_BASE_URL": legacy.get("AI_BASE_URL") or "https://api.openai.com/v1",
        "UPCITEMDB_MODE": "trial", "UPCITEMDB_API_KEY": "",
        "UPCITEMDB_BASE_URL": "https://api.upcitemdb.com/prod/trial",
        "BARCODE_CACHE_TTL_SECONDS": "86400",
        "GEOCODING_BASE_URL": "https://data.geopf.fr/geocodage",
    }
    for filename, content in [("api.env", values), ("services.env", credentials)]:
        (LOCAL / filename).write_text("\n".join(k + "=" + json.dumps(v) for k, v in content.items()) + "\n", encoding="utf8")
    # These values are generated URL-safe server secrets, never client input.
    sql = "CREATE ROLE dressly_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '" + credentials["POSTGRES_APP_PASSWORD"] + "';\nGRANT ALL PRIVILEGES ON DATABASE dressly TO dressly_app;\nGRANT USAGE, CREATE ON SCHEMA public TO dressly_app;\n"
    (LOCAL / "init-db.sql").write_text(sql, encoding="utf8")
    print("Generated isolated local configuration; secrets remain in ignored .local files.")


def load():
    from dotenv import load_dotenv
    load_dotenv(LOCAL / "api.env", override=True)


async def bootstrap():
    from sqlalchemy import select
    from app.db.session import dispose_engine, get_session_factory, init_engine
    from app.modules.media.storage import configure_local_lifecycle, ensure_bucket_exists, verify_private_bucket
    from app.modules.wardrobe.catalog import CATEGORY_SEED
    from app.modules.wardrobe.models import GarmentCategory

    ensure_bucket_exists()
    verify_private_bucket()
    configure_local_lifecycle()
    init_engine()
    async with get_session_factory()() as db:
        existing = set(await db.scalars(select(GarmentCategory.slug)))
        for index, entry in enumerate(CATEGORY_SEED):
            if entry["slug"] not in existing:
                db.add(GarmentCategory(**entry, sort_order=index))
        await db.commit()
    await dispose_engine()
    print("Private S3 bucket, lifecycle and actual garment catalog verified.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["prepare", "migrate", "bootstrap", "api", "cleanup", "minio"])
    command = parser.parse_args().command
    if command == "prepare":
        prepare()
    elif command == "minio":
        from dotenv import dotenv_values
        os.environ.update({k: v for k, v in dotenv_values(LOCAL / "services.env").items() if v is not None})
        os.environ["MINIO_BROWSER_REDIRECT_URL"] = "http://127.0.0.1:19001"
        os.execv(str(ROOT / ".tmp" / "security-tools" / "minio.exe"), ["minio", "server", str(LOCAL / "minio-data"), "--address", "127.0.0.1:19000", "--console-address", "127.0.0.1:19001"])
    else:
        load()
        if command == "migrate":
            from alembic.config import Config
            from alembic import command as migrations
            os.chdir(ROOT / "apps" / "api")
            migrations.upgrade(Config("alembic.ini"), "head")
        elif command == "bootstrap":
            asyncio.run(bootstrap())
        elif command == "api":
            import uvicorn
            uvicorn.run("app.main:app", host="127.0.0.1", port=18000, access_log=False)
        elif command == "cleanup":
            import runpy
            sys.argv = ["cleanup.py", "--loop"]
            runpy.run_path(str(ROOT / "apps/api/scripts/cleanup.py"), run_name="__main__")
