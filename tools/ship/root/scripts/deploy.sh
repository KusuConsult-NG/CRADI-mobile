#!/usr/bin/env bash
#
# One entry point for the three things that deploy.
#
#   ./scripts/deploy.sh functions     the Appwrite Functions
#   ./scripts/deploy.sh web           the admin panel (Appwrite Sites)
#   ./scripts/deploy.sh apk           a signed release APK
#   ./scripts/deploy.sh check         configuration only, deploys nothing
#
# Credentials come from the environment, never from this repository. Put
# them in a file outside the checkout and source it first:
#
#   set -a; source ~/.cradi/appwrite-cloud.env; set +a
#   ./scripts/deploy.sh functions
#
set -euo pipefail
cd "$(dirname "$0")/.."

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\n\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { [ -n "${!1:-}" ]; }

require() {
  # A string, not an array: macOS ships bash 3.2, where expanding an empty
  # array under `set -u` is an error rather than nothing.
  local missing=''
  for v in "$@"; do have "$v" || missing="$missing $v"; done
  [ -z "$missing" ] || die "not set:$missing
  Source your credentials file first:  set -a; source ~/.cradi/appwrite-cloud.env; set +a"
}

check() {
  say "Configuration"
  for v in APPWRITE_ENDPOINT APPWRITE_PROJECT_ID APPWRITE_DATABASE_ID \
           APPWRITE_API_KEY TERMII_API_KEY TERMII_SENDER_ID; do
    # Values are never printed — only whether each one is there.
    have "$v" && printf '  %-24s set\n' "$v" || printf '  %-24s \033[31mMISSING\033[0m\n' "$v"
  done
  printf '\n'
  [ -f mobile/env.json ] && printf '  %-24s present\n' 'mobile/env.json' \
                         || printf '  %-24s \033[31mmissing\033[0m (the app will start signed out)\n' 'mobile/env.json'
  [ -f mobile/android/key.properties ] && printf '  %-24s present\n' 'android/key.properties' \
                                       || printf '  %-24s \033[31mmissing\033[0m (a release build will refuse to run)\n' 'android/key.properties'
}

# ── The Appwrite Functions ───────────────────────────────────────────────
#
# Nothing in CI does this. The deploy rewrites each Function's variables
# from the environment it is given, so a missing TERMII_* silently turns
# off every authority SMS — deploy.mjs refuses rather than let that pass,
# and ALLOW_SMS_OFF=1 is the deliberate override.
deploy_functions() {
  require APPWRITE_ENDPOINT APPWRITE_PROJECT_ID APPWRITE_API_KEY
  say "Deploying the Appwrite Functions"
  ( cd mobile && node infra/appwrite/local/deploy.mjs )
  printf '\n  Confirm in the console that each Function is `ready` with a\n'
  printf '  non-zero build time. See mobile/docs/CUTOVER-RUNBOOK.md.\n'
}

# ── The admin panel ──────────────────────────────────────────────────────
#
# Appwrite Sites builds from the connected repository, so this only proves
# the build is sound before the push that triggers it. The adapter must be
# SSR: under `static` every route 404s, which is not obvious from the
# build log. See web/SETUP.md.
deploy_web() {
  say "Building the admin panel"
  ( cd web && npm ci && npx tsc --noEmit && npx eslint . --max-warnings 0 && npm run build )
  printf '\n  Build is sound. Push to the branch Appwrite Sites tracks to deploy.\n'
  printf '  Adapter must be SSR, and APPWRITE_API_KEY marked secret.\n'
}

# ── A signed release APK ─────────────────────────────────────────────────
deploy_apk() {
  [ -f mobile/env.json ] || die "mobile/env.json is missing.
  Without it APPWRITE_ENDPOINT and APPWRITE_PROJECT_ID compile in empty and
  the app behaves as permanently signed out. Copy mobile/env.example.json."
  [ -f mobile/android/key.properties ] || die "mobile/android/key.properties is missing.
  The release build refuses rather than silently debug-signing."
  say "Building the release APK"
  ( cd mobile && flutter clean && flutter pub get \
      && flutter build apk --release --dart-define-from-file=env.json )
  local apk=mobile/build/app/outputs/flutter-apk/app-release.apk
  say "Verifying the signature"
  keytool -printcert -jarfile "$apk" | grep SHA256 \
    || die "could not read a certificate from $apk"
  printf '\n  Compare that against your keystore:\n'
  printf '    keytool -list -v -keystore <keystore> -alias cradi | grep SHA256\n'
  printf '  They must match. CN=Android Debug means the signing config was not picked up.\n'
  printf '\n  %s\n' "$apk"
}

case "${1:-}" in
  functions) deploy_functions ;;
  web)       deploy_web ;;
  apk)       deploy_apk ;;
  check)     check ;;
  *) sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
