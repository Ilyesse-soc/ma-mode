"""Build archived official MinIO source for LOCAL testing; no third-party images."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
from urllib.request import Request, urlopen
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / ".tmp" / "minio-build"
DEST.mkdir(parents=True, exist_ok=True)


def read(url):
    with urlopen(Request(url, headers={"User-Agent": "Dressly-local-build"}), timeout=60) as response:
        data = response.read(256 * 1024 * 1024 + 1)
    if len(data) > 256 * 1024 * 1024:
        raise ValueError("Oversized download")
    return data


def unpack(data, destination):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for member in archive.infolist():
            target = (destination / member.filename).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError("Unsafe archive path")
        archive.extractall(destination)


if __name__ == "__main__":
    versions = json.loads(read("https://go.dev/dl/?mode=json"))
    chosen = next(f for v in versions if v["stable"] for f in v["files"] if f["os"] == "windows" and f["arch"] == "amd64" and f["kind"] == "archive")
    go_archive = read("https://go.dev/dl/" + chosen["filename"])
    if hashlib.sha256(go_archive).hexdigest() != chosen["sha256"]:
        raise ValueError("Go checksum mismatch")
    unpack(go_archive, DEST)
    tag = "RELEASE.2025-10-15T17-29-55Z"
    release = json.loads(read(f"https://api.github.com/repos/minio/minio/git/ref/tags/{tag}"))
    commit = release["object"]["sha"]
    source = read(f"https://codeload.github.com/minio/minio/zip/{commit}")
    unpack(source, DEST)
    (DEST / "receipt.json").write_text(json.dumps({"go": chosen, "minio_tag": tag, "minio_commit": commit, "source_sha256": hashlib.sha256(source).hexdigest()}, indent=2))
    (DEST / "source-directory.txt").write_text(str(DEST / f"minio-{commit}"))
    print("Official Go archive SHA256 verified; pinned official MinIO source extracted.")
    environment = os.environ.copy()
    environment.update({"GOCACHE": str(ROOT / ".tmp/go-cache"), "GOMODCACHE": str(ROOT / ".tmp/go-modules"), "CGO_ENABLED": "0", "GOMAXPROCS": "2"})
    binary = ROOT / ".tmp/security-tools/minio.exe"
    binary.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(DEST / "go/bin/go.exe"), "build", "-p", "2", "-o", str(binary), "."], cwd=DEST / f"minio-{commit}", env=environment, check=True)
    print("Local-only MinIO binary built from the pinned official source.")
