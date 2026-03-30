#!/usr/bin/env python3
"""Rename a Google Task List via PATCH."""
import sys
import json
import urllib.request
import urllib.error


def main():
    if len(sys.argv) < 4:
        print(json.dumps({"error": "Usage: google_rename_list.py <token> <list_id> <new_title>"}), flush=True)
        sys.exit(1)

    token, list_id, new_title = sys.argv[1], sys.argv[2], sys.argv[3]
    url = f"https://tasks.googleapis.com/tasks/v1/users/@me/lists/{list_id}"
    body = json.dumps({"title": new_title}).encode()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=body, method="PATCH", headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            result = json.loads(r.read())
            print(json.dumps({"success": True, "id": result.get("id"), "title": result.get("title")}), flush=True)
    except urllib.error.HTTPError as e:
        print(json.dumps({"error": f"HTTP {e.code}: {e.read().decode(errors='replace')}"}), flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
