#!/usr/bin/env python3
"""
Google Tasks bidirectional sync for Noctalia Todo plugin.

Usage: google_sync.py <access_token> <todos_b64> <pages_b64> <output_file>

  todos_b64   base64-encoded JSON array of local todo objects
  pages_b64   base64-encoded JSON array of local page objects
  output_file path to write {"todos": [...], "pages": [...]}

Sync rules (local is considered the source of truth for content):
  - Local todo WITH googleTaskId   → update the matching Google task
  - Local todo WITHOUT googleTaskId → create in Google, store the new ID back
  - Google task NOT matched locally → import into local (from another device / web)

Priority is encoded in the Google task's notes field as [priority:high/medium/low]
so it round-trips cleanly.  The rest of notes becomes the local "details" field.
"""

import sys
import json
import base64
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _api(method, url, token, data=None):
    body = json.dumps(data).encode() if data is not None else None
    headers = {"Authorization": f"Bearer {token}"}
    if body:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        if e.code == 404 and method == "DELETE":
            return {}
        raise RuntimeError(
            f"HTTP {e.code} {method} {url}: {e.read().decode(errors='replace')}"
        ) from e


def api_get(url, token):    return _api("GET",    url, token)
def api_post(url, token, data): return _api("POST",   url, token, data)
def api_patch(url, token, data):return _api("PATCH",  url, token, data)
def api_delete(url, token):     return _api("DELETE", url, token)


# ---------------------------------------------------------------------------
# Priority <-> notes encoding
# ---------------------------------------------------------------------------

def encode_notes(priority, details):
    tag = f"[priority:{priority}]"
    return f"{tag} {details}".strip() if details else tag


def decode_notes(notes):
    priority = "medium"
    details = (notes or "").strip()
    for p in ("high", "medium", "low"):
        tag = f"[priority:{p}]"
        if tag in details:
            priority = p
            details = details.replace(tag, "").strip()
            break
    return priority, details


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


_id_seq = [int(time.time() * 1000)]


def unique_local_id():
    _id_seq[0] += 1
    return _id_seq[0]


# ---------------------------------------------------------------------------
# Main sync logic
# ---------------------------------------------------------------------------

def main():
    token       = sys.argv[1]
    todos       = json.loads(base64.b64decode(sys.argv[2]))
    pages       = json.loads(base64.b64decode(sys.argv[3]))
    output_file = sys.argv[4]

    BASE = "https://tasks.googleapis.com/tasks/v1"

    # ------------------------------------------------------------------
    # Step 1: Resolve (or create) a Google Task List for every local page
    # ------------------------------------------------------------------
    gl_resp = api_get(f"{BASE}/users/@me/lists", token)
    gl_lists = gl_resp.get("items", [])
    by_name = {lst["title"]: lst for lst in gl_lists}
    by_id   = {lst["id"]:    lst for lst in gl_lists}

    updated_pages = []
    page_to_list  = {}   # local page id (int) -> google list id (str)

    for page in pages:
        page = dict(page)
        gl_id = page.get("googleListId", "")

        if gl_id and gl_id in by_id:
            pass  # already mapped
        elif page["name"] in by_name:
            gl_id = by_name[page["name"]]["id"]
            page["googleListId"] = gl_id
        else:
            new_list = api_post(f"{BASE}/users/@me/lists", token, {"title": page["name"]})
            gl_id = new_list["id"]
            page["googleListId"] = gl_id
            by_id[gl_id] = new_list

        page_to_list[page["id"]] = gl_id
        updated_pages.append(page)

    # ------------------------------------------------------------------
    # Step 2: Fetch all existing Google tasks per list (paginated)
    # ------------------------------------------------------------------
    gl_tasks_by_list = {}   # gl_list_id -> {task_id: task_obj}

    for gl_id in set(page_to_list.values()):
        tasks = []
        page_token = None
        while True:
            url = (
                f"{BASE}/lists/{gl_id}/tasks"
                "?showCompleted=True&showHidden=True&maxResults=100"
            )
            if page_token:
                url += f"&pageToken={page_token}"
            resp = api_get(url, token)
            tasks.extend(resp.get("items", []))
            page_token = resp.get("nextPageToken")
            if not page_token:
                break
        gl_tasks_by_list[gl_id] = {t["id"]: t for t in tasks}

    # ------------------------------------------------------------------
    # Step 3: Push every local todo to Google (create or update)
    # ------------------------------------------------------------------
    updated_todos = []
    seen_google_ids = set()

    for todo in todos:
        todo = dict(todo)
        gl_id = page_to_list.get(todo.get("pageId", 0))
        if not gl_id:
            updated_todos.append(todo)
            continue

        payload = {
            "title":  todo.get("text", ""),
            "status": "completed" if todo.get("completed") else "needsAction",
            "notes":  encode_notes(
                          todo.get("priority", "medium"),
                          todo.get("details", ""),
                      ),
        }

        google_task_id = todo.get("googleTaskId", "")
        if google_task_id and google_task_id in gl_tasks_by_list.get(gl_id, {}):
            api_patch(f"{BASE}/lists/{gl_id}/tasks/{google_task_id}", token, payload)
            todo["googleListId"] = gl_id
            seen_google_ids.add(google_task_id)
        else:
            new_task = api_post(f"{BASE}/lists/{gl_id}/tasks", token, payload)
            todo["googleTaskId"] = new_task["id"]
            todo["googleListId"] = gl_id
            seen_google_ids.add(new_task["id"])

        updated_todos.append(todo)

    # ------------------------------------------------------------------
    # Step 4: Import Google tasks that don't exist locally
    # ------------------------------------------------------------------
    for page in updated_pages:
        gl_id = page_to_list.get(page["id"])
        if not gl_id:
            continue
        for task_id, task in gl_tasks_by_list.get(gl_id, {}).items():
            if task_id in seen_google_ids:
                continue
            title = task.get("title", "").strip()
            if not title:
                continue  # skip blank / deleted stubs
            priority, details = decode_notes(task.get("notes", ""))
            new_todo = {
                "id":           unique_local_id(),
                "text":         title,
                "completed":    task.get("status") == "completed",
                "createdAt":    task.get("due") or now_iso(),
                "pageId":       page["id"],
                "priority":     priority,
                "details":      details,
                "googleTaskId": task_id,
                "googleListId": gl_id,
            }
            updated_todos.append(new_todo)
            seen_google_ids.add(task_id)

    # ------------------------------------------------------------------
    # Write result
    # ------------------------------------------------------------------
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump({"todos": updated_todos, "pages": updated_pages}, f)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # Write a structured error so QML can surface it
        err_msg = str(exc).replace('"', '\\"')
        output_file = sys.argv[4] if len(sys.argv) > 4 else "/tmp/noctalia_sync_error.json"
        with open(output_file, "w") as f:
            f.write(f'{{"error": "{err_msg}"}}')
        sys.exit(1)
