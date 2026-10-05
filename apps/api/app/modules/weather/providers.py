"""Weather provider abstraction + implementations.

Interchangeable: WEATHER_PROVIDER env var selects the implementation.
Open-Meteo needs no key (default fallback); OpenWeatherMap is supported.
"""

import time
from dataclasses import dataclass, field

import httpx

from app.core.config import get_settings
from app.core.errors import upstream_unavailable
from app.core.logging import get_logger

log = get_logger("weather")


@dataclass
class HourlyPoint:
    timestamp: int  # epoch seconds UTC
    temperature_c: float
    feels_like_c: float
    precip_probability: float  # 0..1
    precip_mm: float
    wind_kmh: float
    gust_kmh: float
    humidity_pct: float
    uv_index: float | None
    condition: str  # normalized: clear, clouds, rain, snow, storm, fog


@dataclass
class WeatherReport:
    latitude: float
    longitude: float
    current: HourlyPoint
    hourly: list[HourlyPoint] = field(default_factory=list)
    provider: str = "unknown"
    fetched_at: float = field(default_factory=time.time)


class WeatherProvider:
    name: str = "base"

    async def forecast(self, latitude: float, longitude: float) -> WeatherReport:
        raise NotImplementedError


_OWM_CONDITION_MAP = {
    "Thunderstorm": "storm",
    "Drizzle": "rain",
    "Rain": "rain",
    "Snow": "snow",
    "Mist": "fog",
    "Fog": "fog",
    "Haze": "fog",
    "Clear": "clear",
    "Clouds": "clouds",
}


class OpenWeatherMapProvider(WeatherProvider):
    name = "openweathermap"
    BASE = "https://api.openweathermap.org"

    async def forecast(self, latitude: float, longitude: float) -> WeatherReport:
        settings = get_settings()
        if not settings.openweathermap_api_key:
            raise upstream_unavailable("weather")
        params: dict[str, str | int | float] = {
            "lat": latitude,
            "lon": longitude,
            "appid": settings.openweathermap_api_key,
            "units": "metric",
        }
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                current_resp = await client.get(f"{self.BASE}/data/2.5/weather", params=params)
                forecast_resp = await client.get(f"{self.BASE}/data/2.5/forecast", params=params)
            if current_resp.status_code != 200 or forecast_resp.status_code != 200:
                raise upstream_unavailable("weather")
            current_json = current_resp.json()
            forecast_json = forecast_resp.json()
        except httpx.HTTPError:
            raise upstream_unavailable("weather") from None

        def to_point(entry: dict) -> HourlyPoint:
            weather_main = (entry.get("weather") or [{}])[0].get("main", "Clear")
            return HourlyPoint(
                timestamp=int(entry["dt"]),
                temperature_c=float(entry["main"]["temp"]),
                feels_like_c=float(entry["main"].get("feels_like", entry["main"]["temp"])),
                precip_probability=float(entry.get("pop", 0.0)),
                precip_mm=float((entry.get("rain") or {}).get("3h", 0.0)),
                wind_kmh=float((entry.get("wind") or {}).get("speed", 0.0)) * 3.6,
                gust_kmh=float((entry.get("wind") or {}).get("gust", 0.0)) * 3.6,
                humidity_pct=float(entry["main"].get("humidity", 50)),
                uv_index=None,
                condition=_OWM_CONDITION_MAP.get(weather_main, "clouds"),
            )

        current = to_point({**current_json, "pop": 0})
        hourly = [to_point(e) for e in forecast_json.get("list", [])]
        return WeatherReport(
            latitude=latitude, longitude=longitude, current=current, hourly=hourly, provider=self.name
        )


_WMO_CONDITION_MAP = {
    0: "clear",
    1: "clear",
    2: "clouds",
    3: "clouds",
    45: "fog",
    48: "fog",
    51: "rain",
    53: "rain",
    55: "rain",
    56: "rain",
    57: "rain",
    61: "rain",
    63: "rain",
    65: "rain",
    66: "rain",
    67: "rain",
    71: "snow",
    73: "snow",
    75: "snow",
    77: "snow",
    80: "rain",
    81: "rain",
    82: "rain",
    85: "snow",
    86: "snow",
    95: "storm",
    96: "storm",
    99: "storm",
}


