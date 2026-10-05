"""French commune reverse geocoding through the official IGN/BAN service."""

from pydantic import Field

from app.core.config import get_settings
from app.core.errors import upstream_unavailable
from app.core.outbound import bounded_json_request
from app.core.validation import StrictModel


class Commune(StrictModel):
    label: str = Field(min_length=1, max_length=160)
    administrative_area: str | None = Field(default=None, max_length=160)
    attribution: str = "Source : IGN / Base Adresse Nationale"


async def reverse(latitude, longitude):
    data = await bounded_json_request(
        "GET",
        get_settings().geocoding_base_url.rstrip("/") + "/reverse",
        params={"lat": latitude, "lon": longitude, "index": "address", "limit": 1},
        headers={"Accept": "application/json"},
        request_timeout=10,
    )
    try:
        properties = data["features"][0]["properties"]
        context = properties.get("context") or ""
        parts = [part.strip() for part in context.split(",")]
        return Commune(label=properties["city"], administrative_area=parts[1] if len(parts) > 1 else None)
    except (KeyError, IndexError, TypeError, ValueError):
        raise upstream_unavailable("geocoding") from None
