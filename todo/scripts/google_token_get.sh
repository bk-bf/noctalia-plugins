#!/usr/bin/env bash
# Refresh the Google access token and print it to stdout.
# Used by google_sync.sh before each sync.
# On failure: prints error to stderr and exits 1.

set -uo pipefail

CLIENT_ID=$(secret-tool lookup service "noctalia-todo" account "google_client_id" 2>/dev/null || true)
CLIENT_SECRET=$(secret-tool lookup service "noctalia-todo" account "google_client_secret" 2>/dev/null || true)
REFRESH_TOKEN=$(secret-tool lookup service "noctalia-todo" account "google_refresh_token" 2>/dev/null || true)

if [[ -z "$CLIENT_ID" ]] || [[ -z "$CLIENT_SECRET" ]] || [[ -z "$REFRESH_TOKEN" ]]; then
    echo "ERROR: Not authenticated — missing credentials in keyring" >&2
    exit 1
fi

TOKEN_JSON=$(python3 -c "
import urllib.request, urllib.parse, json, sys

client_id, client_secret, refresh_token = sys.argv[1], sys.argv[2], sys.argv[3]
data = urllib.parse.urlencode({
    'client_id':     client_id,
    'client_secret': client_secret,
    'refresh_token': refresh_token,
    'grant_type':    'refresh_token',
}).encode()

req = urllib.request.Request(
    'https://oauth2.googleapis.com/token',
    data=data,
    headers={'Content-Type': 'application/x-www-form-urlencoded'},
)
try:
    with urllib.request.urlopen(req) as r:
        print(r.read().decode())
except urllib.error.HTTPError as e:
    print(json.dumps({'error': e.read().decode()}), file=sys.stderr)
    sys.exit(1)
" "$CLIENT_ID" "$CLIENT_SECRET" "$REFRESH_TOKEN") || { echo "ERROR: Token refresh request failed" >&2; exit 1; }

ACCESS_TOKEN=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('access_token', ''))
" "$TOKEN_JSON")

if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "ERROR: Empty access token — refresh may have expired, please sign in again" >&2
    exit 1
fi

# Update the stored access token
printf '%s' "$ACCESS_TOKEN" | secret-tool store \
    --label="Noctalia Todo Google Access Token" \
    service "noctalia-todo" account "google_access_token"

printf '%s' "$ACCESS_TOKEN"
