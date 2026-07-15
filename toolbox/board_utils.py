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


# ──────────────────────────────────────────────────────────────
# Stall Detection and Recovery Protocol (FEAT-003)
# ──────────────────────────────────────────────────────────────

# Stall cause constants
STALL_CAUSE_MAX_TURNS = "MAX_TURNS_EXHAUSTED"
STALL_CAUSE_UNRESPONSIVE = "UNRESPONSIVE_TIMEOUT"
STALL_CAUSE_ERROR = "ERROR"

# Recovery path constants
RECOVERY_MANUAL_RESUME = "MANUAL_RESUME"
RECOVERY_RE_DELEGATION = "RE_DELEGATION"

# Default unresponsiveness timeout in seconds (15 minutes per REQ-002)
DEFAULT_UNRESPONSIVE_TIMEOUT_SECONDS = 15 * 60


class StallResult:
    """Result of a stall detection check."""

    def __init__(
        self,
        is_stalled: bool,
        cause: str | None = None,
        details: str = "",
    ):
        self.is_stalled = is_stalled
        self.cause = cause
        self.details = details

    def to_dict(self) -> dict[str, Any]:
        return {
            "is_stalled": self.is_stalled,
            "cause": self.cause,
            "details": self.details,
        }

    def __repr__(self) -> str:
        return (
            f"StallResult(is_stalled={self.is_stalled}, "
            f"cause={self.cause!r}, details={self.details!r})"
        )


def max_turns_tracker(
    subagent_id: str,
    current_turns: int,
    max_turns: int,
) -> StallResult:
    """
    Track subagent turn count against configured max_turns threshold.

    Per FEAT-003 Phase A: The orchestrator tracks each subagent's turn count
    against its configured max_turns (from get_delegation_params.py).
    When the limit is reached, a stall event is raised with cause = MAX_TURNS_EXHAUSTED.

    Args:
        subagent_id: The unique identifier of the subagent being tracked.
        current_turns: The current number of turns executed by the subagent.
        max_turns: The configured maximum number of turns allowed.

    Returns:
        StallResult indicating whether a stall was detected and the cause.

    Raises:
        ValueError: If current_turns or max_turns is negative.
    """
    if current_turns < 0:
        raise ValueError(f"current_turns must be non-negative, got {current_turns}")
    if max_turns <= 0:
        raise ValueError(f"max_turns must be positive, got {max_turns}")

    if current_turns >= max_turns:
        return StallResult(
            is_stalled=True,
            cause=STALL_CAUSE_MAX_TURNS,
            details=(
                f"Subagent {subagent_id} reached max_turns limit: "
                f"{current_turns}/{max_turns} turns"
            ),
        )

    return StallResult(
        is_stalled=False,
        details=(
            f"Subagent {subagent_id} within turn limit: "
            f"{current_turns}/{max_turns} turns"
        ),
    )


def unresponsiveness_monitor(
    subagent_id: str,
    last_activity_timestamp: datetime,
    timeout_seconds: float | None = None,
) -> StallResult:
    """
    Monitor subagent unresponsiveness based on last activity timestamp.

    Per FEAT-003 Phase A: A configurable idle timeout (default 15 minutes
    per REQ-002) detects when no activity occurs for a subagent session.
    When exceeded, stall event raised with cause = UNRESPONSIVE_TIMEOUT.

    Args:
        subagent_id: The unique identifier of the subagent being monitored.
        last_activity_timestamp: The timestamp of the subagent's last known activity.
        timeout_seconds: Timeout threshold in seconds. Defaults to 15 minutes
                         (DEFAULT_UNRESPONSIVE_TIMEOUT_SECONDS).

    Returns:
        StallResult indicating whether a stall was detected and the cause.

    Raises:
        ValueError: If timeout_seconds is non-positive.
    """
    if timeout_seconds is not None and timeout_seconds <= 0:
        raise ValueError(f"timeout_seconds must be positive, got {timeout_seconds}")

    effective_timeout = (
        timeout_seconds
        if timeout_seconds is not None
        else DEFAULT_UNRESPONSIVE_TIMEOUT_SECONDS
    )

    now = datetime.now()
    elapsed = (now - last_activity_timestamp).total_seconds()

    if elapsed >= effective_timeout:
        return StallResult(
            is_stalled=True,
            cause=STALL_CAUSE_UNRESPONSIVE,
            details=(
                f"Subagent {subagent_id} unresponsive for {elapsed:.0f}s "
                f"(threshold: {effective_timeout:.0f}s)"
            ),
        )

    return StallResult(
        is_stalled=False,
        details=(
            f"Subagent {subagent_id} active: last activity {elapsed:.0f}s ago "
            f"(threshold: {effective_timeout:.0f}s)"
        ),
    )


