"""
Delegation utilities for the Lead archetype.

Codifies the Pre-Delegation Checklist and Post-Delegation Verification
into reusable functions. Replaces the manual 7-step process in team-lead.md.

Usage as CLI:
    # Pre-delegation
    uv run toolbox/delegation_utils.py prepare \\
        --doc-type REQ --title "Hello World" --primary-doc REQ-001

    # Post-delegation verification
    uv run toolbox/delegation_utils.py verify \\
        --task-id TASK-0001 --role analyst --specialist business-analyst

Usage as module:
    from toolbox.delegation_utils import prepare_delegation, verify_delegation
"""

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path

# ──────────────────────────────────────────────────────────────
# Paths
# ──────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).resolve().parents[1]
BOARD_DIR = REPO_ROOT / ".board"
LOG_DIR = REPO_ROOT / "logs" / "specialist_logs"

# ──────────────────────────────────────────────────────────────
# Document type → branch creation rules
# ──────────────────────────────────────────────────────────────

# Doc types that stay on the integration branch (no new branch)
INTEGRATION_DOC_TYPES = frozenset({"REQ", "BUG", "RAD", "SPIKE", "DEC", "DSGN"})

# Doc types that auto-create a feature branch if not on one already.
# BUGFIX is NOT here — the Lead manages branch context explicitly:
#   - BUGFIX from REVIEW: reuses existing feat/ branch
#   - BUGFIX from BUG: Lead creates bugfix/ branch before calling prepare
BRANCH_DOC_TYPES = frozenset({"PLAN", "FEAT"})

# Doc types that require a feature branch but do NOT auto-create one.
# The Lead must ensure the correct branch exists before calling prepare.
MANUAL_BRANCH_DOC_TYPES = frozenset({"BUGFIX"})

# ──────────────────────────────────────────────────────────────
# Document type → board status mapping
# ──────────────────────────────────────────────────────────────

DOC_TYPE_TO_STATUS: dict[str, str] = {
    "REQ": "TO-DO",
    "BUG": "TO-DO",
    "RAD": "ANALYSING",
    "SPIKE": "ANALYSING",
    "DEC": "ANALYSING",
    "DSGN": "DESIGNING",
    "PLAN": "PLANNING",
    "FEAT": "PLANNING",
    "BUGFIX": "PLANNING",
    "IMPLEMENTING": "IMPLEMENTING",
    "REVIEWING": "REVIEWING",
    "TESTING": "TESTING",
}

# ──────────────────────────────────────────────────────────────
# Branch prefix by document type
# ──────────────────────────────────────────────────────────────

DOC_TYPE_TO_BRANCH_PREFIX: dict[str, str] = {
    "PLAN": "feat",
    "FEAT": "feat",
    "BUGFIX": "bugfix",
}

# ──────────────────────────────────────────────────────────────
# Feature/bugfix branch prefixes
# ──────────────────────────────────────────────────────────────

FEATURE_BRANCH_PREFIXES = ("feat/", "bugfix/")


# ──────────────────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────────────────


def _run_git(args: list[str]) -> subprocess.CompletedProcess:
    """Run a git command and return the result."""
    return subprocess.run(
        ["git"] + args,
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )


def _run_tool(tool_path: str, args: list[str]) -> subprocess.CompletedProcess:
    """Run a toolbox utility via uv run."""
    return subprocess.run(
        ["uv", "run", tool_path] + args,
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )


def get_current_branch() -> str:
    """Get the current git branch name."""
    result = _run_git(["branch", "--show-current"])
    if result.returncode != 0:
        raise RuntimeError(f"Failed to get current branch: {result.stderr}")
    return result.stdout.strip()


def is_feature_branch(branch: str) -> bool:
    """Check if a branch is a feature or bugfix branch."""
    return branch.startswith(FEATURE_BRANCH_PREFIXES)


def is_integration_branch(branch: str) -> bool:
    """Check if a branch is an integration branch (i.e. not a feature/bugfix branch)."""
    return not is_feature_branch(branch)


def create_branch(branch_name: str, source: str = "HEAD") -> None:
    """Create and checkout a new git branch."""
    result = _run_git(["checkout", "-b", branch_name, source])
    if result.returncode != 0:
        raise RuntimeError(f"Failed to create branch {branch_name}: {result.stderr}")


def branch_exists(branch_name: str) -> bool:
    """Check if a branch already exists."""
    result = _run_git(["branch", "--list", branch_name])
    return bool(result.stdout.strip())


