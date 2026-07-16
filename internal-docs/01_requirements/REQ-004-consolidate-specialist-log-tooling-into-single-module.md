---
id: REQ-004
title: Consolidate Specialist Log Tooling into Single Module
version: 1.0.0
status: DRAFT
created: 2026-07-16 11:30:22
updated: 2026-07-16 11:30:22
related_docs: ["REQ-003", "FEAT-005", "FEAT-006", "BUGFIX-003"]
---

# Summary

Consolidate the three-module specialist log tooling (`specialist_log.py`, `compliance_audit.py`, `log_format.py`) into a single module (`toolbox/specialist_log.py`), eliminating unnecessary cross-module dependencies and reducing the toolbox to one cohesive utility per concern. This follows the established pattern of `doc_utils.py`, which keeps all constants, validation logic, CLI commands, and formatting functions in one file.

# Business Context / Rationale

During BUGFIX-003 (REVIEW-005 findings), three modules were created to address specialist log functionality:

1. **`toolbox/specialist_log.py`** — LOG, SHOW, VALIDATE, CLEAN commands
2. **`toolbox/compliance_audit.py`** — AUDIT all files, REPORT generation, board integration
3. **`toolbox/log_format.py`** — Shared constants and validation functions (ENTRY_PATTERN, validate_entry, format_entry)

This creates an artificial boundary: `compliance_audit.py` is essentially "specialist_log VALIDATE but for every file" plus report generation. The separation into three modules adds maintenance overhead without providing architectural benefit. Every change to the log entry format requires updates across multiple files instead of one.

The established pattern in this codebase — demonstrated by `doc_utils.py` (342 lines, all inline) and `board_utils.py` (410+ lines, all inline) — is that each toolbox utility lives as a single file with module-level constants, validation functions, CLI commands, and formatting logic. Specialist log tooling should follow the same pattern.

# Scope

## In Scope

- Merge `log_format.py` contents into `specialist_log.py` (constants, validate_entry, format_entry become inline)
- Fold `compliance_audit.py` functionality into `specialist_log.py` as new CLI subcommands: AUDIT and REPORT
- Consolidate test files (`test_specialist_log.py` + `test_compliance_audit.py`) into a single `test_specialist_log.py`
- Delete `toolbox/compliance_audit.py` and `toolbox/log_format.py`

## Out of Scope

- Changes to the log entry format itself (that is governed by REQ-003 FR#2)
- Changes to board task management structure (`board_utils.py`)
- Prompt snippet library updates (FEAT-004 scope)
- Automated remediation of non-compliant entries

# Functional Requirements

1. **Single Module**: `toolbox/specialist_log.py` must contain all specialist log functionality — constants, validation, formatting, CLI commands, and reporting logic. No imports from other toolbox modules except standard library and `board_utils`.

2. **CLI Commands** (mirroring doc_utils.py pattern with sys.argv parsing):
   - `LOG --role <r> --subtask "<s>" --status <st> --details "d"` — Create/append entry
   - `SHOW [--role <r>] [--since YYYY-MM-DD]` — Query and display entries
   - `VALIDATE <logfile>` — Validate a single file, exit 0 if compliant, 1 otherwise
   - `CLEAN [--days N]` — Remove log files older than N days (default: 30)
   - `AUDIT` — Scan all files in LOG_DIR, validate each, print summary to stdout with per-role compliance rates and non-compliant entry details
   - `REPORT --format json|markdown [--output <path>]` — Generate structured report file from audit results

3. **Inline Constants**: Module-level constants must include ENTRY_PATTERN (regex), VALID_STATUS_LABELS (set), LOG_DIR, and REPORTS_DIR — matching the pattern used in doc_utils.py for TYPE_MAP, LIFECYCLE_STATUSES, etc.

4. **Inline Validation**: `validate_entry(line)` function must be defined within specialist_log.py, returning `(bool, str)` tuple with human-readable issue description on failure.

5. **Report Output**: Reports saved to `logs/reports/` directory (not internal-docs). Default filename: `specialist_audit_<YYYYMMDD_HHMMSS>.<md|json>`.

6. **Board Integration**: AUDIT and REPORT commands support `--task-id <ID>` flag that logs results via `board_utils.log_event()` for traceability.

7. **Return Value Convention**: All public functions follow the doc_utils.py pattern — return result/path/count on success, None on failure with error printed to stdout. CLI exit codes remain 0 for all cases (errors reported in output).

# Success Criteria / Acceptance Criteria

- `toolbox/compliance_audit.py` and `toolbox/log_format.py` are deleted
- All specialist log functionality accessible via `specialist_log.py` subcommands: LOG, SHOW, VALIDATE, CLEAN, AUDIT, REPORT
- 135+ unit tests pass (consolidated from both test files)
- No circular import risk — specialist_log.py imports only standard library and board_utils
- Report output goes to `logs/reports/`, not version-controlled documentation directories

# Constraints / Guardrails / Dependencies

- Must maintain backward compatibility: existing CLI commands (LOG, SHOW, VALIDATE, CLEAN) must continue to work with identical argument formats.
- AUDIT command is read-only — it never modifies specialist log files.
- REPORT command produces artifacts that should not be committed to version control (add `logs/reports/` to `.gitignore` if not already present).
- The validation logic (ENTRY_PATTERN, validate_entry) must produce identical results for VALIDATE and AUDIT commands — no divergence between single-file and cross-file validation.

# Timing / Deadline / Trigger

- Needed by: End of current sprint cycle
- Trigger: After REQ-004 is APPROVED, implement as TASK on the board with testing phase before merge.

# Notes / Assumptions

- The consolidation reduces toolbox module count from 4 to 3 (doc_utils.py, specialist_log.py, board_utils.py), aligning with the project's minimalist design philosophy.
- Agents that currently import `compliance_audit` or `log_format` will need their prompt instructions updated — this is a migration concern handled via REQ-004 implementation documentation.

# SMART Check

- **Specific:** The requirement clearly defines consolidation of three modules into one, with explicit command list and inline structure matching doc_utils.py pattern.
- **Measurable:** Success verified by deletion of two files, existence of six subcommands in specialist_log.py, 135+ passing tests, zero circular imports.
- **Achievable:** All functionality already exists across the three modules; consolidation is a reorganization task with no new logic required.
- **Relevant:** Directly addresses REVIEW-006's noted deviation and reduces maintenance burden for log format changes.
- **Time-bound:** Targeted for completion within current sprint cycle, triggered by REQ-004 approval.
