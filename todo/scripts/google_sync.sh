#!/usr/bin/env bash
# Google Tasks bidirectional sync wrapper for Noctalia Todo plugin.
# Usage: google_sync.sh <todos_b64> <pages_b64> <output_file> [filter_page_id]
# Writes JSON result to <output_file>.

set -uo pipefail

TODOS_B64="$1"
PAGES_B64="$2"
OUTPUT_FILE="${3:-/tmp/noctalia_todo_sync.json}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get a fresh (refreshed) access token
ACCESS_TOKEN=$("$SCRIPT_DIR/google_token_get.sh") || {
    printf '{"error": "Could not obtain access token"}' > "$OUTPUT_FILE"
    exit 1
}

# Delegate all sync logic to the Python script — result written to OUTPUT_FILE
python3 "$SCRIPT_DIR/google_sync.py" "$ACCESS_TOKEN" "$TODOS_B64" "$PAGES_B64" "$OUTPUT_FILE" ${4:+"$4"}
