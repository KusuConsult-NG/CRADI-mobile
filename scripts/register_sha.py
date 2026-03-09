#!/usr/bin/env python3
"""
register_sha.py — Extract SHA-256 from the CRADI release keystore and register
it with Firebase if not already present.

Usage:
    python3 scripts/register_sha.py

Requirements:
    pip install pyjks cryptography firebase-admin

The script reads key.properties from android/key.properties (same values used
by Gradle) so no credentials need to be hard-coded here.
"""

import os
import sys
import json
import hashlib
import subprocess
from pathlib import Path

# ─────────────────────────── Config ───────────────────────────────────────────

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
KEY_PROPS = PROJECT_DIR / "android" / "key.properties"

FIREBASE_APP_ID = "1:689251502200:android:3c102d339da6c4437e458d"  # climate_app (android)

# ─────────────────────────── Read key.properties ──────────────────────────────

def read_key_properties():
    props = {}
    with open(KEY_PROPS) as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                props[k.strip()] = v.strip()
    return props


# ─────────────────────────── SHA extraction ───────────────────────────────────

def extract_sha256_via_keytool(store_file: str, store_pass: str, alias: str) -> str:
    """Run keytool in a subprocess with a hard pipe to avoid terminal wait."""
    cmd = [
        "keytool", "-list",
        "-keystore", store_file,
        "-alias", alias,
        "-storepass", store_pass,
        "-noprompt", "-v",
    ]
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=15,
            stdin=subprocess.DEVNULL,  # Prevents any interactive prompt
        )
        output = result.stdout + result.stderr
        for line in output.splitlines():
            if "SHA256:" in line:
                # e.g. "SHA256: 4A:CF:07:96:..."
                raw = line.split("SHA256:")[-1].strip()
                # Normalise: remove colons, lowercase
                return raw.replace(":", "").lower()
        print("❌ keytool output:\n", output)
        return ""
    except subprocess.TimeoutExpired:
        print("❌ keytool timed out. Trying fallback method...")
        return ""
    except FileNotFoundError:
        print("❌ keytool not found. Is the JDK in your PATH?")
        return ""


def extract_sha256_via_pyjks(store_file: str, store_pass: str, alias: str) -> str:
    """Fallback: use pyjks to read JKS and extract the cert SHA-256."""
    try:
        import jks  # pyjks
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
    except ImportError:
        print("Installing pyjks and cryptography...")
        subprocess.run([sys.executable, "-m", "pip", "install", "pyjks", "cryptography", "-q"], check=True)
        import jks
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes

    ks = jks.KeyStore.load(store_file, store_pass)
    entry = ks.private_keys.get(alias) or ks.certs.get(alias)
    if entry is None:
        raise ValueError(f"Alias '{alias}' not found in keystore. Available: {list(ks.private_keys.keys())}")

    # entry.cert_chain[0][1] is the raw DER bytes of the leaf certificate
    cert_der = entry.cert_chain[0][1]
    digest = hashlib.sha256(cert_der).hexdigest()
    return digest


def get_sha256(props: dict) -> str:
    store_file = props["storeFile"]
    store_pass = props["storePassword"]
    alias = props["keyAlias"]

    if not Path(store_file).exists():
        print(f"❌ Keystore not found at: {store_file}")
        sys.exit(1)

    print(f"🔍 Reading keystore: {store_file} (alias={alias})")

    # Try keytool first (standard, no extra deps)
    sha = extract_sha256_via_keytool(store_file, store_pass, alias)
    if sha:
        return sha

    # Fallback to pyjks (pure Python)
    print("⚙️  Falling back to pyjks...")
    return extract_sha256_via_pyjks(store_file, store_pass, alias)


# ─────────────────────────── Firebase registration ───────────────────────────

def get_registered_shas() -> list[str]:
    """Query currently registered SHA hashes via Firebase CLI."""
    result = subprocess.run(
        ["firebase", "apps:sdkconfig", "android", FIREBASE_APP_ID, "--json"],
        capture_output=True, text=True, cwd=str(PROJECT_DIR),
    )
    # We also query sha list separately
    result2 = subprocess.run(
        ["firebase", "apps:android:sha:list", FIREBASE_APP_ID, "--json"],
        capture_output=True, text=True, cwd=str(PROJECT_DIR),
    )
    try:
        data = json.loads(result2.stdout)
        shas = [s["shaHash"].replace(":", "").lower() for s in data.get("result", [])]
        return shas
    except Exception:
        return []


def register_sha_via_cli(sha256: str) -> bool:
    """Register a SHA-256 fingerprint with Firebase via CLI."""
    # Firebase CLI format: colon-separated uppercase pairs
    colon_sha = ":".join(sha256[i:i+2].upper() for i in range(0, len(sha256), 2))
    print(f"📡 Registering: {colon_sha}")
    result = subprocess.run(
        ["firebase", "apps:android:sha:add", FIREBASE_APP_ID, colon_sha],
        capture_output=True, text=True, cwd=str(PROJECT_DIR),
    )
    if result.returncode == 0:
        print("✅ SHA-256 registered successfully.")
        return True
    else:
        print("❌ Firebase CLI error:")
        print(result.stderr or result.stdout)
        return False


# ─────────────────────────── MCP fallback ─────────────────────────────────────

def register_sha_via_mcp_hint(sha256: str):
    """Print the curl command to register manually if CLI is unavailable."""
    colon_sha = ":".join(sha256[i:i+2].upper() for i in range(0, len(sha256), 2))
    print()
    print("ℹ️  Firebase CLI not available. Register manually with:")
    print(f"  firebase apps:android:sha:add {FIREBASE_APP_ID} {colon_sha}")
    print()
    print("Or via Firebase Console → Project Settings → Your App → SHA certificate fingerprints")


# ─────────────────────────── Main ─────────────────────────────────────────────

def main():
    print("=" * 55)
    print("  CRADI Mobile — SHA-256 Firebase Registration Script")
    print("=" * 55)

    props = read_key_properties()
    sha256 = get_sha256(props)

    if not sha256:
        print("❌ Could not extract SHA-256 from keystore.")
        sys.exit(1)

    # Format for display
    colon_sha = ":".join(sha256[i:i+2].upper() for i in range(0, len(sha256), 2))
    print(f"\n🔑 SHA-256: {colon_sha}\n")

    # Check if already registered (via CLI)
    registered = get_registered_shas()
    if sha256 in registered:
        print("✅ This SHA-256 is already registered with Firebase. No action needed.")
        print()
        print("If App Check is still rejecting builds, the issue is likely:")
        print("  1. App Check enforcement mode — set to 'Monitoring' temporarily in Firebase Console")
        print("  2. Play Integrity not passing on the test device (rooted/emulator)")
        return

    # Attempt registration
    print("📌 SHA-256 not yet registered. Registering now...")
    success = register_sha_via_cli(sha256)
    if not success:
        register_sha_via_mcp_hint(sha256)

    print()
    print("🏁 Done. Re-build and install the release APK to verify App Check passes.")


if __name__ == "__main__":
    main()
