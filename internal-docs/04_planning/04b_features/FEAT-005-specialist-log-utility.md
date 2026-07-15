---
id: FEAT-005
title: Specialist Log Utility Development
version: 1.0.0
status: APPROVED
created: "2026-07-15 17:48:00"
updated: "2026-07-15 18:20:00"
related_docs: ["PLAN-002", "REQ-003", "SPIKE-002"]
---

# Feature Overview

This feature implements `toolbox/specialist_log.py`, a Python CLI utility for creating, querying, and validating specialist log entries. The utility mirrors the established `doc_utils.py` API design pattern (module-level constants, sys.argv CLI parsing, validation functions returning None on failure) while addressing current logging inconsistencies documented in SPIKE-002 Finding 1. It supports three commands: LOG (create/append), SHOW (query/filter), and VALIDATE (audit compliance). This addresses REQ-003 functional requirement #8 (specialist log utility) and provides the programmatic enforcement tool needed to achieve >=95% format compliance within two weeks of deployment.

# Objectives

- Implement `toolbox/specialist_log.py` with LOG, SHOW, and VALIDATE commands mirroring `doc_utils.py` CLI patterns.
- Support both CLI usage (`uv run toolbox/specialist_log.py ...`) and programmatic import (Python module API).
- Enforce standardized log entry format: `[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]`.
- Provide audit capability via VALIDATE command that returns exit code 0 for compliant files, 1 for violations.

# Scope

## In Scope

### Phase A: Core LOG Command (mirrors `doc_utils.py` CREATE)

1. **CLI Interface**: `uv run toolbox/specialist_log.py LOG --role <role> --subtask "<subtask>" --status STATUS --details "DETAILS"`
   - Creates a new log file with role-based naming convention (`logs/specialist_logs/<role>_<YYYYMMDD_HHMMSS>.log`) if one does not exist for the given role.
   - Appends an entry in the standardized format to that file.
   - Validates: status must be `IN_PROGRESS`, `COMPLETE`, or `FAILED`; subtask and details are required fields; timestamp is auto-generated using project-standard format (`YYYY-MM-DD HH:MM:SS`).

2. **Module-Level Constants**: Define constants at module level mirroring `doc_utils.py` style:
   - `ROOT_DIR`: Path to repository root (parent of `toolbox/`).
   - `LOG_DIR`: Path to `logs/specialist_logs/`.
   - `VALID_STATUS_LABELS`: Set containing `{"IN_PROGRESS", "COMPLETE", "FAILED"}`.
   - `LOG_FILE_PATTERN`: Regex pattern for role-based log file naming: `^([a-z0-9_-]+)_\d{8}_\d{6}\.log$`.

3. **Helper Functions**:
   - `get_next_log_path(role)`: Returns the path for a role's current log file, creating it if needed.
   - `format_entry(subtask, status, details)`: Formats an entry as `[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]`.

### Phase B: SHOW Command (New — Query and Filter Logs)

4. **CLI Interface**: `uv run toolbox/specialist_log.py SHOW [--role <role>] [--since YYYY-MM-DD]`
   - Lists all log files in `logs/specialist_logs/`.
   - Optional filtering by role (`--role`) filters to logs for a specific role.
   - Optional date range filtering (`--since YYYY-MM-DD`) shows entries from that date forward.
   - Displays entries in chronological order with the standardized format preserved.

5. **Implementation**: Parse log files, apply filters, and display formatted output. Handle missing directories gracefully (create if needed).

### Phase C: VALIDATE Command (Audit Compliance)

6. **CLI Interface**: `uv run toolbox/specialist_log.py VALIDATE <logfile>`
   - Validates all entries in a specified log file against the required format.
   - Reports non-compliant entries with line numbers and specific issues (e.g., missing DETAILS field, invalid status label, malformed timestamp).
   - Returns exit code 0 for fully compliant files, 1 if violations are found.

7. **Validation Logic**: Each entry must match the pattern `[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]` where:
   - TIMESTAMP matches `YYYY-MM-DD HH:MM:SS`.
   - SUBTASK is non-empty text within brackets.
   - STATUS_LABEL is one of `IN_PROGRESS`, `COMPLETE`, or `FAILED`.
   - DETAILS is non-empty text within brackets.

### Phase D: Module Structure and Import Support

8. **Module Layout**: Mirror `doc_utils.py` structure with functions organized as:
   ```python
   import json, os, re, sys
   from datetime import datetime
   from pathlib import Path

   # Constants (module-level)
   ROOT_DIR = ...
   LOG_DIR = ...
   VALID_STATUS_LABELS = ...
   LOG_FILE_PATTERN = ...

   # Core functions: get_next_log_path(), format_entry()
   # CLI commands: create_log(), show_logs(), validate_log()
   # Entry point: main() with argparse-style sys.argv parsing

   if __name__ == "__main__":
       main()
   ```

9. **Programmatic Import**: Functions like `format_entry()` and `validate_entry()` must be importable without triggering CLI behavior:
   ```python
   from toolbox.specialist_log import format_entry, create_log

   entry = format_entry("TASK-003 analysis", "IN_PROGRESS", "Starting investigation")
   create_log("technical-analyst", "TASK-003 analysis", "IN_PROGRESS", "Starting investigation")
   ```

## Out of Scope

