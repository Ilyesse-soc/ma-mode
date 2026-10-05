"""Public outbound HTTPS only. No redirects or arbitrary provider downloads."""

import asyncio
import ipaddress
import socket
import ssl
from urllib.parse import urlsplit

import httpcore
import httpx

from app.core.errors import bad_request, upstream_unavailable


def validate_public_url(url: str, resolve=True) -> str:
    try:
        parts = urlsplit(url)
        if (
            parts.scheme != "https"
            or not parts.hostname
            or parts.username
            or parts.password
            or parts.fragment
        ):
            raise ValueError
        if parts.port not in {None, 443}:
            raise ValueError
        host = parts.hostname.rstrip(".").lower()
        if host in {"localhost", "metadata.google.internal"} or host.endswith(
            (".localhost", ".local", ".internal")
        ):
            raise ValueError
        try:
            addresses = [ipaddress.ip_address(host)]
        except ValueError:
            addresses = (
                [ipaddress.ip_address(i[4][0]) for i in socket.getaddrinfo(host, 443)] if resolve else []
            )
        if any(
            not address.is_global
            or (address.version == 6 and address.ipv4_mapped and not address.ipv4_mapped.is_global)
            for address in addresses
        ):
            raise ValueError
    except (ValueError, OSError):
        raise bad_request("unsafe_url", "Only public HTTPS provider URLs are allowed") from None
    return url


class PublicNetworkBackend(httpcore.AsyncNetworkBackend):
    """Validate the actual DNS result then connect to that IP, retaining TLS SNI."""

    async def connect_tcp(self, host, port, timeout=None, local_address=None, socket_options=None):  # noqa: ASYNC109
        # httpcore's interface requires this parameter; its backend enforces the deadline.
        records = await asyncio.get_running_loop().getaddrinfo(host, port, type=socket.SOCK_STREAM)
        addresses = [ipaddress.ip_address(record[4][0]) for record in records]
        if not addresses or any(not address.is_global for address in addresses):
            raise httpcore.ConnectError("Non-public destination")
        return await httpcore.AnyIOBackend().connect_tcp(
            str(addresses[0]),
            port,
            timeout=timeout,
            local_address=local_address,
            socket_options=socket_options,
        )

    async def connect_unix_socket(self, *args, **kwargs):
        raise httpcore.ConnectError("Unix sockets prohibited")

    async def sleep(self, seconds):
        await asyncio.sleep(seconds)


class PublicTransport(httpx.AsyncHTTPTransport):
    def __init__(self):
        super().__init__(trust_env=False)
        self._pool = httpcore.AsyncConnectionPool(
            ssl_context=ssl.create_default_context(), network_backend=PublicNetworkBackend(), retries=0
        )


async def bounded_json_request(
    method: str,
    url: str,
    *,
    request_timeout=15,
    allowed_statuses=frozenset({200}),
    return_metadata=False,
    **kwargs,
):
    from starlette.concurrency import run_in_threadpool

    await run_in_threadpool(validate_public_url, url)
    try:
        async with (
            httpx.AsyncClient(
                timeout=request_timeout, transport=PublicTransport(), follow_redirects=False, trust_env=False
            ) as client,
            client.stream(method, url, **kwargs) as response,
        ):
            if response.status_code not in allowed_statuses:
                from app.core.logging import get_logger

                get_logger("outbound").warning("provider.http_error", status=response.status_code)
                raise upstream_unavailable("provider")
            if response.status_code in {404, 429} and return_metadata:
                return {}, dict(response.headers), response.status_code
            body = bytearray()
            async for chunk in response.aiter_bytes():
                body.extend(chunk)
                if len(body) > 256 * 1024:
                    raise upstream_unavailable("provider")
            import json

            data = json.loads(body)
            return (data, dict(response.headers), response.status_code) if return_metadata else data
    except (httpx.HTTPError, ValueError, RecursionError) as exc:
        from app.core.logging import get_logger

        get_logger("outbound").warning("provider.request_failed", error_type=type(exc).__name__)
        raise upstream_unavailable("provider") from None
