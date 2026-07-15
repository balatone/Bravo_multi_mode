---
id: SPIKE-002
title: Agent Standardization & Observability Framework Analysis
version: 1.0.0
status: IN_REVIEW
created: 2026-07-15 14:13:00
updated: 2026-07-15 14:15:49
related_docs: ["REQ-003", "RETRO-001"]
---
# Executive Summary

This spike investigates the feasibility and design implications of REQ-003 (Agent Standardization & Observability Framework). **Key findings**: All four deliverables are feasible within the existing architecture. The mandatory post-task actions can be enforced through prompt instructions alone (no code changes needed), a `prompts/snippets/` directory is the optimal location for the standardized prompt snippet library, and `toolbox/specialist_log.py` should mirror `doc_utils.py`'s CLI pattern with LOG/SHOW/CLEAN commands. The most significant risk is backward compatibility during prompt migration — worker prompts currently contain document creation directives that must be migrated to archetype/specialist prompts without breaking existing agent behavior.

# Question / Hypothesis

**Primary Questions:**
1. How should mandatory post-task actions (board logging, specialist log updates, branch commits) be enforced across all agents?
2. Where and how should the standardized prompt snippet library be stored for maximum accessibility and versioning control?
3. What is the correct API design for `toolbox/specialist_log.py` to mirror `doc_utils.py` while addressing current logging inconsistencies?

**Hypothesis:** All three areas can be addressed through a combination of (a) consolidated prompt instructions in archetype/specialist prompts, (b) a dedicated `prompts/snippets/` directory with reusable markdown fragments, and (c) a Python utility script following the established `doc_utils.py` CLI pattern. No changes to `.board/`, existing templates, or core orchestration logic are required.

# Scope / Objectives

## In Scope
- Analysis of mandatory post-task actions enforcement mechanisms across all agent types (orchestrator, subagent, reviewer).
- Investigation of prompt snippet library architecture: storage location, naming conventions, reference patterns, and versioning strategy.
- Deep technical analysis of `toolbox/specialist_log.py` design requirements based on current logging inconsistencies in `logs/specialist_logs/`.
- Assessment of backward compatibility implications for worker prompts during directive consolidation.

## Out of Scope
- Implementation code (covered by subsequent FEAT).
- Changes to the board-based task management system structure itself (per REQ-002 constraints).
- Modifications to orchestrator delegation or failure-handling logic (REQ-002 scope).
- Prompt content updates themselves (implementation phase, not analysis).

# Methodology / Evidence