def classify_stall(stall_cause: str) -> str:
    """
    Classify a stall cause and return the appropriate recovery path.

    Per FEAT-003 Phase B: Maps stall causes to recovery paths:
    - MAX_TURNS_EXHAUSTED -> MANUAL_RESUME
    - UNRESPONSIVE_TIMEOUT -> MANUAL_RESUME
    - Any error/unknown cause -> RE_DELEGATION

    Args:
        stall_cause: The cause of the stall (e.g., MAX_TURNS_EXHAUSTED).

    Returns:
        Recovery path string (MANUAL_RESUME or RE_DELEGATION).
    """
    if stall_cause in (STALL_CAUSE_MAX_TURNS, STALL_CAUSE_UNRESPONSIVE):
        return RECOVERY_MANUAL_RESUME

    return RECOVERY_RE_DELEGATION


def log_stall_event(
    subagent_id: str,
    cause: str,
    recovery_path: str,
    task_id: str | None = None,
    details: str = "",
    repo_root: Path | None = None,
) -> Path:
    """
    Log a stall event to the orchestrator specialist log file.

    Per FEAT-003 Phase C: All stall events logged to
    logs/specialist_logs/orchestrator_<timestamp>.log following format:
    [TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: FAILED] - [DETAILS]

    Args:
        subagent_id: The ID of the subagent that stalled.
        cause: The cause of the stall (e.g., MAX_TURNS_EXHAUSTED).
        recovery_path: The recovery path selected (MANUAL_RESUME or RE_DELEGATION).
        task_id: Optional task ID for logging context.
        details: Additional details about the stall.
        repo_root: Optional repo root override (for testing).

    Returns:
        Path to the log file that was written.
    """
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    root = repo_root if repo_root is not None else REPO_ROOT
    log_dir = root / "logs" / "specialist_logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    log_filename = f"orchestrator_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    log_path = log_dir / log_filename

    task_context = task_id if task_id else "unknown"

    log_line = (
        f"[{timestamp}] - [{task_context}] - [STATUS: FAILED] - "
        f"[Stall detected: subagent={subagent_id}, "
        f"cause={cause}, recovery={recovery_path}"
    )
    if details:
        log_line += f", details={details}"
    log_line += "]\n"

    with log_path.open("a", encoding="utf-8") as f:
        f.write(log_line)

    return log_path


def execute_manual_resume(
    task_id: str,
    subagent_id: str,
    cause: str,
    details: str = "",
    repo_root: Path | None = None,
) -> dict[str, Any]:
    """
    Execute the manual resume recovery path.

    Per FEAT-003 Phase B: For stalls caused by MAX_TURNS_EXHAUSTED or
    UNRESPONSIVE_TIMEOUT, the system routes to manual resume -- preserving
    subagent context and allowing a human operator to continue execution.

    Args:
        task_id: The board task ID to update.
        subagent_id: The ID of the stalled subagent.
        cause: The cause of the stall.
        details: Additional details about the stall.
        repo_root: Optional repo root override (for testing).

    Returns:
        Dict with recovery result details.
    """
    root = repo_root if repo_root is not None else REPO_ROOT

    # Log the stall event
    log_path = log_stall_event(
        subagent_id=subagent_id,
        cause=cause,
        recovery_path=RECOVERY_MANUAL_RESUME,
        task_id=task_id,
        details=details,
        repo_root=root,
    )

    # Update board task status to require manual resume
    try:
        log_event(
            task_id=task_id,
            actor="stall-recovery",
            message=(
                f"MANUAL_RESUME required: subagent {subagent_id} stalled "
                f"(cause: {cause}). Human intervention needed. Log: {log_path.name}"
            ),
        )
    except RuntimeError:
        # Task may not exist on board; still return success for the recovery action
        pass

    return {
        "success": True,
        "recovery_path": RECOVERY_MANUAL_RESUME,
        "task_id": task_id,
        "subagent_id": subagent_id,
        "cause": cause,
        "log_path": str(log_path),
        "message": (
            f"Task {task_id} flagged for MANUAL_RESUME. "
            f"Subagent {subagent_id} stalled (cause: {cause})."
        ),
    }


