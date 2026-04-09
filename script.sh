#!/usr/bin/env bash
set -euo pipefail

echo "-----------------------------------"
echo " Matrix DB V2 Dynamic Dispatcher"
echo " Date: $(date)"
echo "-----------------------------------"

TARGET_URL="${TARGET_SCRIPT_URL:-}"

if [ -z "$TARGET_URL" ]; then
    echo "ERROR: TARGET_SCRIPT_URL is empty. The workflow did not determine a script to run."
    exit 1
fi

echo "Fetching Dynamic Payload from: $TARGET_URL"

TEMP_DIR="fetched_payload"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo "Entering dynamic build directory: $TEMP_DIR"
cd "$TEMP_DIR"

if [ -z "${FARM_API_TOKEN:-}" ]; then
    echo "WARNING: FARM_API_TOKEN is missing. Request will likely fail."
fi

MAX_RETRIES=10
RETRY_DELAY=45
ATTEMPT=1

fetch_payload() {
    PAYLOAD=$(curl -s --fail -H "Authorization: Bearer $FARM_API_TOKEN" "$TARGET_URL")

    if [ $? -eq 0 ] && [[ "$PAYLOAD" != *"\"error\""* ]]; then
        return 0
    fi

    if [ $ATTEMPT -ge $MAX_RETRIES ]; then
        echo "ERROR: Failed to fetch payload from Matrix DB after $MAX_RETRIES attempts!"
        echo "$PAYLOAD" | jq -r '.error' || echo "$PAYLOAD"
        exit 1
    fi

    echo "WARNING: Matrix DB server busy or returned an error. Retrying in $RETRY_DELAY seconds (Attempt $ATTEMPT of $MAX_RETRIES)..."
    sleep $RETRY_DELAY
    ATTEMPT=$((ATTEMPT + 1))

    fetch_payload
}

fetch_payload

echo "Extracting dynamic payload files..."
echo "$PAYLOAD" | jq -r '."Dockerfile"' > Dockerfile
echo "$PAYLOAD" | jq -r '."config.json"' > config.json
echo "$PAYLOAD" | jq -r '."accounts.json"' > accounts.json

SCRIPT_NAME=$(echo "$PAYLOAD" | jq -r 'keys[] | select(test("\\.sh$"))')

if [ -z "$SCRIPT_NAME" ]; then
    echo "ERROR: No .sh script found in Matrix DB payload!"
    exit 1
fi

echo "$PAYLOAD" | jq -r '."'"$SCRIPT_NAME"'"' > "$SCRIPT_NAME"
chmod +x "$SCRIPT_NAME"

echo "Executing $SCRIPT_NAME inside $(pwd)..."
./"$SCRIPT_NAME"
