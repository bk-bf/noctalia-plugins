#!/usr/bin/env bash
# Rename a Google Task List.
# Usage: google_rename_list.sh <list_id> <new_title>

set -uo pipefail

LIST_ID="$1"
NEW_TITLE="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACCESS_TOKEN=$("$SCRIPT_DIR/google_token_get.sh") || {
    printf '{"error": "Could not obtain access token"}'
    exit 1
}

python3 "$SCRIPT_DIR/google_rename_list.py" "$ACCESS_TOKEN" "$LIST_ID" "$NEW_TITLE"
