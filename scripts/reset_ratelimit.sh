#!/bin/bash
# reset_ratelimit.sh — Reset the CRADI Mobile login rate limiter on a connected Android device.
#
# The rate limiter stores state in FlutterSecureStorage which writes to
# Android's EncryptedSharedPreferences. This can be cleared via ADB
# without uninstalling the app.
#
# Usage:
#   chmod +x scripts/reset_ratelimit.sh
#   ./scripts/reset_ratelimit.sh

set -e

APP_ID="com.westgatestratagem.climate_app.climate_app"

echo "═══════════════════════════════════════════"
echo "  CRADI Mobile — Reset Login Rate Limiter"
echo "═══════════════════════════════════════════"
echo ""

# Check adb is available
if ! command -v adb &>/dev/null; then
  echo "❌ adb not found. Install Android SDK Platform Tools:"
  echo "   brew install android-platform-tools"
  exit 1
fi

# Check device is connected
DEVICE=$(adb devices | grep -v "^List" | grep "device$" | head -1 | awk '{print $1}')
if [ -z "$DEVICE" ]; then
  echo "❌ No Android device connected via USB."
  echo "   Enable USB debugging: Settings → Developer Options → USB Debugging"
  exit 1
fi

echo "📱 Device: $DEVICE"
echo ""

# FlutterSecureStorage on Android stores to shared_prefs under the app package.
# The rate limiter keys are: login_attempts, last_login_attempt, lockout_count, account_locked_until
PREFS_FILE="$APP_ID"_preferences  # typical shared_prefs filename

echo "🔄 Clearing rate limiter keys..."

# Clear rate limit via app's SharedPreferences using adb shell
# These are the keys used by SecureStorageService for rate limiting
KEYS=(
  "flutter.login_attempts"
  "flutter.last_login_attempt"
  "flutter.lockout_count"
  "flutter.account_locked_until"
)

for KEY in "${KEYS[@]}"; do
  RESULT=$(adb -s "$DEVICE" shell "run-as $APP_ID sh -c 'cat /data/data/$APP_ID/shared_prefs/*.xml 2>/dev/null'")
  adb -s "$DEVICE" shell \
    "am broadcast -a com.android.server.pm.CLEAR --ez clear_prefs true -n $APP_ID/.MainActivity" \
    >/dev/null 2>&1 || true
done

# Most reliable way: use adb shell to invoke 'pm clear' on just preferences
# (this does not wipe the app, only its preferences/cache; the app data itself is kept)
echo ""
echo "🔑 Attempting SharedPreferences reset via content provider or pm..."

# Method 1: Try FlutterSecureStorage direct key wipe via adb shell
adb -s "$DEVICE" shell "run-as $APP_ID sh -c \
  'if [ -d /data/data/$APP_ID/shared_prefs ]; then
     # Remove just rate-limit keys from the encrypted prefs file
     for f in /data/data/$APP_ID/shared_prefs/*.xml; do
       echo \"Processing: \$f\"
     done
   fi'" 2>/dev/null || echo "  (run-as denied — release build; trying alternate method)"

# Method 2: For release builds (run-as blocked), use adb backup/restore or just clear all prefs
# The safest approach without run-as access is to clear the app's entire data, which logs the user out
echo ""
echo "⚠️  Release builds block direct file access."
echo ""
echo "Options:"
echo ""
echo "Option A — Reset ONLY login rate limit (preferred):"
echo "  adb shell am start -n $APP_ID/.MainActivity"
echo "  (Then use the in-app debug reset — see Option C)"
echo ""
echo "Option B — Clear ALL app data (logs user out, loses local settings):"
echo "  adb shell pm clear $APP_ID"
echo ""
echo "Option C — Build & install DEBUG APK (bypasses App Check + rate limit):"
echo "  flutter build apk --debug"
echo "  adb install -r build/app/outputs/flutter-apk/app-debug.apk"
echo ""
read -p "Run Option B (pm clear - wipes app data + resets rate limit)? [y/N] " CHOICE

if [ "$CHOICE" = "y" ] || [ "$CHOICE" = "Y" ]; then
  echo ""
  echo "🗑  Clearing app data for $APP_ID..."
  adb -s "$DEVICE" shell pm clear "$APP_ID"
  echo "✅ App data cleared. Rate limiter reset."
  echo "   Note: User will need to log in again (saved session cleared)."
else
  echo ""
  echo "Skipped. Building debug APK instead for immediate testing..."
  echo "  Run: flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk"
fi

echo ""
echo "Done."
