#!/bin/bash
set -e

PROJECT_NUMBER="689251502200"
APP_ID="1:689251502200:android:3c102d339da6c4437e458d"

if [ -z "$1" ]; then
  echo "Usage: ./add_appcheck_token.sh <debug_token> [display_name]"
  exit 1
fi

TOKEN="$1"
DISPLAY_NAME="${2:-Emulator Token}"

echo "Authenticating via gcloud..."
ACCESS_TOKEN=$(gcloud auth print-access-token)

echo "Adding App Check Debug Token: $TOKEN ..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://firebaseappcheck.googleapis.com/v1/projects/$PROJECT_NUMBER/apps/$APP_ID/debugTokens" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Goog-User-Project: ewer-8f788" \
  -H "Content-Type: application/json" \
  -d "{
    \"token\": \"$TOKEN\",
    \"displayName\": \"$DISPLAY_NAME\"
  }")

HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$ d')

if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 201 ]; then
    echo "✅ Successfully added debug token!"
    echo "$BODY"
else
    echo "❌ Failed to add debug token. HTTP Status: $HTTP_STATUS"
    echo "$BODY"
    exit 1
fi