def execute_re_delegation(
    task_id: str,
    original_subagent_id: str,
    new_subagent_id: str | None = None,
    cause: str = STALL_CAUSE_ERROR,
    details: str = "",
    repo_root: Path | None = None,
) -> dict[str, Any]:
    """
    Execute the re-delegation recovery path.

    Per FEAT-003 Phase B: For stalls caused by unexpected errors/crashes,
    the orchestrator re-delegates the task to another available agent with
    matching role specialization. If no alternative is available, escalation
    to human operator occurs as fallback.

    Args:
        task_id: The board task ID to update.
        original_subagent_id: The ID of the original stalled subagent.
        new_subagent_id: The ID of the new subagent to delegate to.
                         If None, escalates to human operator.
        cause: The cause of the stall.
        details: Additional details about the stall.
        repo_root: Optional repo root override (for testing).

    Returns:
        Dict with recovery result details.
    """
    root = repo_root if repo_root is not None else REPO_ROOT

    # Log the stall event
    log_path = log_stall_event(
        subagent_id=original_subagent_id,
        cause=cause,
        recovery_path=RECOVERY_RE_DELEGATION,
        task_id=task_id,
        details=details,
        repo_root=root,
    )

    if new_subagent_id:
        # Re-delegate to new subagent
        try:
            log_event(
                task_id=task_id,
                actor="stall-recovery",
                message=(
                    f"RE_DELEGATION: task re-delegated from "
                    f"{original_subagent_id} to {new_subagent_id} "
                    f"(cause: {cause}). Log: {log_path.name}"
                ),
            )
        except RuntimeError:
            pass

        return {
            "success": True,
            "recovery_path": RECOVERY_RE_DELEGATION,
            "task_id": task_id,
            "original_subagent_id": original_subagent_id,
            "new_subagent_id": new_subagent_id,
            "cause": cause,
            "log_path": str(log_path),
            "escalated": False,
            "message": (
                f"Task {task_id} re-delegated from {original_subagent_id} "
                f"to {new_subagent_id}."
            ),
        }
    else:
        # No alternative agent available - escalate to human operator
        try:
            log_event(
                task_id=task_id,
                actor="stall-recovery",
                message=(
                    f"ESCALATION: no alternative agent available for "
                    f"{original_subagent_id} (cause: {cause}). "
                    f"Human intervention needed. Log: {log_path.name}"
                ),
            )
        except RuntimeError:
            pass

        return {
            "success": True,
            "recovery_path": RECOVERY_RE_DELEGATION,
            "task_id": task_id,
            "original_subagent_id": original_subagent_id,
            "new_subagent_id": None,
            "cause": cause,
            "log_path": str(log_path),
            "escalated": True,
            "message": (
                f"Task {task_id} escalated to human operator. "
                f"No alternative agent available for {original_subagent_id}."
            ),
        }


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


# Document type to directory mapping (mirrors doc_utils.py TYPE_MAP)
DOC_TYPE_MAP = {
    "REQ": "internal-docs/01_requirements",
    "BUG": "internal-docs/01_requirements",
    "RAD": "internal-docs/02_analysis",
    "SPIKE": "internal-docs/02_analysis",
    "DSGN": "internal-docs/03_design",
    "DEC": "internal-docs/03_design",
    "PLAN": "internal-docs/04_planning/04a_master",
    "FEAT": "internal-docs/04_planning/04b_features",
    "BUGFIX": "internal-docs/04_planning/04b_features",
    "REVIEW": "internal-docs/05_review",
    "RETRO": "internal-docs/06_retrospective",
}

VALID_LIFECYCLE_STATUSES = {
    "DRAFT",
    "IN_REVIEW",
    "APPROVED",
    "SUPERSEDED",
    "DEPRECATED",
    "ARCHIVED",
}


def resolve_document_path(doc_id: str) -> Path | None:
    """
    Resolve a document ID (e.g. 'FEAT-002') to its filesystem path.
    Searches all known document directories for a file matching the ID.
    Returns None if the document is not found.
    """
    # Extract the type prefix (e.g. 'FEAT' from 'FEAT-002')
    match = re.match(r"^([A-Z]+)-\d+", doc_id)
    if not match:
        return None

    doc_type = match.group(1)
    search_dirs: list[Path] = []

    # Use the type map to narrow search if we know the type
    if doc_type in DOC_TYPE_MAP:
        search_dirs = [REPO_ROOT / DOC_TYPE_MAP[doc_type]]
    else:
        # Fallback: search all known directories
        search_dirs = [REPO_ROOT / dir_path for dir_path in DOC_TYPE_MAP.values()]

    for directory in search_dirs:
        if not directory.exists():
            continue
        for filepath in directory.rglob("*.md"):
            try:
                metadata = load_task(filepath)["metadata"]
            except Exception:
                continue
            if metadata.get("id") == doc_id:
                return filepath

    return None


def read_document_preamble(filepath: Path) -> dict[str, Any]:
    """Read and parse the YAML preamble from a document file."""
    content = filepath.read_text(encoding="utf-8")
    parts = re.split(r"^---$", content, flags=re.MULTILINE)
    if len(parts) < 3:
        raise ValueError(
            f"Invalid document format in {filepath}. Missing YAML preamble."
        )
    metadata = yaml.safe_load(parts[1]) or {}
    return metadata


