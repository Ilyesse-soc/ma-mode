"""Test fixtures: ephemeral RSA keys, SQLite in-memory DB, ASGI client."""

import os
import uuid
from contextlib import asynccontextmanager

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import ASGITransport, AsyncClient

# --- Environment MUST be set before importing app modules (settings are cached).
_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_priv = _key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
).decode()
_pub = (
    _key.public_key()
    .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    .decode()
)

os.environ.update(
    {
        "ENVIRONMENT": "development",
        "DATABASE_URL": "sqlite+aiosqlite://",
        "JWT_PRIVATE_KEY_PEM": _priv,
        "JWT_PUBLIC_KEY_PEM": _pub,
        "WEATHER_PROVIDER": "openmeteo",
        "RATE_LIMIT_AUTH": "1000/minute",
        "PRODUCT_SEARCH_PROVIDERS": "",
        "ALLOW_DEV_TOKENS": "true",
        "RATE_LIMIT_ACCOUNT": "1000/minute",
    }
)

# Import all models so create_all sees them.
import app.modules.audit.models  # noqa: E402
import app.modules.locations.router  # noqa: E402
import app.modules.outfits.models  # noqa: E402
import app.modules.recommendations.models  # noqa: E402
import app.modules.users.models  # noqa: E402
import app.modules.wardrobe.models  # noqa: E402
import app.modules.weather.router  # noqa: E402,F401
from app.db.session import Base, dispose_engine, get_session_factory, init_engine  # noqa: E402
from app.main import create_app  # noqa: E402
from app.modules.wardrobe.catalog import CATEGORY_SEED  # noqa: E402
from app.modules.wardrobe.models import GarmentCategory  # noqa: E402


@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def db_ready():
    init_engine("sqlite+aiosqlite://")
    factory = get_session_factory()
    async with factory() as session:
        async with session.bind.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)
        for i, entry in enumerate(CATEGORY_SEED):
            session.add(GarmentCategory(**entry, sort_order=i))
        await session.commit()
    yield
    await dispose_engine()


@pytest.fixture
async def client(db_ready):
    app = create_app()
    # Bypass lifespan (engine already initialized with test DB).
    app.router.lifespan_context = lambda _app: _null_lifespan()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@asynccontextmanager
async def _null_lifespan():
    yield


BASE = "/api/v1"


async def register_user(client: AsyncClient, email: str | None = None, first_name: str = "Alex"):
    email = email or f"user-{uuid.uuid4().hex[:8]}@test.dev"
    resp = await client.post(
        f"{BASE}/auth/register",
        json={
            "first_name": first_name,
            "email": email,
            "password": "super-secret-10",
            "mannequin_presentation": "male",
        },
    )
    assert resp.status_code == 201, resp.text
    return email, resp.json()["access_token"], resp.json()["refresh_token"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}
