"""Generate RS256 keypair for JWT signing (dev bootstrap)."""

from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
private = key.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
).decode()
public = (
    key.public_key()
    .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    .decode()
)

destination = Path(".env.keys")
with destination.open("x", encoding="utf8") as file:
    file.write(f'JWT_PRIVATE_KEY_PEM="{private.replace(chr(10), chr(92) + "n")}"\n')
    file.write(f'JWT_PUBLIC_KEY_PEM="{public.replace(chr(10), chr(92) + "n")}"\n')
print("Created .env.keys locally. Move its values to your secret manager; do not commit this file.")
