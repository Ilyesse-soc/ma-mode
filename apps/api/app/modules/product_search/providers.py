"""Product search provider abstraction.

Implementations must be ToS-compliant (official APIs / open databases only).
Providers are tried in configured order; swap or add implementations without
touching callers.
"""

from pydantic import Field, ValidationError
from starlette.concurrency import run_in_threadpool

from app.core.config import get_settings
from app.core.logging import get_logger
from app.core.outbound import bounded_json_request
from app.core.validation import StrictModel
from app.modules.product_search import budget

log = get_logger("product_search")


class ProductCandidate(StrictModel):
    name: str = Field(min_length=1, max_length=160)
    brand: str | None = Field(default=None, max_length=120)
    reference: str | None = Field(default=None, max_length=160)
    color: str | None = Field(default=None, max_length=60)
    category_hint: str | None = Field(default=None, max_length=64)
    ean: str | None = Field(default=None, max_length=14, pattern=r"^[0-9]+$")
    upc: str | None = Field(default=None, max_length=14, pattern=r"^[0-9]+$")
    gtin: str | None = Field(default=None, max_length=14, pattern=r"^[0-9]+$")
    images: list[str] = Field(default_factory=list, max_length=5)
    confidence: float = Field(default=0, ge=0, le=1)
    source: str = Field(default="unknown", max_length=40)


class ProductSearchProvider:
    name: str = "base"

    async def search_by_barcode(self, barcode: str) -> list[ProductCandidate]:
        raise NotImplementedError

    async def search_by_text(self, query: str) -> list[ProductCandidate]:
        raise NotImplementedError


class UpcItemDbProvider(ProductSearchProvider):
    """UPCitemdb trial API (public barcode database)."""

    name = "upcitemdb"

    async def _search(self, endpoint: str, params: dict, confidence: float) -> list[ProductCandidate]:
        from app.core.errors import upstream_unavailable
        from app.core.outbound import validate_public_url

        settings = get_settings()
        paid = settings.upcitemdb_mode == "paid" and bool(settings.upcitemdb_api_key)
        base = settings.upcitemdb_base_url.rstrip("/")
        if not paid:
            base = "https://api.upcitemdb.com/prod/trial"
        elif base.endswith("/trial"):
            base = "https://api.upcitemdb.com/prod/v1"
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        if paid:
            headers.update(user_key=settings.upcitemdb_api_key, key_type="3scale")
        await run_in_threadpool(budget.reserve, endpoint)
        data, response_headers, status = await bounded_json_request(
            "GET",
            base + "/" + endpoint,
            params=params,
            headers=headers,
            request_timeout=10,
            allowed_statuses=frozenset({200, 404, 429}),
            return_metadata=True,
        )
        await run_in_threadpool(budget.remember_headers, response_headers, status)
        if status == 404:
            return []
        if status == 429:
            try:
                seconds = int(response_headers.get("retry-after", "60"))
            except ValueError:
                seconds = 60
            raise budget.unavailable(seconds)
        if not isinstance(data, dict) or not isinstance(data.get("items", []), list):
            from app.core.errors import upstream_unavailable

            raise upstream_unavailable("catalog")
        result = []
        for item in data.get("items", [])[:5]:
            if not isinstance(item, dict):
                continue
            from app.core.errors import ApiError

            images = []
            raw_images = item.get("images", [])
            if isinstance(raw_images, list):
                for url in raw_images[:5]:
                    if not isinstance(url, str) or len(url) > 2048:
                        continue
                    try:
                        images.append(validate_public_url(url, resolve=False))
                    except ApiError:
                        continue
            try:
                result.append(
                    ProductCandidate(
                        name=item.get("title", ""),
                        brand=item.get("brand") or None,
                        reference=item.get("model") or item.get("ean") or None,
                        color=item.get("color") or None,
                        category_hint=(
                            item["category"][:64] if isinstance(item.get("category"), str) else None
                        ),
                        ean=item.get("ean") or None,
                        upc=item.get("upc") or None,
                        gtin=item.get("gtin") or None,
                        images=images,
                        confidence=confidence,
                        source=self.name,
                    )
                )
            except (ValidationError, ValueError):
                log.warning("catalog.invalid_candidate")
        return result

    async def search_by_barcode(self, barcode: str) -> list[ProductCandidate]:
        return await self._search("lookup", {"upc": barcode}, 0.7)

    async def search_by_text(self, query: str) -> list[ProductCandidate]:
        return await self._search("search", {"s": query}, 0.5)


_PROVIDER_REGISTRY: dict[str, type[ProductSearchProvider]] = {
    "upcitemdb": UpcItemDbProvider,
}


def get_product_search_providers() -> list[ProductSearchProvider]:
    settings = get_settings()
    providers: list[ProductSearchProvider] = []
    for name in settings.product_search_providers.split(","):
        name = name.strip()
        cls = _PROVIDER_REGISTRY.get(name)
        if cls is not None:
            providers.append(cls())
        else:
            log.warning("product_search.unknown_provider", provider=name)
    return providers