def next_task_id() -> str:
    """Generate the next TASK-XXXX ID based on existing tasks."""
    max_num = 0
    for path in BOARD_DIR.rglob("TASK-*.md"):
        match = re.match(r"TASK-(\d+)", path.name)
        if match:
            num = int(match.group(1))
            max_num = max(max_num, num)
    return f"TASK-{max_num + 1:04d}"


def get_target_status(doc_type: str) -> str:
    """Get the target board status for a document type."""
    doc_type_upper = doc_type.upper()
    if doc_type_upper not in DOC_TYPE_TO_STATUS:
        raise ValueError(
            f"Unknown document type '{doc_type}'. "
            f"Valid types: {sorted(DOC_TYPE_TO_STATUS.keys())}"
        )
    return DOC_TYPE_TO_STATUS[doc_type_upper]


def get_branch_prefix(doc_type: str) -> str | None:
    """Get the branch prefix for a document type, or None if no branch needed."""
    return DOC_TYPE_TO_BRANCH_PREFIX.get(doc_type.upper())


def needs_branch(doc_type: str) -> bool:
    """Check if a document type requires a new branch."""
    return doc_type.upper() in BRANCH_DOC_TYPES


def needs_existing_branch(doc_type: str) -> bool:
    """Check if a document type requires an existing feature branch (no new branch)."""
    return doc_type.upper() in MANUAL_BRANCH_DOC_TYPES


# ──────────────────────────────────────────────────────────────
# Pre-delegation preparation
# ──────────────────────────────────────────────────────────────


@dataclass
class DelegationPrep:
    """Result of prepare_delegation."""

    task_id: str
    branch: str
    status: str
    needs_branch: bool
    existing_branch: bool  # True for BUGFIX — must be on existing feature branch
    branch_created: bool
    task_created: bool

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2)


