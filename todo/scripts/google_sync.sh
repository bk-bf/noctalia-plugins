#!/usr/bin/env bash
# Google Tasks bidirectional sync wrapper for Noctalia Todo plugin.
# Usage: google_sync.sh <todos_b64> <pages_b64> <output_json_file>
#
# todos_b64 / pages_b64: base64-encoded JSON arrays (Qt.btoa output)
# output_json_file:      path where {"todos": [...], "pages": [...]} will be written

set -uo pipefail

TODOS_B64="$1"
PAGES_B64="$2"
OUTPUT_FILE="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get a fresh (refreshed) access token
ACCESS_TOKEN=$("$SCRIPT_DIR/google_token_get.sh") || {
    printf '{"error": "Could not obtain access token"}' > "$OUTPUT_FILE"
    exit 1
}

# Delegate all sync logic to the Python script
python3 "$SCRIPT_DIR/google_sync.py" "$ACCESS_TOKEN" "$TODOS_B64" "$PAGES_B64" "$OUTPUT_FILE"
