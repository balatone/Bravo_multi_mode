---
id: RAD-002
title: Consolidate Specialist Log Tooling into Single Module
version: 1.0.0
status: DRAFT
created: 2026-07-16 11:53:43
updated: 2026-07-16 11:53:43
related_docs: ["REQ-004", "FEAT-005", "FEAT-006", "BUGFIX-003", "REVIEW-005", "REVIEW-006"]
---

# Executive Summary

This document outlines the technical plan for consolidating three specialist log tooling modules (`toolbox/specialist_log.py`, `toolbox/compliance_audit.py`, and `toolbox/log_format.py`) into a single module at `toolbox/specialist_log.py`. The consolidation eliminates cross-module dependencies, removes validation logic duplication, and ensures **consistent log entries** by unifying the permissive entry pattern from `compliance_audit.py` with the human-readable error reporting from `log_format.py`. All existing functionality — including 135 unit tests across both test files — will be preserved in a single consolidated test file. No new CLI subcommands are added; the goal is format consistency, not audit/reporting features.

# Purpose / Question

How should three loosely-coupled specialist log modules be merged into one cohesive module so that all log entries are consistently formatted — eliminating the validation logic duplication between `specialist_log.py` (strict pattern) and `compliance_audit.py` (permissive pattern)?

# Scope

## In Scope
- Merge `log_format.py` contents (constants, `validate_entry`, `format_entry`) inline into `specialist_log.py`
- Fold `compliance_audit.py`'s validation helpers (`extract_role`, `_calc_compliance_rate`, `_get_issue_description`, `validate_file`) into `specialist_log.py` as utility functions — **not** as new CLI subcommands. These support log consistency by providing diagnostic tools for identifying and correcting non-compliant entries.
- Update the log file naming convention from `<role>_<timestamp>.log` to `<YYYYMMDD_HHMMSS>_<role>.log` (date-first) so that `ls` output sorts chronologically rather than alphabetically by role name. This affects `get_next_log_path()`, `show_logs(role=None)` filtering, and any filename parsing logic in folded-in utilities like `extract_role()`.
- Consolidate tests from `test_specialist_log.py` (63 tests) + `test_compliance_audit.py` (72 tests) = 135 total into a single `test_specialist_log.py`, updating all test fixtures and assertions that reference the old naming convention.
- Delete `toolbox/compliance_audit.py` and `toolbox/log_format.py`

