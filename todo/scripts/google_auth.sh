#!/usr/bin/env bash
# Google OAuth 2.0 PKCE authentication for Noctalia Todo plugin.
# Usage: google_auth.sh <client_id> <output_json_file>
#
# Writes {"success": true, "email": "..."} or {"success": false, "error": "..."}
# to the output file. No client_secret needed — uses PKCE (RFC 7636).
#
# Dependencies: bash, python3, secret-tool (libsecret-tools), xdg-open

set -uo pipefail

CLIENT_ID="${1:-}"
OUTPUT_FILE="${2:-}"

fail() {
    local msg="${1//\"/\\\"}"
    printf '{"success": false, "error": "%s"}' "$msg" > "$OUTPUT_FILE"
    exit 1
}

[[ -z "$CLIENT_ID" ]]   && fail "client_id required"
[[ -z "$OUTPUT_FILE" ]] && fail "output_file required"

SCOPE="https://www.googleapis.com/auth/tasks https://www.googleapis.com/auth/userinfo.email"
REDIRECT_URI="http://127.0.0.1:9785"
PORT=9785

# --- PKCE: generate code_verifier + code_challenge ---
CODE_VERIFIER=$(python3 -c "
import secrets, base64
raw = secrets.token_bytes(32)
print(base64.urlsafe_b64encode(raw).rstrip(b'=').decode()[:43])
") || fail "Failed to generate code_verifier"

CODE_CHALLENGE=$(python3 -c "
import hashlib, base64, sys
v = sys.argv[1].encode()
digest = hashlib.sha256(v).digest()
print(base64.urlsafe_b64encode(digest).rstrip(b'=').decode())
" "$CODE_VERIFIER") || fail "Failed to generate code_challenge"

SCOPE_ENC=$(python3 -c "
import urllib.parse, sys
print(urllib.parse.quote(sys.argv[1]))
" "$SCOPE")

AUTH_URL="https://accounts.google.com/o/oauth2/v2/auth"
AUTH_URL="${AUTH_URL}?client_id=${CLIENT_ID}"
AUTH_URL="${AUTH_URL}&redirect_uri=${REDIRECT_URI}"
AUTH_URL="${AUTH_URL}&response_type=code"
AUTH_URL="${AUTH_URL}&scope=${SCOPE_ENC}"
AUTH_URL="${AUTH_URL}&code_challenge=${CODE_CHALLENGE}"
AUTH_URL="${AUTH_URL}&code_challenge_method=S256"
AUTH_URL="${AUTH_URL}&access_type=offline"
AUTH_URL="${AUTH_URL}&prompt=consent"

# Open browser
xdg-open "$AUTH_URL" 2>/dev/null || true

# Minimal HTTP server to catch the redirect callback (120s timeout)
AUTH_CODE=$(python3 -c "
import http.server, urllib.parse, sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        self.server._code  = params.get('code',  [''])[0]
        self.server._error = params.get('error', [''])[0]
        if self.server._code:
            body = b'<html><body><h2>Authentication successful! You can close this tab.</h2></body></html>'
        else:
            body = b'<html><body><h2>Authentication failed. You can close this tab.</h2></body></html>'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass

server = http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler)
server._code = ''
server._error = ''
server.timeout = 120
server.handle_request()
if server._error:
    sys.exit(1)
print(server._code)
" "$PORT") || fail "No authorization code received (timeout or access denied)"

[[ -z "$AUTH_CODE" ]] && fail "No authorization code received"

# Exchange code for tokens — no client_secret required with PKCE
TOKEN_JSON=$(python3 -c "
import urllib.request, urllib.parse, json, sys

client_id, code, verifier, redirect_uri = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
data = urllib.parse.urlencode({
    'client_id':     client_id,
    'code':          code,
    'code_verifier': verifier,
    'grant_type':    'authorization_code',
    'redirect_uri':  redirect_uri,
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
" "$CLIENT_ID" "$AUTH_CODE" "$CODE_VERIFIER" "$REDIRECT_URI") || fail "Token exchange failed"

ACCESS_TOKEN=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('access_token', ''))
" "$TOKEN_JSON")

REFRESH_TOKEN=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('refresh_token', ''))
" "$TOKEN_JSON")

[[ -z "$ACCESS_TOKEN" ]] && fail "Empty access token in response"

# Store tokens encrypted in GNOME Keyring / KWallet via secret-tool
printf '%s' "$ACCESS_TOKEN" | secret-tool store \
    --label="Noctalia Todo Google Access Token" \
    service "noctalia-todo" account "google_access_token" \
    || fail "Failed to store access token"

printf '%s' "$CLIENT_ID" | secret-tool store \
    --label="Noctalia Todo Google Client ID" \
    service "noctalia-todo" account "google_client_id" \
    || fail "Failed to store client ID"

if [[ -n "$REFRESH_TOKEN" ]]; then
    printf '%s' "$REFRESH_TOKEN" | secret-tool store \
        --label="Noctalia Todo Google Refresh Token" \
        service "noctalia-todo" account "google_refresh_token" \
        || fail "Failed to store refresh token"
fi

# Retrieve signed-in email
EMAIL=$(python3 -c "
import urllib.request, json, sys
req = urllib.request.Request(
    'https://www.googleapis.com/oauth2/v1/userinfo',
    headers={'Authorization': 'Bearer ' + sys.argv[1]},
)
try:
    with urllib.request.urlopen(req) as r:
        print(json.loads(r.read()).get('email', ''))
except Exception:
    print('')
" "$ACCESS_TOKEN")

EMAIL_SAFE="${EMAIL//\"/\\\"}"
printf '{"success": true, "email": "%s"}' "$EMAIL_SAFE" > "$OUTPUT_FILE"