def prepare_delegation(
    doc_type: str,
    task_id: str | None = None,
    title: str | None = None,
    primary_doc: str | None = None,
    target_status: str | None = None,
    branch_name: str | None = None,
    integration_branch: str | None = None,
    find_existing_task: bool = False,
) -> DelegationPrep:
    """
    Prepare the board and git state before delegating a task.

    Steps:
    1. Verify branch state (integration branch for doc creation, feature branch for impl)
    2. Create branch if needed
    3. Create task if it doesn't exist
    4. Transition task to target status

    Args:
        doc_type: Document type (REQ, BUG, FEAT, etc.)
        task_id: Existing task ID, or None to create a new one
        title: Task title (required if creating new task)
        primary_doc: Primary document ID (e.g. "REQ-001")
        target_status: Override the default status for this doc type
        branch_name: Override the default branch name
        integration_branch: Override the integration branch name

    Returns:
        DelegationPrep with task_id, branch, status, and flags.

    Raises:
        RuntimeError: If branch state is wrong or git operations fail.
    """
    current_branch = get_current_branch()
    doc_type_upper = doc_type.upper()

    # Step 1: Verify branch state
    if doc_type_upper in INTEGRATION_DOC_TYPES:
        # These must be done on an integration branch
        if is_feature_branch(current_branch):
            raise RuntimeError(
                f"On feature branch '{current_branch}'. "
                f"Cannot create {doc_type_upper} documents on a feature branch. "
                f"Switch to an integration branch (main, develop, etc.) first."
            )

    elif doc_type_upper in BRANCH_DOC_TYPES:
        # These require a feature/bugfix branch created from integration
        if is_feature_branch(current_branch):
            # Already on a feature branch — verify it exists
            pass
        elif not is_integration_branch(current_branch):
            raise RuntimeError(
                f"On branch '{current_branch}' which is neither an integration "
                f"branch nor a feature/bugfix branch. Switch to an integration branch first."
            )

    elif doc_type_upper in MANUAL_BRANCH_DOC_TYPES:
        # BUGFIX: must be on an existing feature branch (reuses branch, does not create new)
        if not is_feature_branch(current_branch):
            raise RuntimeError(
                f"On branch '{current_branch}' which is not a feature/bugfix branch. "
                f"BUGFIX work must be done on the existing feature branch for this task. "
                f"Switch to the active feature branch first."
            )
    else:
        raise ValueError(
            f"Unknown document type '{doc_type}'. "
            f"Integration types: {sorted(INTEGRATION_DOC_TYPES)}\n"
            f"Branch types: {sorted(BRANCH_DOC_TYPES)}\n"
            f"Existing branch types: {sorted(MANUAL_BRANCH_DOC_TYPES)}"
        )

    # Step 2: Create branch if needed
    branch_created = False
    if doc_type_upper in BRANCH_DOC_TYPES and not is_feature_branch(current_branch):
        prefix = get_branch_prefix(doc_type_upper)
        if not prefix:
            raise ValueError(f"No branch prefix defined for doc type '{doc_type}'")

        if branch_name is None:
            # Generate: feat/<task-id>-<short-desc> or bugfix/...
            desc = ""
            if title:
                desc = re.sub(r"[^a-zA-Z0-9]+", "-", title.lower()).strip("-")[:40]
            elif task_id:
                desc = task_id.lower()
            elif primary_doc:
                desc = primary_doc.lower()
            desc = desc or "task"

            if task_id:
                branch_name = f"{prefix}/{task_id.lower()}-{desc}"
            else:
                # Will create task_id first
                pass

        if branch_name and not branch_exists(branch_name):
            create_branch(branch_name)
            branch_created = True
            current_branch = branch_name

    # Step 3: Find existing task if requested
    if find_existing_task and task_id is None and primary_doc:
        lookup = find_task_for_doc(primary_doc)
        if lookup.found:
            task_id = lookup.task_id
            print(f"Reusing existing task {task_id} for {primary_doc}")

    # Step 4: Create task if needed
    task_created = False
    if task_id is None:
        task_id = next_task_id()
        task_created = True

        if not title:
            raise ValueError("title is required when creating a new task")
        if not primary_doc:
            raise ValueError("primary_doc is required when creating a new task")

        # Use board_utils to create the task
        result = _run_tool(
            "toolbox/board_utils.py",
            ["create", task_id, title, "--primary-doc", primary_doc],
        )
        if result.returncode != 0:
            raise RuntimeError(f"Failed to create task {task_id}: {result.stderr}")

    # Step 4: Transition task to target status
    if target_status is None:
        target_status = get_target_status(doc_type_upper)

    # Only transition if the task isn't already in that status
    result = _run_tool(
        "toolbox/board_utils.py",
        [
            "transition",
            task_id,
            target_status,
            "--actor",
            "team-lead",
            "--message",
            f"Pre-delegation for {doc_type_upper}: {title or 'task'}",
        ],
    )
    if result.returncode != 0:
        # If the error is about already being in that status, that's ok
        if "already in status" not in result.stderr.lower():
            raise RuntimeError(
                f"Failed to transition {task_id} to {target_status}: {result.stderr}"
            )

    return DelegationPrep(
        task_id=task_id,
        branch=current_branch,
        status=target_status,
        needs_branch=doc_type_upper in BRANCH_DOC_TYPES,
        existing_branch=doc_type_upper in MANUAL_BRANCH_DOC_TYPES,
        branch_created=branch_created,
        task_created=task_created,
    )


# ──────────────────────────────────────────────────────────────
# Post-delegation verification
# ──────────────────────────────────────────────────────────────


@dataclass
class DelegationResult:
    """Result of verify_delegation."""

    ok: bool
    specialist_log_ok: bool
    activity_log_ok: bool
    commits_ok: bool
    errors: list[str] = field(default_factory=list)

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2)