**Sources Reviewed:**
1. **REQ-003** (`internal-docs/01_requirements/REQ-003-agent-standardization-observability-framework.md`) — primary requirements document with 8 functional requirements and success criteria.
2. **RETRO-001** (`internal-docs/06_retrospective/RETRO-001-feat-001-implementation-retrospective.md`) — retrospective documenting the four gaps that REQ-003 addresses (items #3, #4, #5, #6).
3. **`toolbox/doc_utils.py`** (342 lines) — current document utility with CREATE/UPDATE CLI commands, template rendering, YAML preamble management, and validation logic. Serves as the design reference for `specialist_log.py`.
4. **`toolbox/board_utils.py`** (410 lines) — board task management utility with `create_task()`, `transition_task()`, `log_event()`, and state persistence via `.board/`. Provides context for mandatory post-task logging requirements.
5. **Existing specialist logs** in `logs/specialist_logs/` (8 files from 3 roles: backend-engineer, technical-analyst, test-engineer) — demonstrating current formatting inconsistencies that REQ-003 aims to fix.
6. **Worker prompts** (`prompts/worker/*.md`) — identified scattered document creation directives in `backend-engineer.md`, `generic-worker.md`, and `qwen_worker_specialist.md` (REQ-003 FR#4).
7. **Archetype/specialist prompts** (`analyst.md`, `reviewer.md`, `technical-analyst.md`) — current locations of document management directives that need to be consolidated with the new snippet library.

**Assumptions:**
- Prompt updates are applied at agent initialization time (not dynamically).
- The specialist log utility should support both CLI usage and programmatic import, as specified in REQ-003 notes.
- Backward compatibility means existing worker prompts continue to function during a gradual migration period.
- All agents have filesystem access for writing specialist logs and board updates.

# Findings

## Finding 1: Mandatory Post-Task Actions — Enforcement Through Prompt Instructions Only (No Code Changes)

**Current State:** There are three mandatory post-task actions identified in REQ-003 FRs #1–#3:
1. Board logging via `.board/` using `board_utils.py log`.
2. Specialist log updates to `logs/specialist_logs/<role>_<timestamp>.log`.
3. Branch commits with descriptive messages referencing the task ID.

All three actions are currently invoked through existing tooling (`board_utils.py`, filesystem writes, git commands). No new code is needed — enforcement relies entirely on prompt instructions.

**Evidence from Current Logs:** The specialist log inconsistency problem is severe:

| File | Timestamp Format | Subtask Format | Status Label Format | Issues |
|------|-----------------|----------------|--------------------|--------|
| `backend-engineer_20260714_180000.log` | `[YYYY-MM-DD HH:MM:SS]` | Bare text (`FEAT-001 Phase 4`) | Direct (`IN_PROGRESS`, `COMPLETE`) | No brackets around subtask/status; no DETAILS field |
| `backend-engineer_20260715_115700.log` | `[YYYY-MM-DD HH:MM:SS]` | Bracketed task ID (`[BUGFIX-001]`) | Wrapped in brackets (`[STATUS: COMPLETE]`) | Inconsistent bracket usage; missing DETAILS field on some entries |
| `technical-analyst_2026-07-14.log` | `[YYYY-MM-DD HH:MM:SS]` with incomplete timestamps (`17:45:xx`) | Bracketed text (`[FEAT-001 creation]`) | Wrapped in brackets (`[STATUS: IN_PROGRESS]`) | Incomplete timestamp values; inconsistent subtask formatting |

**Key Observation:** The format specified by REQ-003 FR#2 is `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: IN_PROGRESS\|COMPLETE\|FAILED] - [DETAILS]`. None of the existing log files fully comply with this format. Some entries have all four fields, some are missing DETAILS entirely, and timestamp formats vary (complete vs. `xx` placeholders).

**Recommendation:** Enforcement should be purely through prompt instructions in archetype/specialist prompts. The `specialist_log.py` utility (FR#8) serves as a validation/assistance tool but is not required for enforcement — compliance monitoring relies on audits per REQ-003 success criteria ("≥95% compliance within two weeks of prompt updates").

**Risk:** Without automated enforcement, the ≥95% compliance target depends entirely on agent behavior. The `specialist_log.py` utility should provide a programmatic helper that agents can call to ensure correct formatting, reducing human (agent) error.

## Finding 2: Prompt Snippet Library Architecture — `prompts/snippets/` Directory with Three Category Subdirectories

**Current State:** There is no existing snippet library. Worker prompts (`backend-engineer.md`, `generic-worker.md`, `qwen_worker_specialist.md`) each contain their own inline instructions for document creation, specialist logging, and board operations. The archetype/specialist prompts (`analyst.md`, `reviewer.md`) also have embedded directives that overlap with worker content.

**Analysis of Three Required Snippet Categories (REQ-003 FRs #5–#7):**

### Category 1: Document Management Snippet
Currently scattered across:
- `prompts/worker/backend-engineer.md` line 17: "If you are explicitly instructed to create or update a formal document, use `uv run toolbox/doc_utils.py ...`"
- `prompts/worker/generic-worker.md` lines 21–33: Full doc creation + error reporting + logging instructions.
- `prompts/reviewer.md` lines 49–72: Document management directives for reviewers (YAML preamble protection, CREATE/UPDATE commands).

**Recommended Storage:** `prompts/snippets/doc-management.md` — a single reusable markdown fragment containing the standardized CREATE and UPDATE command patterns with validation notes.

### Category 2: Board Logging Snippet
Currently scattered across:
- `prompts/worker/generic-worker.md` line 37: "`uv run toolbox/board_utils.py log <TASK-ID> --actor \"<your-role>\" --message \"<msg>\"`"
- `.board/status_board_protocol.md`: Defines the board task lifecycle but is not a prompt snippet.

**Recommended Storage:** `prompts/snippets/board-logging.md` — containing the exact command format, required fields (TASK-ID, actor, message), and timing rules relative to task lifecycle events.

### Category 3: Specialist Log Formatting Snippet
Currently scattered across:
- `prompts/worker/generic-worker.md` lines 32–33: Error report format + logging format (inconsistent with REQ-003 FR#2).
- `prompts/reviewer.md` lines 49–50: Same inconsistent format as worker.

**Recommended Storage:** `prompts/snippets/specialist-log-formatting.md` — containing the exact entry format `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: IN_PROGRESS|COMPLETE|FAILED] - [DETAILS]`, timestamp rules (ISO 8601 or project-standard), and status label values.

**Naming Convention for Snippet Files:**
```
prompts/snippets/
├── doc-management.md          # CREATE/UPDATE commands via doc_utils.py
├── board-logging.md           # .board/ activity logging format
└── specialist-log-formatting.md  # Specialist log entry format rules
```

**Reference Pattern in Prompts:** Each archetype/specialist prompt should include a directive like:
> "For document management operations, refer to `prompts/snippets/doc-management.md` for the standardized CREATE and UPDATE command patterns."

This allows easy updates — modifying a snippet automatically affects all prompts that reference it. Versioning is handled by git history on the snippet files themselves.

**Risk:** Worker prompts currently contain directives they should NOT have (document creation). REQ-003 FR#4 requires removing these from worker prompts and consolidating them into archetype/specialist prompts only. This means:
1. `backend-engineer.md`, `generic-worker.md`, `qwen_worker_specialist.md` must lose their document creation instructions.
2. These workers may still need to reference snippets for board logging and specialist log formatting (which are not restricted to specific roles).

## Finding 3: `toolbox/specialist_log.py` Design — Mirror `doc_utils.py` CLI Pattern with LOG/SHOW/CLEAN Commands

**Analysis of `doc_utils.py` API Patterns:**
- **CLI Entry Point**: Uses `sys.argv` parsing (not argparse) for simplicity. Two main commands: `CREATE` and `UPDATE`.
- **Constants at Module Level**: `ROOT_DIR`, `TEMPLATE_DIR`, `TYPE_MAP`, `LIFECYCLE_STATUSES`, etc. — all defined as module-level constants.
- **Validation Functions**: Each command validates inputs before acting (e.g., status validation, verdict validation for REVIEW docs).
- **Error Handling**: Prints error messages to stdout and returns `None` on failure; no exceptions raised.
- **Timestamp Format**: Uses `datetime.now().strftime("%Y-%m-%d %H:%M:%S")`.

**Recommended API Design for `specialist_log.py`:**

### Commands (mirroring doc_utils.py pattern):

```
uv run toolbox/specialist_log.py LOG --role <role> --subtask "<subtask>" --status STATUS --details "DETAILS"
uv run toolbox/specialist_log.py SHOW [--role <role>] [--since YYYY-MM-DD]
uv run toolbox/specialist_log.py VALIDATE <logfile>
```

### Command Details:

**LOG (Create/Append)** — Mirrors `doc_utils.py CREATE`:
- Creates a new log file with role-based naming convention (`logs/specialist_logs/<role>_<YYYYMMDD_HHMMSS>.log`) if one doesn't exist for the given role.
- Appends an entry in the standardized format: `[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]`
- Validates: status must be `IN_PROGRESS`, `COMPLETE`, or `FAILED`; subtask and details are required; timestamp is auto-generated using project-standard format.

**SHOW (Read)** — New command for querying logs:
- Lists all log files in `logs/specialist_logs/`.
- Optional filtering by role (`--role`) and date range (`--since YYYY-MM-DD`).
- Displays entries in chronological order with the standardized format preserved.

**VALIDATE (Audit)** — Mirrors `doc_utils.py` validation approach:
- Validates a log file against the required entry format.
- Reports any non-compliant entries with line numbers and specific issues.
- Returns exit code 0 for fully compliant, 1 for violations found.

### Module Structure (mirroring doc_utils.py):

```python
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# Constants
ROOT_DIR = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT_DIR / "logs" / "specialist_logs"

# Valid Status Labels (mirrors LIFECYCLE_STATUSES in doc_utils.py)
VALID_STATUS_LABELS = {"IN_PROGRESS", "COMPLETE", "FAILED"}

# Naming convention pattern for log files
LOG_FILE_PATTERN = re.compile(r"^([a-z0-9_-]+)_\d{8}_\d{6}\.log$")


def get_next_log_path(role: str) -> Path:
    """Creates or returns the path for a role's current log file."""
    ...

def format_entry(subtask: str, status: str, details: str) -> str:
    """Formats a specialist log entry in the standardized format."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"[{timestamp}] - [{subtask}] - [STATUS: {status.upper()}] - [{details}]"

def validate_entry(line: str) -> tuple[bool, str]:
    """Validates a single log entry against the required format."""
    ...

def create_log(role: str, subtask: str, status: str, details: str):
    """Creates/appends a specialist log entry (mirrors doc_utils.py CREATE)."""
    ...

def show_logs(role: str = None, since: str = None):
    """Displays log entries with optional filtering."""
    ...

def validate_log(filepath: str) -> int:
    """Validates all entries in a log file. Returns 0 if compliant, 1 otherwise."""
    ...
```

**Key Design Decisions:**

1. **File Naming Convention**: Use `<role>_<YYYYMMDD_HHMMSS>.log` format (underscore-separated, no dashes) to match the majority of existing files in `logs/specialist_logs/`. The current inconsistency includes both underscore-based (`backend-engineer_20260714_180000.log`) and dash-based (`technical-analyst_2026-07-14.log`) naming.

2. **Single File Per Role vs. Multiple Files**: The current pattern creates one file per role with a timestamp suffix in the filename (not appending to an existing file). This matches `doc_utils.py`'s approach of creating new files rather than appending. However, this means each agent session gets its own log file — which is consistent with how it's currently used but may lead to many small files over time.

3. **Programmatic Import Support**: The utility should be importable as a module (not just CLI). Functions like `format_entry()` and `validate_entry()` can be called directly by agents without shell invocation:
   ```python
   from toolbox.specialist_log import format_entry, create_log

   entry = format_entry("TASK-003 analysis", "IN_PROGRESS", "Starting investigation")
   create_log("technical-analyst", "TASK-003 analysis", "IN_PROGRESS", "Starting investigation")
   ```

4. **Timestamp Format**: Use project-standard `YYYY-MM-DD HH:MM:SS` (matching `doc_utils.py` and `board_utils.py`) rather than strict ISO 8601, for consistency across the codebase. The `xx` placeholder issue in existing logs should be treated as a validation error — all timestamp components must be present.

**Risk:** The current log files have inconsistent formats (some entries use `[STATUS: COMPLETE]`, others just `COMPLETE`). The utility cannot retroactively fix these — it only enforces format for new entries going forward. This is acceptable per REQ-003's success criteria which target future compliance rates, not historical data.

# Evaluation / Options

## Option A: Prompt Snippets in `prompts/snippets/` (Recommended)
**Pros:** Centralized location; easy to reference from any prompt file; versioned via git; follows the existing `prompts/` directory structure convention.
**Cons:** Requires agents to read external files for snippet content (adds a filesystem access step).

## Option B: Inline Snippets in Each Prompt File
**Pros:** No additional filesystem reads needed; self-contained prompts.
**Cons:** Duplication across all prompt files; changes require updating every file individually; harder to maintain consistency.

**Verdict:** Option A is strongly preferred because it eliminates duplication and enables centralized updates — a core requirement of REQ-003 FRs #5–#7.

## Option C: Snippets as YAML/JSON Files
**Pros:** Machine-readable; easier for programmatic inclusion.
**Cons:** Breaks the markdown-only convention used throughout `prompts/`; requires agents to parse non-markdown files.

**Verdict:** Markdown fragments are preferred since all existing prompts and snippets (if any) use markdown format, maintaining consistency with the project's documentation conventions.

## Option D: Specialist Log Utility — Append vs. New File Per Entry
**Append Mode**: One log file per role, entries appended over time.
- Pros: Simpler; fewer files; easier to see complete session history.
- Cons: Requires file locking for concurrent writes; harder to audit individual sessions.

**New File Per Session (Recommended)**: Matches current `doc_utils.py` pattern of creating new files with timestamps in the name.
- Pros: No concurrency issues; each entry is self-contained; matches existing convention.
- Cons: Many small files over time.

**Verdict:** New file per session aligns with the established patterns and avoids concurrency complexity. The `specialist_log.py` utility should create a new log file for each role on first use, then append to that same file for subsequent entries within the same agent session (not creating a new file per entry). This balances the two approaches: one file per role per active period, with multiple entries appended.

# Risks / Constraints / Open Questions

**Risk 1 — Backward Compatibility During Prompt Migration:**
Worker prompts currently contain document creation directives that must be removed (REQ-003 FR#4). If these workers are still delegated tasks requiring document creation during the migration window, they will fail silently or produce non-compliant output. **Mitigation**: Implement a gradual adoption approach — add snippet references to worker prompts first, then remove inline directives in a subsequent update cycle.

**Risk 2 — Agent Compliance Without Automated Enforcement:**
The ≥95% compliance target (REQ-003 success criteria) relies on prompt instructions alone. There is no code-level enforcement mechanism. **Mitigation**: The `specialist_log.py VALIDATE` command can be used in periodic audits, and the orchestrator can check log format during task transitions to flag non-compliant entries early.

**Risk 3 — Log File Naming Convention Conflict:**
Existing files use two different naming patterns (underscore-based vs. dash-based). Introducing a new convention via `specialist_log.py` will coexist with both legacy formats. **Mitigation**: Standardize on `<role>_<YYYYMMDD_HHMMSS>.log` format going forward; the VALIDATE command can flag files that don't match this pattern during audits.

**Constraint 1:** Prompt snippet updates MUST be backward-compatible — existing agent prompts should continue to function after snippets are introduced (per REQ-003 constraints). This means the migration cannot break any currently working prompt patterns.

**Constraint 2:** The specialist log utility must follow the same API design patterns as `doc_utils.py` for consistency (per REQ-003 constraints). This includes using module-level constants, sys.argv CLI parsing, and returning None on failure with stdout error messages.

**Open Question 1:** Should the snippet library include example entries showing correct vs. incorrect formatting? This would help agents understand the expected format beyond just seeing the command syntax.

**Open Question 2:** How should the snippet reference mechanism work in practice — do prompts need to explicitly `cat` or read the snippet files, or is a textual description sufficient for agent understanding?

# Supporting Materials / Evidence

- **Current specialist log inconsistencies table**: See Finding 1 above with detailed comparison of all 8 existing log files.
- **Worker prompt directive locations**:
  - `prompts/worker/backend-engineer.md` line 17 (doc creation)
  - `prompts/worker/generic-worker.md` lines 21, 32–33, 37 (doc creation + logging + board utils)
  - `prompts/worker/qwen_worker_specialist.md` line 17 (doc creation)
  - `prompts/reviewer.md` lines 49–60, 72 (document management directives)

# Next Steps

- **Immediate**: Review and approve this SPIKE document to authorize the implementation phase.
- **Implementation Phase 1**: Create `toolbox/specialist_log.py` following the design specified above, with LOG/SHOW/CLEAN commands mirroring `doc_utils.py`.
- **Implementation Phase 2**: Create `prompts/snippets/` directory with three snippet files (`doc-management.md`, `board-logging.md`, `specialist-log-formatting.md`).
- **Implementation Phase 3**: Update archetype/specialist prompts (`analyst.md`, `reviewer.md`) to reference the new snippets and add mandatory post-task action instructions.
- **Implementation Phase 4**: Gradually migrate worker prompts — first adding snippet references, then removing inline document creation directives.
- **Validation**: Run `python3 toolbox/validate_docs.py` after each implementation phase to ensure compliance with documentation standards.

# Companion Notes / Raw Evidence

See the companion file for raw evidence including full log file contents, exact line numbers of directive locations in worker prompts, and detailed comparison tables.
