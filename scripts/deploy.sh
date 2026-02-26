#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# EWER App — Firebase Production Deploy Script
# Project: ewer-8f788
# Run: chmod +x scripts/deploy.sh && ./scripts/deploy.sh
#
# What this deploys:
#   1. Firestore security rules
#   2. Firestore indexes
#   3. Cloud Functions (all 5)
#   4. Firebase Hosting (assetlinks.json, apple-app-site-association)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_ID="ewer-8f788"
REGION="us-central1"

print_step() { echo -e "\n\033[36m▶ $1\033[0m"; }
print_ok()   { echo -e "\033[32m✓ $1\033[0m"; }
print_warn() { echo -e "\033[33m⚠ $1\033[0m"; }
print_err()  { echo -e "\033[31m✗ $1\033[0m"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
print_step "Preflight checks"
if ! command -v firebase &> /dev/null; then
  print_err "firebase CLI not found. Install: npm install -g firebase-tools"
  exit 1
fi

if ! firebase projects:list 2>/dev/null | grep -q "$PROJECT_ID"; then
  print_warn "You may not be logged in. Running: firebase login"
  firebase login
fi

# ── 1. Firestore security rules ───────────────────────────────────────────────
print_step "Deploying Firestore security rules"
firebase deploy \
  --only firestore:rules \
  --project "$PROJECT_ID" \
  --message "rules: deploy from deploy.sh $(date '+%Y-%m-%d %H:%M')"
print_ok "Firestore rules deployed"

# ── 2. Firestore indexes ──────────────────────────────────────────────────────
print_step "Deploying Firestore indexes"
firebase deploy \
  --only firestore:indexes \
  --project "$PROJECT_ID"
print_ok "Firestore indexes deployed"

# ── 3. Cloud Functions ────────────────────────────────────────────────────────
print_step "Installing Cloud Function dependencies"
for fn in send-email alert-distribution escalation-timer verification-request statistics-aggregation; do
  if [ -f "functions/$fn/package.json" ]; then
    echo "  → Installing $fn"
    (cd "functions/$fn" && npm install --silent)
  fi
done

# Check RESEND_API_KEY is set
if ! firebase functions:config:get 2>/dev/null | grep -q "resend.api_key"; then
  print_warn "Resend API key not configured in Firebase Functions config."
  print_warn "Run: firebase functions:config:set resend.api_key=YOUR_KEY from_email=noreply@cradi.ng from_name=\"EWER Alert System\""
fi

print_step "Deploying Cloud Functions"
firebase deploy \
  --only functions \
  --project "$PROJECT_ID"
print_ok "Cloud Functions deployed"

# ── 4. Hosting (deep link verification files) ─────────────────────────────────
print_step "Deploying Firebase Hosting (assetlinks.json, apple-app-site-association)"
if [ -f "web/.well-known/assetlinks.json" ]; then
  firebase deploy \
    --only hosting \
    --project "$PROJECT_ID"
  print_ok "Hosting deployed"
else
  print_warn "web/.well-known/assetlinks.json not found — skipping hosting deploy"
fi

# ── 5. App Check enforcement reminder ────────────────────────────────────────
echo ""
print_warn "Manual step required: Enable App Check enforcement in Firebase Console"
print_warn "  → Firebase Console → App Check → Apps → EWER Mobile → Enforce"
echo ""

print_ok "Deploy complete! Project: $PROJECT_ID"
echo "  Firestore rules:  https://console.firebase.google.com/project/$PROJECT_ID/firestore/rules"
echo "  Functions:        https://console.firebase.google.com/project/$PROJECT_ID/functions"
echo "  Hosting:          https://console.firebase.google.com/project/$PROJECT_ID/hosting"