## Out of Scope
- New CLI subcommands (no AUDIT or REPORT commands added to the CLI)
- Changes to the log entry format itself (governed by REQ-003 FR#2)
- Changes to `board_utils.py` or its `log_event()` interface
- Prompt snippet library updates (FEAT-004 scope)
- Automated remediation of non-compliant entries
- Report file generation — the goal is consistent log creation, not audit reporting

# Current State

## Module Inventory

| File | Lines | Purpose | Imports From Other Toolbox Modules |
|---|---|---|---|
| `toolbox/specialist_log.py` | 328 | LOG, SHOW, VALIDATE, CLEAN CLI commands + helpers | `log_format`: `VALID_STATUS_LABELS`, `validate_entry`, `format_entry` |
| `toolbox/compliance_audit.py` | 450 | Log file scanning, report generation (markdown/JSON), board integration — legacy module being folded in for diagnostic utilities only | `log_format`: `VALID_STATUS_LABELS`; also has its own `ENTRY_PATTERN` and `validate_entry()` |
| `toolbox/log_format.py` | 73 | Shared constants (`ENTRY_PATTERN`, `VALID_STATUS_LABELS`) + validation/formatting functions | None (standard library only) |

## Dependency Graph

```
specialist_log.py ──imports──> log_format.py (VALID_STATUS_LABELS, validate_entry, format_entry)
compliance_audit.py ──imports──> log_format.py (VALID_STATUS_LABELS only)
                              ──has own──> ENTRY_PATTERN + validate_entry() [permissive variant]
```

Key observation: `compliance_audit.py` imports `VALID_STATUS_LABELS` from `log_format.py` but maintains its **own** `ENTRY_PATTERN` regex and `validate_entry()` function. This is the deviation flagged in REVIEW-005/REVIEW-006 — it uses `[^\]]*` (allows empty brackets) while `specialist_log.py`'s inherited pattern from `log_format.py` uses `[^\]]+` (requires non-empty). Both produce equivalent validation results due to secondary checks, but this duplication creates maintenance risk.

## Test Inventory

| File | Tests | Coverage |
|---|---|---|
| `python_tests/test_specialist_log.py` | 63 tests | Constants, get_next_log_path, format_entry, validate_entry, create_log, show_logs, validate_log, clean_logs, main CLI, integration |
| `python_tests/test_compliance_audit.py` | 72 tests | Constants, extract_role, validate_entry (issue-key variant), validate_file, scan_log_files, aggregate_results, _calc_compliance_rate, _get_issue_description, generate_markdown_report, generate_json_report, save_report, run_audit, shared-module verification, integration |

## CLI Commands Currently Available

| Module | Subcommands / Entry Points |
|---|---|
| `specialist_log.py` | LOG, SHOW, VALIDATE, CLEAN (manual sys.argv parsing) |
| `compliance_audit.py` | Single entry point via argparse (`--format`, `--task-id`) — produces reports |

Note: The consolidation does **not** add new CLI subcommands. The goal is format consistency through unified validation logic, not audit/reporting features. Any diagnostic utilities folded in from `compliance_audit.py` will be callable as module-level functions only (no CLI surface).

## Naming Convention Change

| Aspect | Current (`specialist_log.py`) | New (consolidated) |
|---|---|---|
| Format | `<role>_<YYYYMMDD_HHMMSS>.log` | `<YYYYMMDD_HHMMSS>_<role>.log` |
| Example | `technical-analyst_20260715_140130.log` | `20260715_140130_technical-analyst.log` |
| Sort order by `ls` | Alphabetical (role groups together) | Chronological (newest last, oldest first) |

**Impact on code**:
- `get_next_log_path(role)` — change the filename construction in the f-string: `{timestamp}_{role}.log` instead of `{role}_{timestamp}.log`
- `show_logs(role=None)` — existing filter logic (`filename.startswith(f"{role}_")`) must be updated to match the new pattern. Since role now appears at the end, filtering requires a different approach (e.g., regex or suffix matching).
- `extract_role(filename)` from `compliance_audit.py` — currently parses `<role>_<timestamp>`; must be updated to parse `<timestamp>_<role>.log`. The timestamp portion is always 15 characters (`YYYYMMDD_HHMMSS`), so role extraction becomes: `filename[:-4].rsplit("_", 1)[-1]` (strip `.log`, split on last `_`).
- `clean_logs(days=30)` — uses `datetime.strptime(filename.split("_")[1], "%Y%m%d_%H%M%S")`; the timestamp position shifts from index `[1]` to `[0]`.

This change is **backward-compatible** in that it only affects new log files. Existing old-format logs remain untouched and will simply not match the new naming pattern — they can be cleaned up by `clean_logs()` using date-based logic rather than filename parsing.

# Methodology / Evidence

- **Code inspection**: All three source files read and analyzed in full.
- **Import analysis**: Grep across entire codebase for imports of `specialist_log`, `compliance_audit`, and `log_format`.
- **Test enumeration**: pytest collection counts verified (63 + 72 = 135 tests).
- **Pattern reference**: `doc_utils.py` (342 lines, single file with constants/validation/CLI) used as the target pattern.
- **Board review**: TASK-0006 status confirmed as ANALYSING; related REQ-004 and BUGFIX-003 documents reviewed for context.

# Findings

## Finding 1: `log_format.py` is a thin abstraction with zero internal dependencies
The shared module (`log_format.py`, 73 lines) contains only standard-library imports (`re`, `datetime`). It has no circular import risk and can be safely inlined into `specialist_log.py`. Its three exports — `ENTRY_PATTERN`, `VALID_STATUS_LABELS`, `validate_entry()`, `format_entry()` — are all used by both consumers.

## Finding 2: `compliance_audit.py` duplicates validation logic intentionally but at a cost
`compliance_audit.py` maintains its own `ENTRY_PATTERN` (permissive, allows empty brackets) and `validate_entry()` that returns issue-type keys for remediation mapping. This was an intentional design choice to support distinct error classification in reports. However:
- The core regex is nearly identical to `log_format.py`'s pattern (only difference: `[^\]]*` vs `[^\]]+`)
- Both functions perform the same validation steps (timestamp, subtask, status, details)
- Consolidation should use a **single** `validate_entry()` with clear, human-readable error messages that work consistently across both `create_log()` (preventing bad entries from being written) and `validate_log()` (reporting issues in existing files). The permissive regex + secondary checks pattern ensures agents get actionable feedback like "SUBTASK field is empty" rather than generic format rejections.

## Finding 3: No external code imports these modules outside of tests
Grep across the entire codebase confirms zero non-test Python files import from `compliance_audit` or `log_format`. The only consumers are the two test files and the cross-import between `specialist_log.py` ↔ `log_format.py` and `compliance_audit.py` ↔ `log_format.py`. This means consolidation carries **zero risk of breaking external callers**.

## Finding 4: The permissive pattern from `compliance_audit.py` should become canonical
The strict `[^\]]+` pattern in `log_format.py` rejects empty brackets at the regex level, while the permissive `[^\]]*` pattern in `compliance_audit.py` allows them through to secondary checks. For log consistency, the **permissive** variant should be adopted as the canonical `ENTRY_PATTERN`. This ensures that entries with missing subtask or details fields are caught by clear error messages (e.g., "SUBTASK field is empty") rather than being silently rejected — making it easier for agents and humans to understand what went wrong when creating a log entry.

# Evaluation Criteria

| Criterion | Weight | Notes |
|---|---|---|
| Correctness | High | All 135 tests must pass; VALIDATE output format unchanged for backward compatibility |
| Maintainability | High | Single source of truth for validation logic eliminates sync risk across files |
| Complexity | Medium | Consolidated module will be ~650-700 lines (comparable to `doc_utils.py` at 342 but with more features; `board_utils.py` exceeds 410) |
| Risk | Low | No external callers outside test suite; `.gitignore` already covers output directories |

# Options / Recommendations

## Recommended Approach: Single-Module Consolidation with Unified Validation

### Step 1: Inline `log_format.py` into `specialist_log.py`
Move all constants and functions from `log_format.py` to module-level in `specialist_log.py`:
```python
# Module-level constants (inline, matching doc_utils.py pattern)
ENTRY_PATTERN = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] - \[([^\]]*)\] - \[STATUS: (IN_PROGRESS|COMPLETE|FAILED)\] - \[([^\]]*)\]$"
)
VALID_STATUS_LABELS = {"IN_PROGRESS", "COMPLETE", "FAILED"}

def validate_entry(line): ...  # Returns (bool, str) — human-readable issue on failure
def format_entry(subtask, status, details): ...  # Standardized formatting
```

**Key change**: Use the **permissive** regex variant (`[^\]]*` instead of `[^\]]+`) from `compliance_audit.py`. This allows empty brackets to pass through the regex so that secondary validation can produce clear error messages like "SUBTASK field is empty" rather than a generic format rejection.

### Step 2: Fold `compliance_audit.py` diagnostic utilities into `specialist_log.py`
Import and inline these helper functions from `compliance_audit.py`:
- `_calc_compliance_rate(compliant, total)` → becomes `_calc_compliance_rate()` for internal use by VALIDATE command (to report how many entries passed/failed)
- `_get_issue_description(issue_type)` → used to produce human-readable error messages in `validate_entry()` output
- `extract_role(filename)` → useful utility for log file management

These are **not** exposed as CLI subcommands. They support the VALIDATE command's ability to report per-entry validation status with clear, actionable error descriptions — helping agents understand and fix inconsistent entries.

### Step 3: Unified validation logic ensuring consistent logs
The consolidated `validate_entry()` function will use a single code path that:
1. Applies the permissive `ENTRY_PATTERN` regex (catches structural issues)
2. Validates timestamp via `datetime.strptime()` (catches invalid dates like "9999-99-99")
3. Checks for empty SUBTASK and DETAILS fields when brackets are present but empty
4. Returns `(True, "")` on success or `(False, "<clear error message>")` on failure

This single validation path is used by both `create_log()` (to reject bad entries before writing) and `validate_log()` (to report issues in existing files). No dual code paths — one source of truth for what constitutes a valid log entry.

### Step 4: Update naming convention across code and tests
Update `get_next_log_path()` to produce `<YYYYMMDD_HHMMSS>_<role>.log` instead of `<role>_<YYYYMMDD_HHMMSS>.log`. This cascading change affects:
- **`show_logs(role=None)`**: Replace `filename.startswith(f"{role}_")` with a suffix-based or regex match since role now appears at the end of the filename.
- **`extract_role(filename)`**: Change from `{name.split("_")[0]}` to `{name[:-4].rsplit("_", 1)[-1]}` (strip `.log`, split on last underscore).
- **`clean_logs(days=30)`**: Update timestamp parsing — `filename.split("_")[0]` instead of `[1]`.
- **All test fixtures** in both test files: update every hardcoded filename string from `{role}_{timestamp}.log` to `{timestamp}_{role}.log`.

### Step 5: Consolidate tests into single file
Merge all 135 tests from both test files into `test_specialist_log.py`:
- Rename classes to reflect consolidated module (e.g., `TestExtractRole`, `TestCalcComplianceRate`)
- Remove assertions about cross-module identity (`assertIs(specialist_log.validate_entry, log_format.validate_entry)`) — these become internal implementation details
- Preserve all existing test coverage for LOG, SHOW, VALIDATE, CLEAN commands

### Step 6: Delete obsolete modules
After verification that all functionality is accessible via `specialist_log.py`:
1. Delete `toolbox/compliance_audit.py`
2. Delete `toolbox/log_format.py`
3. Run full test suite to confirm zero regressions

### Step 5: Delete obsolete modules
After verification that all functionality is accessible via `specialist_log.py`:
1. Delete `toolbox/compliance_audit.py`
2. Delete `toolbox/log_format.py`
3. Run full test suite to confirm zero regressions

# Risks / Trade-offs / Constraints

| Risk | Mitigation |
|---|---|
| Regression in VALIDATE output format | Keep existing `validate_entry()` signature and human-readable messages unchanged; the permissive regex change only affects which errors are caught at the regex level vs. secondary checks — error messages remain clear and actionable |
| Test count drops below 135 during merge | Plan for 135+ tests (63 + 72 = 135 baseline); no new CLI subcommands means test scope is preserved, not expanded |
| Permissive regex allows entries that strict pattern rejected | The permissive variant only changes *where* the error is caught — secondary validation still rejects empty SUBTASK/DETAILS fields with clear messages. No valid entry becomes invalid; previously-rejected entries now get better error descriptions |

# Supporting Materials / Evidence

## Current File Sizes
- `toolbox/specialist_log.py`: 328 lines (existing CLI + helpers)
- `toolbox/compliance_audit.py`: 450 lines (audit scan + report generation — most of which is not needed for log consistency)
- `toolbox/log_format.py`: 73 lines (constants + validation)
- **Consolidated target**: ~400–450 lines (significantly smaller than the sum; much of compliance_audit.py's report generation code is excluded since no new CLI commands are added)

## Import Analysis Summary
```
Files importing specialist_log: python_tests/test_specialist_log.py only
Files importing compliance_audit: python_tests/test_compliance_audit.py only
Files importing log_format: toolbox/specialist_log.py, toolbox/compliance_audit.py (both internal consumers)
External callers: NONE
```

## What from `compliance_audit.py` Is Kept vs. Discarded

| Function | Action | Reason |
|---|---|---|
| `_calc_compliance_rate()` | **Kept** — as module-level utility for VALIDATE reporting | Helps VALIDATE report pass/fail counts per file |
| `_get_issue_description()` | **Kept** — used by `validate_entry()` error messages | Produces human-readable descriptions like "SUBTASK field is empty" |
| `extract_role()` | **Kept** — as module-level utility | Useful for log file management operations |
| `validate_file()` | **Kept** — wraps validate_entry() with per-file aggregation | Supports VALIDATE command's file-by-file reporting |
| `scan_log_files()` | Kept but simplified | Just lists LOG_DIR contents; trivial to inline |
| `aggregate_results()` | Discarded | Report-generation concern, not log-consistency |
| `generate_markdown_report()` | **Discarded** — no report CLI command needed | Out of scope: goal is consistent logging, not reporting |
| `generate_json_report()` | **Discarded** — same reason | Out of scope |
| `save_report()` | **Discarded** — same reason | Out of scope |
| `log_to_board()` | **Discarded** — no board integration needed for log consistency | Out of scope |
| `run_audit()` | **Discarded** — wraps report generation | Out of scope; replaced by VALIDATE command's existing behavior |

# Next Steps

1. **Implementation** (worker): Inline `log_format.py` constants/functions into `specialist_log.py`, fold in `compliance_audit.py` diagnostic utilities (`_calc_compliance_rate`, `_get_issue_description`, `extract_role`, `validate_file`)
2. **Naming convention update**: Change `get_next_log_path()` to `<YYYYMMDD_HHMMSS>_<role>.log`; update `show_logs()`, `clean_logs()`, and all test fixtures accordingly
3. **Testing** (test engineer): Run full 135 test suite, fix any regressions — no new tests needed since no CLI changes
4. **Cleanup**: Delete `compliance_audit.py`, `log_format.py`; remove their imports from both test files
5. **Review** (reviewer): Verify backward compatibility of LOG/SHOW/VALIDATE/CLEAN commands; confirm VALIDATE produces clear error messages for all edge cases
6. **Documentation update**: Update any prompt snippets or agent instructions that reference the old module names

# Companion Notes / Raw Evidence

Detailed analysis, raw data, tables, calculations, code snippets, and exhaustive evidence should be stored in a separate companion file with the same base name and a `.notes.md` suffix: `RAD-002-consolidate-specialist-log-tooling-into-single-module.notes.md`.
