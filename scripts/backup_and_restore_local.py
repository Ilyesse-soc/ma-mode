"""Actual encrypted local backup and isolated restoration; no production claim."""
import hashlib
import json
from pathlib import Path
import secrets
import subprocess
import uuid

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".local"
CONTAINER = "dressly-local-postgres-1"


def docker(*args):
    result = subprocess.run(["docker", *args], capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError("Local backup Docker operation failed")
    return result.stdout.decode().strip()


if __name__ == "__main__":
    identifier = uuid.uuid4().hex
    restore_db = "dressly_restore_check_" + identifier
    dump_name = "dressly-check-" + identifier + ".dump"
    dump_path = LOCAL / dump_name
    key_path = LOCAL / "backup-test-key.bin"
    key = key_path.read_bytes() if key_path.exists() else AESGCM.generate_key(bit_length=256)
    key_path.write_bytes(key)
    docker("exec", CONTAINER, "pg_dump", "-U", "dressly_admin", "-d", "dressly", "-Fc", "-f", "/tmp/" + dump_name)
    docker("cp", CONTAINER + ":/tmp/" + dump_name, str(dump_path))
    nonce = secrets.token_bytes(12)
    encrypted = b"DRESSLYBK1" + nonce + AESGCM(key).encrypt(nonce, dump_path.read_bytes(), b"dressly-local-backup")
    archive = LOCAL / (dump_name + ".aes256gcm")
    archive.write_bytes(encrypted)
    # Restore from decrypted ciphertext, rather than accidentally reusing the original dump.
    dump_path.write_bytes(AESGCM(key).decrypt(encrypted[10:22], encrypted[22:], b"dressly-local-backup"))
    docker("cp", str(dump_path), CONTAINER + ":/tmp/restore-" + dump_name)
    docker("exec", CONTAINER, "createdb", "-U", "dressly_admin", restore_db)
    try:
        docker("exec", CONTAINER, "pg_restore", "-U", "dressly_admin", "-d", restore_db, "--exit-on-error", "/tmp/restore-" + dump_name)
        category_count = int(docker("exec", CONTAINER, "psql", "-U", "dressly_admin", "-d", restore_db, "-At", "-c", "SELECT count(*) FROM garment_categories"))
        revision = docker("exec", CONTAINER, "psql", "-U", "dressly_admin", "-d", restore_db, "-At", "-c", "SELECT version_num FROM alembic_version")
        assert category_count == 39 and revision == "verify_expiry_20261005"
        receipt = {"scope": "local PostgreSQL only", "algorithm": "AES-256-GCM", "restored_from_encrypted_archive": True, "catalog_rows": category_count, "schema_revision": revision, "sha256_encrypted_archive": hashlib.sha256(encrypted).hexdigest(), "production_backup_verified": False}
        (ROOT / "docs" / "BACKUP_RESTORE_CHECK.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print("Actual encrypted backup restored into an isolated database; catalog and migration head verified.")
    finally:
        # Only remove the isolated resources created by this invocation.
        if not restore_db.startswith("dressly_restore_check_") or len(identifier) != 32:
            raise ValueError("Unexpected restoration target")
        docker("exec", CONTAINER, "dropdb", "-U", "dressly_admin", restore_db)
        docker("exec", CONTAINER, "rm", "/tmp/" + dump_name, "/tmp/restore-" + dump_name)
        if not dump_path.resolve().is_relative_to(LOCAL.resolve()):
            raise ValueError("Unexpected local backup path")
        dump_path.unlink()
