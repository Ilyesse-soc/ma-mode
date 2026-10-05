"""Application configuration. All secrets come from environment variables."""

from functools import lru_cache

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- Core ---
    environment: str = Field(default="development", pattern="^(development|staging|production)$")
    api_v1_prefix: str = "/api/v1"
    project_name: str = "À la Mode API"

    # --- Database ---
    database_url: str = "postgresql+asyncpg://alamode@localhost:5432/alamode"
    database_ca_file: str = ""

    # --- Auth / JWT ---
    jwt_private_key_pem: str = ""  # RS256 private key (PEM, may use \n escapes)
    jwt_public_key_pem: str = ""  # RS256 public key (PEM)
    jwt_algorithm: str = "RS256"
    access_token_ttl_seconds: int = 900  # 15 min
    refresh_token_ttl_seconds: int = 60 * 60 * 24 * 30  # 30 days

    # --- Weather provider ---
    weather_provider: str = "openmeteo"  # openmeteo (no key) | openweathermap
    openweathermap_api_key: str = ""

    # --- AI provider (server-side only, NEVER shipped to mobile) ---
    ai_provider: str = "openai_compatible"  # openai_compatible | anthropic
    ai_api_key: str = ""
    gemini_api_key: str = ""
    groq_api_key: str = ""
    ai_base_url: str = "https://api.openai.com/v1"
    ai_vision_model: str = "gpt-4o-mini"

    # --- Object storage (S3 compatible) ---
    s3_endpoint_url: str = "http://localhost:9000"
    s3_public_endpoint_url: str = "http://localhost:9000"
    s3_region: str = "eu-west-1"
    s3_access_key: str = ""
    s3_secret_key: str = ""
    s3_bucket: str = "alamode-media"
    s3_presign_ttl_seconds: int = 600
    max_upload_bytes: int = 10 * 1024 * 1024  # 10 MB

    # --- Product search providers ---
    product_search_providers: str = "upcitemdb"  # comma-separated, ordered
    upcitemdb_mode: str = Field(default="trial", pattern="^(trial|paid)$")
    upcitemdb_base_url: str = "https://api.upcitemdb.com/prod/trial"
    upcitemdb_api_key: str = ""
    barcode_cache_ttl_seconds: int = Field(default=86400, ge=60, le=604800)
    geocoding_base_url: str = "https://data.geopf.fr/geocodage"

    # --- Security ---
    cors_allowed_origins: str = "http://localhost:3000,http://localhost:8080"
    bcrypt_like_pepper: str = ""  # optional pepper for password hashing
    rate_limit_auth: str = "10/minute"
    rate_limit_default: str = "120/minute"
    rate_limit_storage_uri: str = "memory://"
    rate_limit_key_secret: str = ""
    rate_limit_account: str = "5/minute"
    rate_limit_upload: str = "20/minute"
    rate_limit_ai: str = "10/minute"
    rate_limit_barcode: str = "30/minute"
    max_json_body_bytes: int = Field(default=256 * 1024, ge=1024, le=1024 * 1024)
    max_image_pixels: int = Field(default=20_000_000, ge=1, le=40_000_000)
    max_image_dimension: int = Field(default=8192, ge=1, le=16384)
    debug: bool = Field(default=False, validation_alias="APP_DEBUG")
    public_api_url: str = "http://localhost:8000"
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    account_link_base_url: str = ""
    allow_dev_tokens: bool = False
    audit_retention_days: int = Field(default=90, ge=1, le=365)
    weather_retention_days: int = Field(default=30, ge=1, le=365)
    draft_retention_days: int = Field(default=7, ge=1, le=30)

    # --- Observability ---
    sentry_dsn: str = ""
    log_level: str = "INFO"
    sentry_environment: str = ""
    security_alert_email: str = ""

    @model_validator(mode="after")
    def _production_security(self):
        if not self.is_production:
            return self
        from urllib.parse import urlsplit

        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import rsa

        if self.debug or self.allow_dev_tokens or self.jwt_algorithm != "RS256":
            raise ValueError("Unsafe production debug/auth settings")
        if not 60 <= self.access_token_ttl_seconds <= 900 or not 30 <= self.s3_presign_ttl_seconds <= 600:
            raise ValueError("Production token lifetime outside allowed bounds")
        if (
            urlsplit(self.rate_limit_storage_uri).scheme not in {"redis", "rediss"}
            or len(self.rate_limit_key_secret) < 32
        ):
            raise ValueError("Production requires shared rate-limit storage and key secret")
        if not self.cors_origins or any(o == "*" or not o.startswith("https://") for o in self.cors_origins):
            raise ValueError("Production CORS must contain explicit HTTPS origins")
        if not self.public_api_url.startswith("https://") or not self.s3_public_endpoint_url.startswith(
            "https://"
        ):
            raise ValueError("Production public endpoints require HTTPS")
        database = urlsplit(self.database_url)
        if not database.scheme.startswith("postgresql") or database.username in {None, "postgres", "root"}:
            raise ValueError("Production requires a dedicated PostgreSQL application user")
        if (
            not database.password
            or len(database.password) < 20
            or database.password in {"alamode", "postgres"}
        ):
            raise ValueError("Weak production database credentials")
        if self.s3_access_key in {"", "minioadmin"} or self.s3_secret_key in {"", "minioadmin"}:
            raise ValueError("Default storage credentials prohibited in production")
        private = serialization.load_pem_private_key(self.jwt_private_key_pem.encode(), password=None)
        public = serialization.load_pem_public_key(self.jwt_public_key_pem.encode())
        if not isinstance(private, rsa.RSAPrivateKey) or private.key_size < 2048:
            raise ValueError("JWT signing key must be RSA >= 2048 bits")
        if (
            not isinstance(public, rsa.RSAPublicKey)
            or private.public_key().public_numbers() != public.public_numbers()
        ):
            raise ValueError("JWT keys do not match")
        if not self.smtp_host or not self.smtp_from or not self.account_link_base_url.startswith("https://"):
            raise ValueError("Production requires real email delivery and HTTPS account links")
        return self

    @field_validator("jwt_private_key_pem", "jwt_public_key_pem")
    @classmethod
    def _unescape_pem(cls, v: str) -> str:
        return v.replace("\\n", "\n")

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.cors_allowed_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