def verify_delegation(
    task_id: str,
    delegated_role: str,
    delegated_specialist: str,
    expected_docs: list[str] | None = None,
) -> DelegationResult:
    """
    Verify that the subagent completed its delegation properly.

    Checks:
    1. Specialist log has a COMPLETE entry from the subagent
    2. Task activity log has an entry from the delegated role
    3. Git working tree is clean (all changes committed)
    4. Expected documents exist (if specified)

    Args:
        task_id: The task ID (e.g. "TASK-0001")
        delegated_role: The role that was delegated (e.g. "analyst")
        delegated_specialist: The specialist that was delegated (e.g. "business-analyst")
        expected_docs: List of document IDs expected to exist

    Returns:
        DelegationResult with pass/fail status and any errors.
    """
    errors: list[str] = []

    # ── Check 1: Specialist log ──────────────────────────────
    specialist_log_ok = False
    if LOG_DIR.exists():
        # Look for log files matching the role
        for log_file in sorted(LOG_DIR.glob(f"*{delegated_role}*.log")):
            content = log_file.read_text(encoding="utf-8")
            if "COMPLETE" in content:
                specialist_log_ok = True
                break

    if not specialist_log_ok:
        errors.append(
            f"No COMPLETE entry found in specialist logs for role '{delegated_role}'. "
            f"The subagent may not have completed its work."
        )

    # ── Check 2: Activity log on task ────────────────────────
    activity_log_ok = False
    result = _run_tool("toolbox/board_utils.py", ["show", task_id])
    if result.returncode == 0:
        task_content = result.stdout
        # Check if the delegated role logged activity
        if (
            f"[{delegated_role}]" in task_content
            or f"[{delegated_specialist}]" in task_content
        ):
            activity_log_ok = True

    if not activity_log_ok:
        errors.append(
            f"No activity log entry from '{delegated_role}' or '{delegated_specialist}' "
            f"on task {task_id}. The subagent may not have logged its work."
        )

    # ── Check 3: Git working tree is clean ───────────────────
    commits_ok = True
    git_status = _run_git(["status", "--porcelain"])
    uncommitted = git_status.stdout.strip()
    if uncommitted:
        commits_ok = False
        errors.append(
            f"Uncommitted changes detected. The subagent did not commit its work:\n{uncommitted}"
        )

    # ── Check 4: Expected documents exist ────────────────────
    if expected_docs:
        docs_dir = REPO_ROOT / "internal-docs"
        for doc_id in expected_docs:
            found = False
            for doc_path in docs_dir.rglob(f"{doc_id}*.md"):
                found = True
                break
            if not found:
                # Also check by searching content
                for doc_path in docs_dir.rglob("*.md"):
                    try:
                        content = doc_path.read_text(encoding="utf-8")
                        if f"id: {doc_id}" in content or doc_id in doc_path.name:
                            found = True
                            break
                    except Exception:
                        pass
                if not found:
                    errors.append(
                        f"Expected document '{doc_id}' not found in internal-docs/."
                    )

    return DelegationResult(
        ok=len(errors) == 0,
        specialist_log_ok=specialist_log_ok,
        activity_log_ok=activity_log_ok,
        commits_ok=commits_ok,
        errors=errors,
    )


# ──────────────────────────────────────────────────────────────
# Task lookup utilities
# ──────────────────────────────────────────────────────────────


@dataclass
class TaskLookupResult:
    """Result of find_task_for_doc."""

    found: bool
    task_id: str | None
    task_path: str | None
    status: str | None
    primary_doc: str | None
    related_docs: list[str] | None

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2)


def find_task_for_doc(doc_id: str) -> TaskLookupResult:
    """
    Find an existing board task associated with a document ID.

    Searches all task files in .board/ for a task whose primary_doc or
    related_docs contains the given document ID.

    Args:
        doc_id: The document ID to search for (e.g. "REQ-001", "FEAT-002").

    Returns:
        TaskLookupResult with found status and task details.
    """
    # Search all task files in .board/
    for path in BOARD_DIR.rglob("TASK-*.md"):
        try:
            content = path.read_text(encoding="utf-8")
            # Check primary_doc and related_docs in the YAML preamble
            if f"primary_doc: {doc_id}" in content or f'"{doc_id}"' in content:
                # Extract task ID from filename
                task_id_match = re.match(r"TASK-(\d+)", path.name)
                if task_id_match:
                    task_id = f"TASK-{task_id_match.group(1)}"
                    # Get more details from the task file
                    status = None
                    primary_doc = None
                    related_docs = None
                    for line in content.split("\n"):
                        line = line.strip()
                        if line.startswith("status:"):
                            status = line.split(":", 1)[1].strip()
                        elif line.startswith("primary_doc:"):
                            primary_doc = line.split(":", 1)[1].strip()
                        elif line.startswith("related_docs:"):
                            try:
                                related_docs = json.loads(line.split(":", 1)[1].strip())
                            except (json.JSONDecodeError, ValueError):
                                related_docs = []

                    return TaskLookupResult(
                        found=True,
                        task_id=task_id,
                        task_path=str(path),
                        status=status,
                        primary_doc=primary_doc,
                        related_docs=related_docs or [],
                    )
        except Exception:
            continue

    return TaskLookupResult(
        found=False,
        task_id=None,
        task_path=None,
        status=None,
        primary_doc=None,
        related_docs=None,
    )


