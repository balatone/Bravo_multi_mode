import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
BOARD_DIR = REPO_ROOT / ".board"

FOLDERS = {
    "TO-DO": BOARD_DIR / "to-do",
    "ANALYSING": BOARD_DIR / "in-progress",
    "DESIGNING": BOARD_DIR / "in-progress",
    "PLANNING": BOARD_DIR / "in-progress",
    "IMPLEMENTING": BOARD_DIR / "in-progress",
    "TESTING": BOARD_DIR / "in-progress",
    "REVIEWING": BOARD_DIR / "in-progress",
    "DONE": BOARD_DIR / "done",
}

VALID_STATUSES = set(FOLDERS.keys())


def slugify(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def format_scalar(value: Any) -> str:
    if isinstance(value, str):
        return value if re.fullmatch(r"[A-Za-z0-9_.:-]+", value) else json.dumps(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    return str(value)


def render_metadata(metadata: dict[str, Any]) -> str:
    lines = [
        f"id: {format_scalar(metadata['id'])}",
        f"title: {format_scalar(metadata['title'])}",
        f"version: {format_scalar(metadata.get('version', '1.0.0'))}",
        f"status: {format_scalar(metadata['status'])}",
        f"created: {format_scalar(metadata['created'])}",
        f"updated: {format_scalar(metadata['updated'])}",
    ]

    if metadata.get("primary_doc"):
        lines.append(f"primary_doc: {format_scalar(metadata['primary_doc'])}")

    if "related_docs" in metadata:
        lines.append(f"related_docs: {json.dumps(metadata['related_docs'])}")

    return "\n".join(lines)


def run_git(args: list[str]) -> None:
    try:
        subprocess.run(
            ["git"] + args,
            check=True,
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip() if exc.stderr else ""
        stdout = exc.stdout.strip() if exc.stdout else ""
        message = stderr or stdout or str(exc)
        raise RuntimeError(f"Git error: {message}") from exc


def stage_board() -> None:
    run_git(["add", "-A", str(BOARD_DIR.relative_to(REPO_ROOT))])


def load_task(path: Path) -> dict[str, Any]:
    content = path.read_text(encoding="utf-8")
    parts = re.split(r"^---$", content, flags=re.MULTILINE)
    if len(parts) < 3:
        raise ValueError(
            f"Invalid task file format in {path}. Missing YAML preamble or body."
        )

    metadata = yaml.safe_load(parts[1]) or {}
    body = parts[2].lstrip("\n")
    return {"metadata": metadata, "body": body, "full_content": content}


def save_task(path: Path, metadata: dict[str, Any], body: str) -> None:
    yaml_str = render_metadata(metadata)
    new_content = f"---\n{yaml_str}\n---\n\n{body.rstrip()}\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new_content, encoding="utf-8")


def get_task_path(task_id: str) -> Path | None:
    matches: list[Path] = []
    for path in BOARD_DIR.rglob("*.md"):
        if path.name == "status_board_protocol.md":
            continue
        try:
            metadata = load_task(path)["metadata"]
        except Exception:
            continue
        if metadata.get("id") == task_id:
            matches.append(path)

    if not matches:
        return None
    if len(matches) > 1:
        raise RuntimeError(
            f"Task {task_id} exists in multiple locations: {', '.join(str(p) for p in matches)}"
        )
    return matches[0]


def ensure_task_namespace(task_id: str) -> None:
    if not task_id.startswith("TASK-"):
        raise ValueError("Board tasks must use the TASK namespace (e.g. TASK-0001).")
    # Enforce exactly 4 digits after "TASK-"
    suffix = task_id[5:]
    if not re.fullmatch(r"\d{4}", suffix):
        raise ValueError(
            f"Invalid task ID '{task_id}'. Must have exactly 4 digits (e.g. TASK-0001)."
        )


def parse_related_docs(raw: str | None) -> list[str] | None:
    if raw is None:
        return None
    try:
        docs = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(
            'related_docs must be a JSON list, e.g. ["REQ-005", "RAD-003"]'
        ) from exc
    if not isinstance(docs, list):
        raise ValueError('related_docs must be a JSON list, e.g. ["REQ-005"]')
    normalized: list[str] = []
    for doc in docs:
        if not isinstance(doc, str) or not doc.strip():
            raise ValueError("related_docs entries must be non-empty strings")
        if doc not in normalized:
            normalized.append(doc)
    return normalized


def merge_related_docs(
    existing: list[str] | None, incoming: list[str] | None
) -> list[str]:
    merged: list[str] = []
    for doc in (existing or []) + (incoming or []):
        if doc not in merged:
            merged.append(doc)
    return merged


def create_task(
    task_id: str, title: str, primary_doc: str, related_docs_raw: str | None = None
) -> None:
    ensure_task_namespace(task_id)
    target_dir = FOLDERS["TO-DO"]
    target_dir.mkdir(parents=True, exist_ok=True)

    if get_task_path(task_id):
        raise RuntimeError(f"Error: Task {task_id} already exists.")

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    related_docs = parse_related_docs(related_docs_raw)
    if related_docs is None:
        related_docs = [primary_doc]
    else:
        related_docs = merge_related_docs([primary_doc], related_docs)

    metadata = {
        "id": task_id,
        "title": title,
        "version": "1.0.0",
        "status": "TO-DO",
        "created": now,
        "updated": now,
        "primary_doc": primary_doc,
        "related_docs": related_docs,
    }
    body = "# Activity Log"
    path = target_dir / f"{task_id}-{slugify(title)}.md"
    if path.exists():
        raise RuntimeError(f"Error: File {path} already exists.")

    save_task(path, metadata, body)
    stage_board()
    run_git(["commit", "-m", f"chore: create task {task_id}"])
    print(f"✅ Task {task_id} created in .board/to-do/")


def transition_task(
    task_id: str,
    new_status: str,
    actor: str,
    message: str,
    related_docs_raw: str | None = None,
) -> None:
    old_path = get_task_path(task_id)
    if not old_path:
        raise RuntimeError(f"Error: Task {task_id} not found.")

    new_status = new_status.upper()
    if new_status not in VALID_STATUSES:
        raise RuntimeError(
            f"Error: Invalid status '{new_status}'. Valid statuses: {sorted(VALID_STATUSES)}"
        )

    task_data = load_task(old_path)
    metadata = task_data["metadata"]
    body = task_data["body"]
    now_dt = datetime.now()

    metadata["status"] = new_status
    metadata["updated"] = now_dt.strftime("%Y-%m-%d %H:%M:%S")

    incoming_related = parse_related_docs(related_docs_raw)
    if incoming_related is not None:
        metadata["related_docs"] = merge_related_docs(
            metadata.get("related_docs", []), incoming_related
        )

    timestamp = now_dt.strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] - [{actor}] - {message}\n"
    new_body = body.rstrip("\n") + "\n" + log_entry

    new_dir = FOLDERS[new_status]
    new_dir.mkdir(parents=True, exist_ok=True)
    new_path = new_dir / old_path.name

    if old_path != new_path:
        run_git(
            [
                "mv",
                str(old_path.relative_to(REPO_ROOT)),
                str(new_path.relative_to(REPO_ROOT)),
            ]
        )

    save_task(new_path, metadata, new_body)
    stage_board()
    run_git(["commit", "-m", f"chore: transition {task_id} to {new_status}"])
    print(f"✅ Task {task_id} transitioned to {new_status}.")


def log_event(task_id: str, actor: str, message: str) -> None:
    path = get_task_path(task_id)
    if not path:
        raise RuntimeError(f"Error: Task {task_id} not found.")

    task_data = load_task(path)
    metadata = task_data["metadata"]
    body = task_data["body"]

    metadata["updated"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] - [{actor}] - {message}\n"
    new_body = body.rstrip("\n") + "\n" + log_entry

    save_task(path, metadata, new_body)
    stage_board()
    run_git(["commit", "-m", f"chore: log event for {task_id}"])
    print(f"✅ Logged event for {task_id}.")


def update_task(
    task_id: str,
    title: str | None = None,
    primary_doc: str | None = None,
    related_docs_raw: str | None = None,
) -> None:
    path = get_task_path(task_id)
    if not path:
        raise RuntimeError(f"Error: Task {task_id} not found.")

    task_data = load_task(path)
    metadata = task_data["metadata"]
    body = task_data["body"]
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if title:
        metadata["title"] = title

    if primary_doc:
        metadata["primary_doc"] = primary_doc

    incoming_related = parse_related_docs(related_docs_raw)
    if incoming_related is not None:
        metadata["related_docs"] = merge_related_docs(
            metadata.get("related_docs", []), incoming_related
        )

    metadata["updated"] = now

    new_path = path
    if title:
        new_path = path.with_name(f"{task_id}-{slugify(title)}.md")
        if new_path != path and new_path.exists():
            raise RuntimeError(f"Error: File {new_path} already exists.")
        if new_path != path:
            run_git(
                [
                    "mv",
                    str(path.relative_to(REPO_ROOT)),
                    str(new_path.relative_to(REPO_ROOT)),
                ]
            )

    save_task(new_path, metadata, body)
    stage_board()
    run_git(["commit", "-m", f"chore: update task {task_id}"])
    print(f"✅ Updated task {task_id}.")


def main() -> None:
    if len(sys.argv) == 1 or sys.argv[1] in ["-h", "--help"]:
        print("Manage Status Board tasks.")
        print("\nUsage Patterns:")
        print(
            "  create <id> <title> --primary-doc <REQ-or-BUG-ID> [--related-docs '[\"REQ-0001\"]']"
        )
        print(
            "  transition <id> <STATUS> --actor <name> --message <msg> [--related-docs '[\"ID-001\"]']"
        )
        print("  log <id> --actor <name> --message <msg>")
        print(
            "  update <id> [--title <new_title>] [--primary-doc <new_doc_id>] [--related-docs '[\"ID-001\"]']"
        )
        print(
            "\nUse 'uv run scripts/board_utils.py <command> --help' for detailed command information."
        )
        return

    parser = argparse.ArgumentParser(description="Manage Status Board tasks.")
    subparsers = parser.add_subparsers(dest="command")

    create_p = subparsers.add_parser("create")
    create_p.add_argument("id", help="Task ID (e.g., TASK-0001)")
    create_p.add_argument("title", help="Task title")
    create_p.add_argument(
        "--primary-doc", required=True, help="The corresponding REQ or BUG document ID"
    )
    create_p.add_argument(
        "--related-docs",
        help='JSON list of related document IDs, e.g. ["REQ-005", "RAD-003"]',
    )

    trans_p = subparsers.add_parser("transition")
    trans_p.add_argument("id", help="Task ID")
    trans_p.add_argument("status", help="New status")
    trans_p.add_argument(
        "--actor", required=True, help="Who is performing the transition"
    )
    trans_p.add_argument("--message", required=True, help="Reason for transition")
    trans_p.add_argument(
        "--related-docs",
        help='JSON list of related document IDs, e.g. ["RAD-003", "FEAT-007"]',
    )

    log_p = subparsers.add_parser("log")
    log_p.add_argument("id", help="Task ID")
    log_p.add_argument("--actor", required=True, help="Who is logging the event")
    log_p.add_argument("--message", required=True, help="The log message")

    update_p = subparsers.add_parser("update")
    update_p.add_argument("id", help="Task ID")
    update_p.add_argument("--title", help="Optional task title update")
    update_p.add_argument(
        "--primary-doc", help="Optional primary source document ID update"
    )
    update_p.add_argument(
        "--related-docs",
        help='JSON list of related document IDs, e.g. ["REQ-005", "REVIEW-010"]',
    )

    args = parser.parse_args()

    try:
        if args.command == "create":
            create_task(args.id, args.title, args.primary_doc, args.related_docs)
        elif args.command == "transition":
            transition_task(
                args.id, args.status, args.actor, args.message, args.related_docs
            )
        elif args.command == "log":
            log_event(args.id, args.actor, args.message)
        elif args.command == "update":
            update_task(args.id, args.title, args.primary_doc, args.related_docs)
        else:
            parser.print_help()
    except (RuntimeError, ValueError, yaml.YAMLError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
