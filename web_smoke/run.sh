#!/usr/bin/env bash
# TEST HARNESS ONLY — build the web app against the local mock and drive it.
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH=/opt/flutter/bin:$PATH
export PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

MOCK_PORT=${MOCK_SUPABASE_PORT:-54321}
WEB_PORT=${WEB_PORT:-8080}

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== building web (mock backend at 127.0.0.1:$MOCK_PORT) =="
  flutter build web --release --no-web-resources-cdn \
    --dart-define=SUPABASE_URL=http://127.0.0.1:$MOCK_PORT \
    --dart-define=SUPABASE_ANON_KEY=anon-test-key \
    --dart-define=ONESIGNAL_APP_ID=
  git checkout analysis_options.yaml 2>/dev/null || true
fi

node web_smoke/mock-supabase.mjs & MOCK_PID=$!
node web_smoke/serve.mjs build/web & WEB_PID=$!
trap 'kill $MOCK_PID $WEB_PID 2>/dev/null || true' EXIT
sleep 2

node web_smoke/smoke.mjs "$@"
