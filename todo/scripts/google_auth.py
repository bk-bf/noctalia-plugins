#!/usr/bin/env python3
"""
Google OAuth 2.0 PKCE authentication for Noctalia Todo plugin.
Usage: python3 google_auth.py <client_id> <client_secret> <output_json_file>

Writes {"success": true, "email": "..."} or {"success": false, "error": "..."}
to the output file.

Dependencies: python3, secret-tool (libsecret-tools), xdg-open
"""

import sys
import json
import secrets
import hashlib
import base64
import urllib.parse
import urllib.request
import urllib.error
import http.server
import subprocess
import os


def fail(msg, output_file):
    with open(output_file, "w") as f:
        json.dump({"success": False, "error": msg}, f)
    sys.exit(1)


def store_secret(label, account, value, output_file):
    proc = subprocess.run(
        [
            "secret-tool", "store",
            "--label", label,
            "service", "noctalia-todo",
            "account", account,
        ],
        input=value.encode(),
        capture_output=True,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.decode(errors="replace").strip()
        fail(f"Failed to store {account} in keyring: {stderr or 'secret-tool exited ' + str(proc.returncode)}", output_file)


def main():
    if len(sys.argv) < 4:
        out = sys.argv[3] if len(sys.argv) > 3 else "/tmp/noctalia_todo_auth_err.json"
        fail("Usage: google_auth.py <client_id> <client_secret> <output_json_file>", out)

    client_id = sys.argv[1].strip()
    client_secret = sys.argv[2].strip()
    output_file = sys.argv[3]

    if not client_id:
        fail("client_id is empty", output_file)
    if not client_secret:
        fail("client_secret is empty", output_file)

    # Debug: write received args to temp file
    debug_file = output_file + ".debug"
    with open(debug_file, "w") as f:
        json.dump({
            "client_id_len": len(client_id),
            "client_id_first10": client_id[:10],
            "client_secret_len": len(client_secret),
        }, f, indent=2)

    # PKCE — code_verifier (43 url-safe chars) and S256 code_challenge
    raw = secrets.token_bytes(32)
    code_verifier = base64.urlsafe_b64encode(raw).rstrip(b"=").decode()
    if len(code_verifier) > 128:
        code_verifier = code_verifier[:128]
    digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
    code_challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode()

    scope = "https://www.googleapis.com/auth/tasks https://www.googleapis.com/auth/userinfo.email"
    redirect_uri = "http://127.0.0.1:9785"
    port = 9785

    params = urllib.parse.urlencode({
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": scope,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
        "access_type": "offline",
        "prompt": "consent",
    })
    auth_url = f"https://accounts.google.com/o/oauth2/v2/auth?{params}"

    print(f"AUTH_URL: {auth_url}", flush=True)
    subprocess.Popen(["xdg-open", auth_url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Minimal HTTP server to catch the OAuth redirect (120 s timeout)
    auth_code = []
    auth_error = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            code = query.get("code", [""])[0]
            error = query.get("error", [""])[0]
            if code:
                auth_code.append(code)
                body = b"<html><body><h2>Authentication successful! You can close this tab.</h2></body></html>"
            else:
                auth_error.append(error or "access_denied")
                body = b"<html><body><h2>Authentication failed. You can close this tab.</h2></body></html>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):  # noqa: A002
            pass

    try:
        server = http.server.HTTPServer(("127.0.0.1", port), Handler)
        server.timeout = 120
        server.handle_request()
        server.server_close()
    except OSError as e:
        fail(f"Could not start local HTTP server on port {port}: {e}", output_file)

    if not auth_code:
        reason = auth_error[0] if auth_error else "timeout or no response"
        fail(f"No authorization code received ({reason})", output_file)

    code = auth_code[0]

    # Exchange authorization code for tokens
    token_data_raw = urllib.parse.urlencode({
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
        "code_verifier": code_verifier,
        "grant_type": "authorization_code",
        "redirect_uri": redirect_uri,
    }).encode("ascii")

    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=token_data_raw,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    try:
        with urllib.request.urlopen(req) as resp:
            token_data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        try:
            err_json = json.loads(body)
            detail = err_json.get("error_description") or err_json.get("error") or body
        except Exception:
            detail = body
        fail(f"Token exchange failed: {detail}", output_file)
        return
    except Exception as e:
        fail(f"Token exchange error: {e}", output_file)
        return

    access_token = token_data.get("access_token", "")
    refresh_token = token_data.get("refresh_token", "")

    if not access_token:
        fail(f"No access_token in response: {json.dumps(token_data)}", output_file)

    # Store all credentials in GNOME Keyring / KWallet via secret-tool
    store_secret("Noctalia Todo Google Access Token",  "google_access_token",  access_token,  output_file)
    store_secret("Noctalia Todo Google Client ID",     "google_client_id",     client_id,     output_file)
    store_secret("Noctalia Todo Google Client Secret", "google_client_secret", client_secret, output_file)
    if refresh_token:
        store_secret("Noctalia Todo Google Refresh Token", "google_refresh_token", refresh_token, output_file)

    # Fetch signed-in email
    email = ""
    try:
        req2 = urllib.request.Request(
            "https://www.googleapis.com/oauth2/v1/userinfo",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        with urllib.request.urlopen(req2) as resp:
            email = json.loads(resp.read().decode()).get("email", "")
    except Exception:
        pass  # email is optional

    with open(output_file, "w") as f:
        json.dump({"success": True, "email": email}, f)


if __name__ == "__main__":
    main()