- Retroactive fixing of existing non-compliant log files (per SPIKE-002: utility enforces format for new entries only).
- Changes to `.board/` task management structure or `board_utils.py`.
- Real-time event-driven callbacks from subagents.
- Configuration file support — all settings use module-level constants as per `doc_utils.py` pattern.

# Inputs to Review

Before implementation begins, the following documents were reviewed:

- **REQ-003**: Defines functional requirement #8 (specialist log utility) with requirements for CLI interface, programmatic import, format enforcement, and compliance validation. Success criteria require >=95% format compliance within two weeks of prompt updates.
- **SPIKE-002 Finding 1**: Documents severe logging inconsistencies across 8 existing specialist log files from 3 roles (backend-engineer, technical-analyst, test-engineer). Format issues include: missing DETAILS field on some entries, incomplete timestamp values (`xx` placeholders), inconsistent bracket usage, and mixed naming conventions.
- **SPIKE-002 Finding 3**: Recommends CLI design mirroring `doc_utils.py` with LOG/SHOW/CLEAN commands (note: "CLEAN" in spike maps to VALIDATE in the final plan — CLEAN is renamed to VALIDATE for clarity). Module structure should use module-level constants, sys.argv parsing, and return None on failure.
- **SPIKE-002 Evaluation Option D**: Recommends single file per role with append mode (not new file per entry) to balance simplicity with auditability. One file per role per active period, with multiple entries appended within the same session.

**Open Questions from SPIKE-002 (require team lead clarification)**:
1. **CLEAN vs VALIDATE**: SPIKE-002 mentions a "CLEAN" command in the recommended API but describes validation behavior rather than cleanup/cleanup functionality. The plan uses VALIDATE for clarity — confirm this is acceptable or if CLEAN should perform actual log file cleanup (e.g., archiving old logs).

# Implementation Tasks

## Phase A: Core LOG Command and Module Structure

1. Create `toolbox/specialist_log.py` with module-level constants (`ROOT_DIR`, `LOG_DIR`, `VALID_STATUS_LABELS`, `LOG_FILE_PATTERN`).
2. Implement `get_next_log_path(role)`: Check if a log file exists for the role; create one with `<role>_<YYYYMMDD_HHMMSS>.log` naming convention if needed; return the path.
3. Implement `format_entry(subtask, status, details)`: Generate timestamp using `datetime.now().strftime("%Y-%m-%d %H:%M:%S")`; format as `[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]`.
4. Implement `validate_entry(line)`: Parse entry against required pattern; return `(True, "")` if compliant or `(False, "issue description")` if not.
5. Implement `create_log(role, subtask, status, details)`: Validate inputs (status in VALID_STATUS_LABELS, non-empty subtask/details); get log path via `get_next_log_path()`; append formatted entry to file.

## Phase B: SHOW Command Implementation

6. Implement `show_logs(role=None, since=None)`: List files in LOG_DIR; filter by role if specified (parse filename for role prefix); filter by date range if `--since` provided; display entries chronologically.
7. Handle edge cases: empty directory, no matching logs, invalid date format.

## Phase C: VALIDATE Command Implementation

8. Implement `validate_log(filepath)`: Read all lines from the specified file; validate each line using `validate_entry()`; collect non-compliant entries with line numbers and issues; print summary report; return 0 if compliant, 1 if violations found.
9. Handle edge cases: file not found (print error to stdout, exit 1), empty file (return 0 — no violations).

## Phase D: CLI Entry Point and Testing

10. Implement `main()` with sys.argv parsing mirroring `doc_utils.py` pattern:
    - Parse command argument (`LOG`, `SHOW`, or `VALIDATE`).
    - Route to appropriate function with parsed arguments.
    - Print error messages to stdout; return None on failure (no exceptions raised).

11. Test the utility manually:
    - Create a log entry for role "test-analyst" and verify file creation + format.
    - Query logs with SHOW command, testing both filtered and unfiltered modes.
    - Validate a compliant log file (expect exit code 0) and a non-compliant file (expect exit code 1).

# Risks / Constraints

- **No Retroactive Fixing**: The utility cannot fix existing non-compliant log files — it only enforces format for new entries going forward. This is acceptable per REQ-003's success criteria which target future compliance rates, not historical data (per SPIKE-002 Finding 1).
- **Naming Convention Coexistence**: New log files will use `<role>_<YYYYMMDD_HHMMSS>.log` format while legacy files may use dash-based naming. The VALIDATE command can flag non-conforming filenames during audits but cannot rename them automatically (per SPIKE-002 Risk 3).
- **Constraint**: Must follow `doc_utils.py` API design patterns exactly — module-level constants, sys.argv CLI parsing, validation functions returning None on failure with stdout error messages.

# Success Criteria

- `toolbox/specialist_log.py` exists and is importable as a Python module without triggering CLI behavior when imported (not run directly).
- LOG command creates/appends entries in the standardized format; SHOW command queries logs with optional role/date filtering; VALIDATE command returns correct exit codes for compliant/non-compliant files.
- All three commands mirror `doc_utils.py` API design patterns: module-level constants, sys.argv parsing, validation functions returning None on failure.
- Programmatic import works correctly: `from toolbox.specialist_log import format_entry, create_log` succeeds and produces valid output.

# Revision Notes

Initial feature spec created based on SPIKE-002 Findings 1 and 3 recommendations. CLI commands mapped to LOG/SHOW/CLEAN (renamed VALIDATE for clarity). Module structure mirrors `doc_utils.py`. Single file per role with append mode adopted from Option D evaluation.
