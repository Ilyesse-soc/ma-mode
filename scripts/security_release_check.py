"""Fail-closed production gate. No credentials are written to diagnostics."""
import re
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps" / "api"))


def main():
    from pydantic import ValidationError
    from app.core.config import Settings
    failures = []
    signing_path = os.environ.get("ANDROID_KEYSTORE_PATH", "")
    if not signing_path or not Path(signing_path).is_file() or any(
        not os.environ.get(name) for name in ("ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")
    ):
        failures.append("Real Android release signing must be configured")
    try:
        settings = Settings()
        if not settings.is_production:
            failures.append("ENVIRONMENT must be production")
        if settings.debug:
            failures.append("APP_DEBUG must be false")
        if not settings.security_alert_email:
            failures.append("Security alert recipient must be configured")
    except (ValidationError, ValueError):
        failures.append("Production settings validation failed; check required security configuration")
    pattern = re.compile(r"\[(?:LEGAL_|DPO_|HOSTING_PROVIDER|APP_STORE_NAME)")
    legal = ROOT / "apps" / "mobile" / "assets" / "legal"
    for document in legal.glob("*.md"):
        if pattern.search(document.read_text(encoding="utf8")):
            failures.append(f"Unresolved legal configuration: {document.name}")
    scanner = shutil.which("gitleaks")
    if scanner is None:
        local = ROOT / ".tmp" / "security-tools" / "gitleaks.exe"
        scanner = str(local) if local.exists() else None
    if scanner is None:
        failures.append("A real Gitleaks binary is required for the release gate")
    else:
        result = subprocess.run([scanner, "dir", str(ROOT), "--config", str(ROOT / ".gitleaks.toml"), "--redact=100", "--no-banner", "--exit-code", "1"], capture_output=True, check=False)
        if result.returncode:
            failures.append("Secret scan failed")
    for failure in failures:
        print("BLOCKED: " + failure)
    if failures:
        return 1
    print("Production static gate passed. Infrastructure probes and legal validation remain separate requirements.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
