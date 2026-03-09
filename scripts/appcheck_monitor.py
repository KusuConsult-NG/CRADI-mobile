#!/usr/bin/env python3
"""
appcheck_monitor.py — Switch Firebase App Check to MONITORING mode for the
CRADI Android app so production logins work while the Play Integrity issue
is investigated.

What this does:
  • Uses the Firebase App Check Management REST API (v1beta)
  • Sets enforcement mode to UNENFORCED (monitoring) for Auth + Firestore
  • App Check tokens are still collected/logged, just not enforced

Usage:
  # Switch App Check to monitoring (fixes production login errors):
  python3 scripts/appcheck_monitor.py

  # Re-enable strict enforcement when Play Integrity is fixed:
  python3 scripts/appcheck_monitor.py --enforce

Requirements:
  pip install requests
  gcloud auth login   (must have Firebase Admin / Editor role)

Note on authentication:
  The Firebase App Check API requires the cloud-platform OAuth scope, which means
  you need to re-login specifically for this if you haven't already:
    gcloud auth login --update-adc
"""

import sys
import argparse
import subprocess
import json

# ─────────────────────────── Config ───────────────────────────────────────────

PROJECT_ID = "ewer-8f788"
ANDROID_APP_ID = "1:689251502200:android:3c102d339da6c4437e458d"

# Services protected by App Check — set each one's enforcement mode
PROTECTED_SERVICES = [
    "identitytoolkit.googleapis.com",   # Firebase Auth
    "firestore.googleapis.com",          # Firestore
    "firebasestorage.googleapis.com",    # Storage
]

API_V1 = "https://firebaseappcheck.googleapis.com/v1"

# ─────────────────────────── Auth ─────────────────────────────────────────────

def get_access_token() -> str:
    """Get an OAuth2 access token with the cloud-platform scope via gcloud."""
    try:
        # Use --scopes to ensure we have cloud-platform, not just default ADC
        result = subprocess.run(
            ["gcloud", "auth", "print-access-token",
             "--scopes=https://www.googleapis.com/auth/cloud-platform"],
            capture_output=True, text=True, timeout=15, stdin=subprocess.DEVNULL,
        )
        token = result.stdout.strip()
        if not token:
            stderr = result.stderr.strip()
            print(f"❌ No token returned from gcloud. Error: {stderr}")
            print()
            print("Fix: run  gcloud auth login --update-adc")
            sys.exit(1)
        return token
    except FileNotFoundError:
        print("❌ gcloud not found. Install: https://cloud.google.com/sdk/docs/install")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("❌ gcloud timed out. Try: gcloud auth login")
        sys.exit(1)


# ─────────────────────────── API ──────────────────────────────────────────────

def _headers(token: str) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "X-Goog-User-Project": PROJECT_ID,
    }


def get_service(token: str, service: str):  # -> Optional[dict]
    """Fetch the current enforcement config for a protected service."""
    try:
        import requests
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "requests", "-q"], check=True)
        import requests

    url = f"{API_V1}/projects/{PROJECT_ID}/services/{service}"
    r = requests.get(url, headers=_headers(token), timeout=10)
    if r.status_code == 200:
        return r.json()
    return None


def set_service_enforcement(token: str, service: str, enforce: bool) -> bool:
    """PATCH the enforcement mode for one service."""
    try:
        import requests
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "requests", "-q"], check=True)
        import requests

    mode = "ENFORCED" if enforce else "UNENFORCED"
    url = f"{API_V1}/projects/{PROJECT_ID}/services/{service}?updateMask=enforcementMode"
    body = {
        "name": f"projects/{PROJECT_ID}/services/{service}",
        "enforcementMode": mode,
    }
    r = requests.patch(url, headers=_headers(token), json=body, timeout=10)
    if r.status_code == 200:
        cfg = r.json()
        actual_mode = cfg.get("enforcementMode", mode)
        print(f"  ✅ {service}: {actual_mode}")
        return True
    else:
        try:
            err = r.json().get("error", {})
            msg = err.get("message", r.text)
        except Exception:
            msg = r.text
        print(f"  ❌ {service}: HTTP {r.status_code} — {msg[:200]}")
        return False


# ─────────────────────────── Main ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Toggle Firebase App Check enforcement mode for CRADI Mobile."
    )
    parser.add_argument(
        "--enforce",
        action="store_true",
        help="Re-enable strict enforcement (default: switch to monitoring/UNENFORCED mode)",
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Just print current enforcement status and exit",
    )
    args = parser.parse_args()

    mode_label = "ENFORCED (strict)" if args.enforce else "UNENFORCED (monitoring)"
    print("=" * 58)
    print(f"  CRADI Mobile — App Check Mode")
    print("=" * 58)
    print(f"  Project : {PROJECT_ID}")
    print(f"  Target  : {mode_label if not args.status else 'Status check'}")
    print()

    token = get_access_token()
    print("🔑 Access token obtained\n")

    if args.status:
        print("Current enforcement modes:")
        for svc in PROTECTED_SERVICES:
            cfg = get_service(token, svc)
            if cfg:
                print(f"  {svc}: {cfg.get('enforcementMode', 'UNKNOWN')}")
            else:
                print(f"  {svc}: (could not fetch)")
        return

    if args.enforce:
        confirm = input(
            "⚠️  Re-enabling enforcement blocks devices that fail Play Integrity.\n"
            "   Continue? [y/N] "
        ).strip().lower()
        if confirm != "y":
            print("Aborted.")
            return

    print(f"Setting enforcement to {mode_label} for all protected services...\n")
    all_ok = True
    for svc in PROTECTED_SERVICES:
        ok = set_service_enforcement(token, svc, enforce=args.enforce)
        if not ok:
            all_ok = False

    print()
    if not args.enforce:
        print("🔍 App Check is now in MONITORING mode.")
        print("   • Production logins will work immediately on all devices")
        print("   • Token failures are still logged — check Firebase Console → App Check dashboard")
        print("   • Re-enable strict mode once Play Integrity passes cleanly:")
        print("       python3 scripts/appcheck_monitor.py --enforce")
    else:
        print("🔒 App Check enforcement is ACTIVE.")
        print("   Only Play Integrity-attested devices can log in.")

    if not all_ok:
        print()
        print("⚠️  Some services could not be updated. Do it manually:")
        print("   Firebase Console → App Check → your Android app → Overflow (⋮) → Manage enforcement")
        sys.exit(1)


if __name__ == "__main__":
    main()