# ──────────────────────────────────────────────────────────────
# CLI interface
# ──────────────────────────────────────────────────────────────


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Delegation utilities for the Lead archetype.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # ── prepare ──────────────────────────────────────────────
    prep_parser = subparsers.add_parser(
        "prepare",
        help="Pre-delegation: check branch, create task, transition status",
    )
    prep_parser.add_argument(
        "--doc-type",
        required=True,
        help="Document type (REQ, BUG, FEAT, PLAN, BUGFIX, etc.)",
    )
    prep_parser.add_argument(
        "--task-id",
        default=None,
        help="Existing task ID, or omit to auto-generate",
    )
    prep_parser.add_argument(
        "--title",
        default=None,
        help="Task title (required when creating new task)",
    )
    prep_parser.add_argument(
        "--primary-doc",
        default=None,
        help="Primary document ID (required when creating new task)",
    )
    prep_parser.add_argument(
        "--target-status",
        default=None,
        help="Override the default target status",
    )
    prep_parser.add_argument(
        "--branch-name",
        default=None,
        help="Override the default branch name",
    )
    prep_parser.add_argument(
        "--integration-branch",
        default=None,
        help="Override the integration branch name",
    )
    prep_parser.add_argument(
        "--json",
        action="store_true",
        help="Output as JSON",
    )
    prep_parser.add_argument(
        "--find-existing-task",
        action="store_true",
        help="Search for an existing task before creating a new one",
    )

    # ── verify ───────────────────────────────────────────────
    verify_parser = subparsers.add_parser(
        "verify",
        help="Post-delegation: verify specialist log, activity log, commits",
    )
    verify_parser.add_argument(
        "--task-id",
        required=True,
        help="Task ID to verify",
    )
    verify_parser.add_argument(
        "--role",
        required=True,
        help="Delegated role (e.g. analyst, worker, reviewer)",
    )
    verify_parser.add_argument(
        "--specialist",
        required=True,
        help="Delegated specialist (e.g. business-analyst, backend-engineer)",
    )
    verify_parser.add_argument(
        "--expected-docs",
        default=None,
        help="Comma-separated list of expected document IDs",
    )
    verify_parser.add_argument(
        "--json",
        action="store_true",
        help="Output as JSON",
    )

    # ── find-task ───────────────────────────────────────────
    find_parser = subparsers.add_parser(
        "find-task",
        help="Find an existing board task associated with a document ID",
    )
    find_parser.add_argument(
        "--doc-id",
        required=True,
        help="Document ID to search for (e.g. REQ-001, FEAT-002)",
    )
    find_parser.add_argument(
        "--json",
        action="store_true",
        help="Output as JSON",
    )

    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    if args.command == "prepare":
        try:
            prep = prepare_delegation(
                doc_type=args.doc_type,
                task_id=args.task_id,
                title=args.title,
                primary_doc=args.primary_doc,
                target_status=args.target_status,
                branch_name=args.branch_name,
                integration_branch=args.integration_branch,
                find_existing_task=args.find_existing_task,
            )
            if args.json:
                print(prep.to_json())
            else:
                print(f"✅ Task: {prep.task_id}")
                print(f"   Branch: {prep.branch}")
                print(f"   Status: {prep.status}")
                print(f"   Branch created: {prep.branch_created}")
                print(f"   Task created: {prep.task_created}")
        except (RuntimeError, ValueError) as e:
            print(f"❌ Pre-delegation failed: {e}", file=sys.stderr)
            sys.exit(1)

    elif args.command == "verify":
        expected_docs = None
        if args.expected_docs:
            expected_docs = [d.strip() for d in args.expected_docs.split(",")]

        result = verify_delegation(
            task_id=args.task_id,
            delegated_role=args.role,
            delegated_specialist=args.specialist,
            expected_docs=expected_docs,
        )

        if args.json:
            print(result.to_json())
        else:
            if result.ok:
                print("✅ Post-delegation verification passed.")
            else:
                print("❌ Post-delegation verification failed:")
                for err in result.errors:
                    print(f"   • {err}")
                sys.exit(1)

    elif args.command == "find-task":
        result = find_task_for_doc(doc_id=args.doc_id)

        if args.json:
            print(result.to_json())
        else:
            if result.found:
                print(f"✅ Found task: {result.task_id}")
                print(f"   Path: {result.task_path}")
                print(f"   Status: {result.status}")
                print(f"   Primary doc: {result.primary_doc}")
                if result.related_docs:
                    print(f"   Related docs: {result.related_docs}")
            else:
                print(f"❌ No task found for document '{args.doc_id}'.")


if __name__ == "__main__":
    main()
