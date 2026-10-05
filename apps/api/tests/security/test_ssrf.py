import pytest

from app.core.errors import ApiError
from app.core.outbound import validate_public_url


@pytest.mark.parametrize(
    "url",
    [
        "http://example.com",
        "file:///etc/passwd",
        "ftp://example.com/a",
        "https://127.0.0.1",
        "https://localhost",
        "https://169.254.169.254/latest/meta-data",
        "https://10.0.0.1",
        "https://172.16.1.1",
        "https://192.168.1.1",
        "https://[::1]",
        "https://[::ffff:127.0.0.1]",
        "https://metadata.google.internal",
        "https://user:password@example.com",
        "https://example.com:9000",
    ],
)
def test_non_public_destinations_rejected(url):
    with pytest.raises(ApiError):
        validate_public_url(url, resolve=False)


def test_dns_resolution_checked(monkeypatch):
    monkeypatch.setattr("socket.getaddrinfo", lambda *_: [(2, 1, 6, "", ("127.0.0.1", 443))])
    with pytest.raises(ApiError):
        validate_public_url("https://provider.example")