class OpenMeteoProvider(WeatherProvider):
    """Key-free provider — sensible default for development."""

    name = "openmeteo"
    BASE = "https://api.open-meteo.com/v1/forecast"

    async def forecast(self, latitude: float, longitude: float) -> WeatherReport:
        params: dict[str, str | int | float] = {
            "latitude": latitude,
            "longitude": longitude,
            "current": (
                "temperature_2m,relative_humidity_2m,apparent_temperature,"
                "precipitation,weather_code,wind_speed_10m,wind_gusts_10m"
            ),
            "hourly": (
                "temperature_2m,apparent_temperature,precipitation_probability,"
                "precipitation,weather_code,wind_speed_10m,wind_gusts_10m,"
                "relative_humidity_2m,uv_index"
            ),
            "forecast_days": 3,
            "timezone": "UTC",
        }
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(self.BASE, params=params)
            if resp.status_code != 200:
                raise upstream_unavailable("weather")
            data = resp.json()
        except httpx.HTTPError:
            raise upstream_unavailable("weather") from None

        import datetime as dt

        current_raw = data["current"]
        current_ts = int(dt.datetime.fromisoformat(current_raw["time"]).replace(tzinfo=dt.UTC).timestamp())
        current = HourlyPoint(
            timestamp=current_ts,
            temperature_c=float(current_raw["temperature_2m"]),
            feels_like_c=float(current_raw["apparent_temperature"]),
            precip_probability=0.0,
            precip_mm=float(current_raw.get("precipitation", 0.0)),
            wind_kmh=float(current_raw.get("wind_speed_10m", 0.0)),
            gust_kmh=float(current_raw.get("wind_gusts_10m", 0.0)),
            humidity_pct=float(current_raw.get("relative_humidity_2m", 50)),
            uv_index=None,
            condition=_WMO_CONDITION_MAP.get(int(current_raw.get("weather_code", 0)), "clouds"),
        )
        hourly_raw = data.get("hourly", {})
        hourly: list[HourlyPoint] = []
        times = hourly_raw.get("time", [])
        for i, t in enumerate(times):
            ts = int(dt.datetime.fromisoformat(t).replace(tzinfo=dt.UTC).timestamp())
            hourly.append(
                HourlyPoint(
                    timestamp=ts,
                    temperature_c=float(hourly_raw["temperature_2m"][i]),
                    feels_like_c=float(hourly_raw["apparent_temperature"][i]),
                    precip_probability=float(hourly_raw["precipitation_probability"][i] or 0) / 100.0,
                    precip_mm=float(hourly_raw["precipitation"][i] or 0.0),
                    wind_kmh=float(hourly_raw["wind_speed_10m"][i] or 0.0),
                    gust_kmh=float(hourly_raw["wind_gusts_10m"][i] or 0.0),
                    humidity_pct=float(hourly_raw["relative_humidity_2m"][i] or 50),
                    uv_index=(hourly_raw.get("uv_index") or [None] * len(times))[i],
                    condition=_WMO_CONDITION_MAP.get(int(hourly_raw["weather_code"][i]), "clouds"),
                )
            )
        return WeatherReport(
            latitude=latitude, longitude=longitude, current=current, hourly=hourly, provider=self.name
        )


_PROVIDER_REGISTRY: dict[str, type[WeatherProvider]] = {
    "openweathermap": OpenWeatherMapProvider,
    "openmeteo": OpenMeteoProvider,
}


def get_weather_provider() -> WeatherProvider:
    settings = get_settings()
    cls = _PROVIDER_REGISTRY.get(settings.weather_provider)
    if cls is None:
        log.warning("weather.unknown_provider", provider=settings.weather_provider)
        cls = OpenMeteoProvider
    return cls()
