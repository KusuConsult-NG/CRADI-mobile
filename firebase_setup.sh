#!/usr/bin/env bash
# =============================================================================
# CRADI Mobile — Firebase Setup Script
# Usage: bash firebase_setup.sh
# =============================================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

PROJECT_ID="ewer-8f788"
FUNCTIONS_DIR="$(dirname "$0")/firebase-functions"

echo ""
echo "========================================================"
echo "  CRADI Mobile — Firebase Go-Live Setup"
echo "  Project: $PROJECT_ID"
echo "========================================================"
echo ""

# ── 0. Pre-flight checks ──────────────────────────────────────────────────────
info "Checking Firebase CLI..."
command -v firebase >/dev/null 2>&1 || error "Firebase CLI not found. Run: npm i -g firebase-tools"
success "Firebase CLI found: $(firebase --version)"

info "Checking active Firebase project..."
ACTIVE=$(firebase use --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")
if [[ "$ACTIVE" != "$PROJECT_ID" ]]; then
  info "Switching to project $PROJECT_ID..."
  firebase use "$PROJECT_ID" || error "Cannot switch to $PROJECT_ID. Run: firebase login"
fi
success "Active project: $PROJECT_ID"

# ── 1. Firestore Rules ────────────────────────────────────────────────────────
echo ""
info "Deploying Firestore Security Rules..."
firebase deploy --only firestore:rules --project "$PROJECT_ID"
success "Firestore rules deployed"

# ── 2. Firestore Indexes ──────────────────────────────────────────────────────
info "Deploying Firestore Indexes..."
firebase deploy --only firestore:indexes --project "$PROJECT_ID"
success "Firestore indexes deployed"

# ── 3. Firebase Functions .env ────────────────────────────────────────────────
echo ""
info "Configuring Firebase Functions environment..."
ENV_FILE="$FUNCTIONS_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  warn ".env already exists at $ENV_FILE — skipping creation."
  warn "To reset it, delete the file and re-run this script."
else
  printf "🔑  Enter your RESEND_API_KEY: "
  read -r RESEND_KEY
  [[ -z "$RESEND_KEY" ]] && error "RESEND_API_KEY is required for email delivery."

  printf "📧  FROM_EMAIL (default: noreply@cradi.ng): "
  read -r FROM_EMAIL
  FROM_EMAIL="${FROM_EMAIL:-noreply@cradi.ng}"

  printf "👤  FROM_NAME (default: EWER Alert System): "
  read -r FROM_NAME
  FROM_NAME="${FROM_NAME:-EWER Alert System}"

  cat > "$ENV_FILE" <<EOF
# Firebase Functions environment — DO NOT COMMIT THIS FILE
RESEND_API_KEY=${RESEND_KEY}
FROM_EMAIL=${FROM_EMAIL}
FROM_NAME=${FROM_NAME}
EOF
  success ".env created at $ENV_FILE"
fi

# ── 4. Deploy Firebase Functions ──────────────────────────────────────────────
echo ""
info "Installing function dependencies..."
(cd "$FUNCTIONS_DIR" && npm install --silent)
success "Dependencies installed"

info "Deploying Firebase Cloud Functions (codebase: cradi-email)..."
firebase deploy --only functions --project "$PROJECT_ID"
success "Firebase Functions deployed"

# ── 5. FCM Default Channel Check (Android) ────────────────────────────────────
echo ""
info "Verifying FCM notification channel in AndroidManifest..."
MANIFEST="$(dirname "$0")/android/app/src/main/AndroidManifest.xml"
if grep -q "alerts_channel" "$MANIFEST" 2>/dev/null; then
  success "FCM alerts_channel already declared in AndroidManifest"
else
  warn "alerts_channel NOT found in AndroidManifest.xml"
  warn "Add the following inside <application> in $MANIFEST:"
  echo ""
  echo '  <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id"'
  echo '             android:value="alerts_channel"/>'
  echo ""
fi

# ── 6. App Check Reminder ─────────────────────────────────────────────────────
echo ""
warn "App Check must be enabled manually in the Firebase Console:"
warn "  → https://console.firebase.google.com/project/$PROJECT_ID/appcheck"
warn "  Enable: Play Integrity (Android) + DeviceCheck (iOS)"
warn "  Register debug tokens for dev builds."

# ── 7. Firestore OTP Cleanup Rule (TTL) ──────────────────────────────────────
echo ""
warn "OTP documents don't auto-delete. Configure Firestore TTL policy:"
warn "  → Firebase Console → Firestore → TTL Policies"
warn "  Collection: otp_verifications | Field: expiresAt"
warn "  This keeps the collection small and removes stale OTPs automatically."

# ── 8. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo -e "  ${GREEN}✅  Firebase Setup Complete${NC}"
echo "========================================================"
echo ""
echo "  Deployed:"
echo "    ✅ Firestore Security Rules"
echo "    ✅ Firestore Indexes"
echo "    ✅ Cloud Functions (sendTransactionalEmail, FCM pipeline)"
echo ""
echo "  Manual steps:"
echo "    ⚠️  Enable Firebase App Check (Play Integrity + DeviceCheck)"
echo "    ⚠️  Add alerts_channel to AndroidManifest (if not already present)"
echo "    ⚠️  Set Firestore TTL policy on otp_verifications.expiresAt"
echo "    ⚠️  Rotate Termii API key (was previously committed to git)"
echo ""
