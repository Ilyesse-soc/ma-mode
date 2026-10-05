"""Fail before publication if runtime secret files or private keys are tracked.

Only paths and rule names are reported; never print matching secret values.
Gitleaks additionally scans entropy/provider tokens and complete Git history.
"""
from pathlib import Path
import re
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    failures = []
    for filename in filter(None, files):
        path = Path(filename)
        if (path.name == ".env" or path.name.startswith(".env.")) and path.name != ".env.example":
            failures.append((filename, "runtime environment file"))
        if path.suffix.lower() in {".pem", ".key", ".p12", ".pfx", ".jks", ".keystore"}:
            failures.append((filename, "credential/key file"))
        if any(part in {"secrets", "credentials", ".local", ".tmp"} for part in path.parts):
            failures.append((filename, "runtime credential directory"))
        # Inspect the exact staged blob, including files changed after staging.
        raw = subprocess.check_output(["git", "show", ":" + filename], cwd=root)
        if b"\x00" in raw[:4096]:
            continue
        content = raw.decode("utf8", errors="replace")
        if re.search(r"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----\s+[A-Za-z0-9+/]{40,}", content):
            failures.append((filename, "embedded private key"))
        # .env.example may contain defaults, but credentials remain empty.
        if path.name == ".env.example":
            for line in content.splitlines():
                name, separator, value = line.partition("=")
                if separator and re.search(r"(?:KEY|SECRET|PASSWORD|TOKEN|DSN|DATABASE_URL|RATE_LIMIT_STORAGE_URI|KEYSTORE_B64)$", name):
                    if value.strip().strip("\"'"):
                        failures.append((filename, "nonempty secret example: " + name))
    for path, rule in failures:
        print(f"REJECTED {path}: {rule}")
    if failures:
        raise SystemExit(1)
    print(f"Tracked-file guard passed: {len(list(filter(None, files)))} files; no runtime .env or private keys.")


if __name__ == "__main__":
    main()