def write_document_preamble(filepath: Path, metadata: dict[str, Any]) -> None:
    """Rewrite the YAML preamble of a document, preserving the body."""
    content = filepath.read_text(encoding="utf-8")
    parts = re.split(r"^---$", content, flags=re.MULTILINE)
    if len(parts) < 3:
        raise ValueError(
            f"Invalid document format in {filepath}. Missing YAML preamble."
        )

    yaml_str = yaml.dump(metadata, default_flow_style=False, sort_keys=False)
    body = parts[2]
    new_content = f"---\n{yaml_str.rstrip()}\n---\n{body}"
    filepath.write_text(new_content, encoding="utf-8")


def _log_auto_approval(
    doc_id: str,
    filepath: Path,
    task_id: str | None,
    was_approved: bool,
    repo_root: Path | None = None,
) -> None:
    """
    Log an auto-approval event to the specialist log file.
    Format: [TIMESTAMP] - [SUBTASK_NAME] - [STATUS] - [DETAILS]

    Args:
        doc_id: The document ID that was processed.
        filepath: The filesystem path of the document.
        task_id: Optional task ID for logging context.
        was_approved: Whether the document was actually approved (vs already approved).
        repo_root: Optional repo root override (for testing).
    """
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    root = repo_root if repo_root is not None else REPO_ROOT
    log_dir = root / "logs" / "specialist_logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    log_filename = f"backend-engineer_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    log_path = log_dir / log_filename

    if was_approved:
        status_label = "INFO"
        detail = f"Auto-approved document {doc_id} ({filepath})"
    else:
        status_label = "INFO"
        detail = f"Document {doc_id} ({filepath}) already approved - no action taken"

    task_context = f"TASK-{task_id}" if task_id else "auto-approval"
    log_line = (
        f"[{timestamp}] - [{task_context}] - [STATUS: {status_label}] - [{detail}]\n"
    )

    with log_path.open("a", encoding="utf-8") as f:
        f.write(log_line)
    print(f"Log written to {log_path}")


def auto_approve_delegation(doc_id: str, task_id: str | None = None) -> dict[str, Any]:
    """
    Auto-approve a target document as part of the delegation process.

    This function reads the target document's YAML preamble, checks if
    its status is not APPROVED, and updates it to APPROVED. This is
    scoped strictly to the delegation context per REQ-002 constraints.

    Args:
        doc_id: The document ID to approve (e.g. 'FEAT-002', 'REQ-001').
        task_id: Optional task ID for logging context (e.g. 'TASK-0002').

    Returns:
        A dict with keys:
            - success (bool): Whether the operation completed without error.
            - doc_id (str): The document ID that was processed.
            - filepath (str | None): Resolved filesystem path, or None if not found.
            - previous_status (str | None): Status before the operation.
            - new_status (str | None): Status after the operation.
            - message (str): Human-readable result description.
            - error (str | None): Error message if success is False.

    Raises:
        ValueError: If doc_id format is invalid.
        RuntimeError: If the document does not exist.
    """
    result: dict[str, Any] = {
        "success": False,
        "doc_id": doc_id,
        "filepath": None,
        "previous_status": None,
        "new_status": None,
        "message": "",
        "error": None,
    }

    # Validate doc_id format
    if not re.match(r"^[A-Z]+-\d+$", doc_id):
        result["error"] = (
            f"Invalid document ID format: '{doc_id}'. "
            "Expected format: TYPE-NNN (e.g. FEAT-002, REQ-001)."
        )
        return result

    # Resolve the document path
    filepath = resolve_document_path(doc_id)
    if filepath is None:
        result["error"] = f"Document not found: '{doc_id}'."
        return result

    result["filepath"] = str(filepath)

    # Read current metadata
    try:
        metadata = read_document_preamble(filepath)
    except Exception as exc:
        result["error"] = f"Failed to read document preamble: {exc}"
        return result

    current_status = metadata.get("status", "").upper()
    result["previous_status"] = current_status

    # Check if already approved (idempotent behavior)
    if current_status == "APPROVED":
        result["success"] = True
        result["new_status"] = "APPROVED"
        result["message"] = f"Document {doc_id} is already APPROVED. No changes made."
        _log_auto_approval(doc_id, filepath, task_id, was_approved=False)
        return result

    # Update status to APPROVED
    metadata["status"] = "APPROVED"
    metadata["updated"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    try:
        write_document_preamble(filepath, metadata)
    except Exception as exc:
        result["error"] = f"Failed to update document: {exc}"
        return result

    stage_board()
    run_git(["commit", "-m", f"chore: auto-approve {doc_id} for delegation"])

    result["success"] = True
    result["new_status"] = "APPROVED"
    result["message"] = (
        f"Document {doc_id} auto-approved. "
        f"Status changed from '{current_status}' to 'APPROVED'."
    )
    _log_auto_approval(doc_id, filepath, task_id, was_approved=True)
    return result


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
