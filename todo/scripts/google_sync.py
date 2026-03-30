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

Details are stored in Google task notes as plain text.
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
# Notes encoding (details only — no priority)
# ---------------------------------------------------------------------------

def encode_notes(details):
    return (details or "").strip()


def decode_notes(notes):
    return (notes or "").strip()


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
    output_file = sys.argv[4] if len(sys.argv) > 4 else "/dev/null"
    filter_page_id = int(sys.argv[5]) if len(sys.argv) > 5 else None

    # Per-list mode: restrict to one page and its todos only
    if filter_page_id is not None:
        pages = [p for p in pages if p.get("id") == filter_page_id]
        todos = [t for t in todos if t.get("pageId") == filter_page_id]

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

    # Also create local pages for Google Task lists that have no local page yet
    # (e.g. "My Tasks" on a fresh install, or lists created on another device)
    # Only during full sync — skip when doing a per-list sync.
    if filter_page_id is None:
        mapped_gl_ids = set(page_to_list.values())
        existing_ids  = [p["id"] for p in updated_pages]
        next_page_id  = (max(existing_ids) + 1) if existing_ids else 1
        for gl_id, gl_list in by_id.items():
            if gl_id in mapped_gl_ids:
                continue
            title = gl_list.get("title", "").strip()
            if not title:
                continue
            new_page = {
                "id":           next_page_id,
                "name":         title,
                "googleListId": gl_id,
            }
            updated_pages.append(new_page)
            page_to_list[next_page_id] = gl_id
            next_page_id += 1

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
    # Sort so top-level tasks are pushed before subtasks.
    # ------------------------------------------------------------------
    # Pre-build local_id -> googleTaskId for already-synced tasks
    local_to_google: dict = {}
    for t in todos:
        lid = str(t.get("id", ""))
        gtid = t.get("googleTaskId", "")
        if lid and gtid:
            local_to_google[lid] = gtid

    todos_sorted = sorted(todos, key=lambda t: 0 if not t.get("parentId") else 1)

    updated_todos = []
    seen_google_ids = set()

    for todo in todos_sorted:
        todo = dict(todo)
        gl_id = page_to_list.get(todo.get("pageId", 0))
        if not gl_id:
            updated_todos.append(todo)
            continue

        due_date = todo.get("dueDate", "")
        payload = {
            "title":  todo.get("text", ""),
            "status": "completed" if todo.get("completed") else "needsAction",
            "notes":  encode_notes(
                          todo.get("details", ""),
                      ),
            "due": (due_date + "T00:00:00.000Z") if due_date else None,
        }

        google_task_id = todo.get("googleTaskId", "")
        if google_task_id and google_task_id in gl_tasks_by_list.get(gl_id, {}):
            api_patch(f"{BASE}/lists/{gl_id}/tasks/{google_task_id}", token, payload)
            todo["googleListId"] = gl_id
            seen_google_ids.add(google_task_id)
            local_to_google[str(todo.get("id", ""))] = google_task_id
        elif google_task_id:
            # Had a Google ID but not found on Google anymore — was deleted there, drop locally
            continue
        else:
            create_url = f"{BASE}/lists/{gl_id}/tasks"
            parent_local_id = str(todo.get("parentId", ""))
            parent_google_id = (
                local_to_google.get(parent_local_id, "")
                or todo.get("googleParentTaskId", "")
            )
            if parent_google_id:
                create_url += f"?parent={parent_google_id}"
            new_task = api_post(create_url, token, payload)
            todo["googleTaskId"] = new_task["id"]
            todo["googleListId"] = gl_id
            if parent_google_id:
                todo["googleParentTaskId"] = parent_google_id
            local_to_google[str(todo.get("id", ""))] = new_task["id"]
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
            details = decode_notes(task.get("notes", ""))
            new_todo = {
                "id":                 unique_local_id(),
                "text":               title,
                "completed":          task.get("status") == "completed",
                "createdAt":          now_iso(),
                "pageId":             page["id"],
                "priority":           "medium",
                "details":            details,
                "dueDate":            task.get("due", "")[:10] if task.get("due") else "",
                "parentId":           "",  # resolved in Step 5
                "googleTaskId":       task_id,
                "googleListId":       gl_id,
                "googleParentTaskId": task.get("parent", ""),
            }
            updated_todos.append(new_todo)
            seen_google_ids.add(task_id)

    # ------------------------------------------------------------------
    # Step 5: Resolve parentId from googleParentTaskId for imported tasks
    # ------------------------------------------------------------------
    gtid_to_local: dict = {}
    for t in updated_todos:
        gtid = t.get("googleTaskId", "")
        if gtid:
            gtid_to_local[gtid] = t["id"]
    for t in updated_todos:
        gp = t.get("googleParentTaskId", "")
        if gp and not t.get("parentId") and gp in gtid_to_local:
            t["parentId"] = gtid_to_local[gp]

    # ------------------------------------------------------------------
    # Write result
    # ------------------------------------------------------------------
    result: dict = {"todos": updated_todos, "pages": updated_pages}
    if filter_page_id is not None:
        result["filter_page_id"] = filter_page_id
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(result, f)
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        output_file = sys.argv[4] if len(sys.argv) > 4 else "/dev/null"
        err_json = json.dumps({"error": str(exc)})
        if output_file != "/dev/null":
            with open(output_file, "w") as f:
                f.write(err_json)
        print(err_json, flush=True)
        sys.exit(1)
