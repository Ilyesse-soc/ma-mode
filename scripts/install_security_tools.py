"""Download official Windows scanners and verify their published SHA256 receipts."""
import hashlib
import io
import json
import platform
import tarfile
from pathlib import Path
from urllib.request import Request, urlopen
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / ".tmp" / "security-tools"
DEST.mkdir(parents=True, exist_ok=True)


def read(url):
    request = Request(url, headers={"User-Agent": "Dressly-local-security-check"})
    with urlopen(request, timeout=45) as response:
        data = response.read(150 * 1024 * 1024 + 1)
    if len(data) > 150 * 1024 * 1024:
        raise ValueError("Download exceeds tool size policy")
    return data


def install(repo, version, asset, executable):
    base = f"https://github.com/{repo}/releases/download/v{version}/"
    sums = read(base + f"{repo.split('/')[-1]}_{version}_checksums.txt").decode()
    expected = next(line.split()[0] for line in sums.splitlines() if line.split()[-1].lstrip('*') == asset)
    archive = read(base + asset)
    actual = hashlib.sha256(archive).hexdigest()
    if actual != expected:
        raise ValueError("Tool archive checksum mismatch")
    if asset.endswith('.zip'):
        with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
            name = next(name for name in bundle.namelist() if name.split('/')[-1] == executable)
            binary = bundle.read(name)
    else:
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as bundle:
            name = next(name for name in bundle.getnames() if name.split('/')[-1] == executable)
            binary = bundle.extractfile(name).read()
    (DEST / executable).write_bytes(binary)
    (DEST / executable).chmod(0o755)
    receipt = {"repository": repo, "version": version, "asset": asset, "sha256": actual}
    (DEST / f"{executable}.receipt.json").write_text(json.dumps(receipt, indent=2))
    print(f"Installed {executable} {version}; published SHA256 verified")


if __name__ == "__main__":
    tool_specs = [
        ("gitleaks/gitleaks", "8.24.3", "gitleaks_8.24.3_windows_x64.zip", "gitleaks.exe"),
        ("aquasecurity/trivy", "0.69.3", "trivy_0.69.3_windows-64bit.zip", "trivy.exe"),
    ] if platform.system() == 'Windows' else [
        ("gitleaks/gitleaks", "8.24.3", "gitleaks_8.24.3_linux_x64.tar.gz", "gitleaks"),
        ("aquasecurity/trivy", "0.69.3", "trivy_0.69.3_Linux-64bit.tar.gz", "trivy"),
    ]
    for args in tool_specs:
        try:
            install(*args)
        except Exception as exc:
            print(f"Could not install {args[-1]}: {type(exc).__name__}")
            raise SystemExit(1) from None
