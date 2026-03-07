#!/usr/bin/env bash
# =============================================================================
# CRADI Mobile — App Check + Firestore TTL Setup Script (v4)
#
# Strategy:
#   - Detects the Firebase-logged-in account ("the right account")
#   - Checks if that account is active in gcloud; if not, adds it via
#     `gcloud auth login --account=<firebase_account>` (opens browser once)
#   - Uses gcloud auth print-access-token with that account for all REST calls
# =============================================================================
set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

PROJECT_ID="ewer-8f788"
PROJECT_NUMBER="689251502200"
ANDROID_APP_ID="1:${PROJECT_NUMBER}:android:3c102d339da6c4437e458d"
IOS_APP_ID="1:${PROJECT_NUMBER}:ios:844c6e09186ae4e47e458d"

echo ""
echo "========================================================"
echo "  CRADI Mobile — App Check + Firestore TTL Setup"
echo "  Project: $PROJECT_ID"
echo "========================================================"
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────────────
command -v firebase >/dev/null 2>&1 || error "firebase CLI not found. Run: npm i -g firebase-tools && firebase login"
command -v gcloud   >/dev/null 2>&1 || error "gcloud not found. Install: https://cloud.google.com/sdk/docs/install"
command -v curl     >/dev/null 2>&1 || error "curl not found."
success "Firebase CLI v$(firebase --version 2>/dev/null | head -1)"
success "gcloud $(gcloud --version 2>&1 | head -1)"

# ── Identify the Firebase project owner account ───────────────────────────────
info "Detecting Firebase login account..."
FB_ACCOUNT=$(firebase login:list 2>/dev/null | grep -oE '[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}' | head -1)
if [[ -z "$FB_ACCOUNT" ]]; then
  info "Not logged in to Firebase — launching browser..."
  firebase login
  FB_ACCOUNT=$(firebase login:list 2>/dev/null | grep -oE '[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}' | head -1)
fi
[[ -z "$FB_ACCOUNT" ]] && error "Could not determine Firebase account."
success "Firebase account: $FB_ACCOUNT"

# ── Ensure this account is also in gcloud ────────────────────────────────────
info "Checking gcloud account list..."
GCLOUD_ACCOUNTS=$(gcloud auth list --format='value(account)' 2>/dev/null)

if echo "$GCLOUD_ACCOUNTS" | grep -qi "^${FB_ACCOUNT}$"; then
  success "Account already in gcloud: $FB_ACCOUNT"
  # Make it active
  gcloud config set account "$FB_ACCOUNT" --quiet
else
  warn "Firebase account ($FB_ACCOUNT) not found in gcloud."
  info "Opening browser to add this account to gcloud (one-time)..."
  gcloud auth login "$FB_ACCOUNT" --update-adc --quiet
fi

# Set the project
gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null || true

# Get access token using the Firebase account
info "Getting access token for $FB_ACCOUNT..."
ACCESS_TOKEN=$(gcloud auth print-access-token --account="$FB_ACCOUNT" 2>/dev/null || echo "")
if [[ -z "$ACCESS_TOKEN" ]]; then
  info "Refreshing credentials for $FB_ACCOUNT..."
  gcloud auth login "$FB_ACCOUNT" --update-adc --quiet
  ACCESS_TOKEN=$(gcloud auth print-access-token --account="$FB_ACCOUNT" 2>/dev/null || echo "")
fi
[[ -z "$ACCESS_TOKEN" ]] && error "Still no access token. Try: gcloud auth login $FB_ACCOUNT"
success "Access token ready (${#ACCESS_TOKEN} chars) for $FB_ACCOUNT"

# ── Helper ─────────────────────────────────────────────────────────────────────
_patch() {
  local label="$1" url="$2" body="$3"
  info "$label..."
  local resp http_code msg
  resp=$(curl -s -w "\n%{http_code}" -X PATCH "$url" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    -H "Content-Type: application/json" \
    -d "$body" || echo -e "\n000")
  http_code=$(echo "$resp" | tail -1)
  msg=$(echo "$resp" | sed '$d' | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('message','ok')[:200])" \
    2>/dev/null || echo "$(echo "$resp" | sed '$d' | head -c 200)")
  if [[ "$http_code" == "200" ]]; then
    success "$label ✓"
  else
    warn "$label — HTTP $http_code: $msg"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Enable the Firebase App Check GCP API (required before REST calls work)
# ─────────────────────────────────────────────────────────────────────────────
info "Enabling Firebase App Check API on project $PROJECT_ID..."
gcloud services enable firebaseappcheck.googleapis.com \
  --project="$PROJECT_ID" \
  --account="$FB_ACCOUNT" \
  --quiet 2>/dev/null && \
  success "firebase App Check API enabled ✓" || \
  warn "Could not enable App Check API automatically — may already be enabled or missing billing."

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — Firebase App Check
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────"
echo "  PART 1 · Firebase App Check"
echo "────────────────────────────────────────────────────────"

BASE="https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_ID}"

_patch "Play Integrity (Android)" \
  "${BASE}/apps/${ANDROID_APP_ID}/playIntegrityConfig?updateMask=tokenTtl" \
  '{"tokenTtl":"3600s"}'

_patch "DeviceCheck (iOS)" \
  "${BASE}/apps/${IOS_APP_ID}/deviceCheckConfig?updateMask=tokenTtl" \
  '{"tokenTtl":"3600s"}'

_patch "Enforce App Check on Firestore" \
  "${BASE}/services/firestore.googleapis.com?updateMask=enforcementMode" \
  '{"enforcementMode":"ENFORCED"}'


# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Firestore TTL Policy
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────"
echo "  PART 2 · Firestore TTL Policy"
echo "────────────────────────────────────────────────────────"

_patch "TTL on otp_verifications.expiresAt" \
  "https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/collectionGroups/otp_verifications/fields/expiresAt?updateMask=ttlConfig" \
  '{"ttlConfig":{}}'

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo -e "  ${GREEN}Script Complete${NC}"
echo "========================================================"
echo ""
echo "  For anything that showed WARN, open these links:"
echo "    App Check : https://console.firebase.google.com/project/${PROJECT_ID}/appcheck"
echo "    TTL Policy: https://console.firebase.google.com/project/${PROJECT_ID}/firestore/ttl"
echo ""
echo "  Always-manual items:"
echo "    ⚠️  Upload Apple DeviceCheck .p8 key in App Check Console (iOS)"
echo "    ⚠️  Add debug tokens per device in App Check Console"
echo ""
