---
id: FEAT-007
title: Implement Specialist Log Tooling Consolidation
version: 1.0.0
status: APPROVED
created: 2026-07-16 12:24:30
updated: 2026-07-16 12:34:32
related_docs: ["REQ-004", "PLAN-003", "RAD-002"]
---
# Feature Overview

This feature consolidates three specialist log tooling modules (`toolbox/specialist_log.py`, `toolbox/compliance_audit.py`, and `toolbox/log_format.py`) into a single module at `toolbox/specialist_log.py`. The consolidation eliminates cross-module dependencies, removes validation logic duplication (flagged in REVIEW-005/REVIEW-006), adopts a date-first log naming convention (`<YYYYMMDD_HHMMSS>_<role>.log`), and merges 135 unit tests into one file. All existing CLI commands (LOG, SHOW, VALIDATE, CLEAN) maintain backward-compatible argument formats. Diagnostic utilities from compliance_audit are folded in as internal functions — no new CLI subcommands are added.

# Objectives

- Consolidate all specialist log functionality into a single `toolbox/specialist_log.py` module following the `doc_utils.py` pattern (module-level constants, validation functions, CLI commands).
- Eliminate `compliance_audit.py` and `log_format.py`, reducing toolbox from 4 modules to 3.
- Adopt permissive regex variant (`[^\]]*`) as canonical ENTRY_PATTERN for consistent error reporting across all validation paths.
- Update log file naming convention to date-first format for chronological sorting via `ls`.
- Merge 135 unit tests (63 + 72) into a single test file with updated fixtures.

# Scope

## In Scope

### Step 1: Inline `log_format.py` into `specialist_log.py`

Move all contents from `toolbox/log_format.py` to module-level in `specialist_log.py`:
- **Constants**: `ENTRY_PATTERN`, `VALID_STATUS_LABELS`, plus add `LOG_DIR` and `REPORTS_DIR` as module-level constants (matching the `doc_utils.py` pattern with `TYPE_MAP`, `LIFECYCLE_STATUSES`).
  - `ENTRY_PATTERN = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] - \[([^\]]*)\] - \[STATUS: (IN_PROGRESS|COMPLETE|FAILED)\] - \[([^\]]*)\]$")` — permissive variant with `[^\]]*`.
  - `VALID_STATUS_LABELS = {"IN_PROGRESS", "COMPLETE", "FAILED"}`.
- **Functions**: `validate_entry(line)` and `format_entry(subtask, status, details)`.
  - `validate_entry()` returns `(bool, str)` tuple — human-readable error message on failure (e.g., `"SUBTASK field is empty"` instead of generic regex rejection).
  - Uses permissive regex + secondary checks: timestamp validation via `datetime.strptime()`, then checks for empty SUBTASK/DETAILS fields when brackets are present but empty.

### Step 2: Fold compliance_audit.py diagnostic utilities into specialist_log.py

Import and inline these functions from `compliance_audit.py`:
- `_calc_compliance_rate(compliant, total)` → module-level utility used by VALIDATE command to report pass/fail counts per file.
- `_get_issue_description(issue_type)` → produces human-readable descriptions like `"SUBTASK field is empty"` for use in `validate_entry()` error messages.
- `extract_role(filename)` → parses `<YYYYMMDD_HHMMSS>_<role>.log` format (strip `.log`, split on last underscore: `filename[:-4].rsplit("_", 1)[-1]`). Updated to match new naming convention.
- `validate_file(filepath)` → wraps `validate_entry()` with per-file aggregation; used by VALIDATE command for file-by-file reporting.

Functions **discarded** (out of scope — no report CLI commands):
- `aggregate_results()`, `generate_markdown_report()`, `generate_json_report()`, `save_report()`, `log_to_board()`, `run_audit()` — all are report-generation concerns excluded from this consolidation.

### Step 3: Update naming convention across code and tests

Change log file naming from `<role>_<YYYYMMDD_HHMMSS>.log` to `<YYYYMMDD_HHMMSS>_<role>.log`:
- **`get_next_log_path(role)`**: Change f-string from `{role}_{timestamp}.log` to `{timestamp}_{role}.log`.
- **`show_logs(role=None)`**: Replace `filename.startswith(f"{role}_")` with suffix-based matching since role now appears at end of filename. Use regex or `filename.endswith(f"_{role}.log")`.
- **`clean_logs(days=30)`**: Update timestamp parsing from `filename.split("_")[1]` to `filename.split("_")[0]`.
- **All test fixtures** in both files: update every hardcoded filename string from `{role}_{timestamp}.log` to `{timestamp}_{role}.log`.

### Step 4: Consolidate tests into single file

Merge all 135 tests from `test_specialist_log.py` (63) and `test_compliance_audit.py` (72):
- Rename test classes to reflect consolidated module (e.g., add `TestExtractRole`, `TestCalcComplianceRate`).
- Remove assertions about cross-module identity (`assertIs(specialist_log.validate_entry, log_format.validate_entry)`) — these become internal implementation details.
- Update all filename fixtures and assertions for new naming convention.
- Preserve all existing test coverage: constants, path generation, formatting, validation, CLI commands, integration tests.

### Step 5: Delete obsolete modules and verify

1. Delete `toolbox/compliance_audit.py`.
2. Delete `toolbox/log_format.py`.
3. Run full test suite (`pytest python_tests/`) to confirm all 135+ tests pass with zero regressions.
4. Verify no circular import risk — `specialist_log.py` imports only standard library and `board_utils`.

# Implementation Tasks

Break the work into concrete tasks for implementation:

1. **Review related documents**: Read REQ-004, PLAN-003, RAD-002 to confirm scope, acceptance criteria, and technical approach.
2. **Inline log_format.py**: Copy constants (`ENTRY_PATTERN`, `VALID_STATUS_LABELS`) and functions (`validate_entry()`, `format_entry()`) into `specialist_log.py` module-level. Replace permissive regex variant as canonical. Remove the import statement for `log_format`.
3. **Fold compliance_audit utilities**: Copy `_calc_compliance_rate()`, `_get_issue_description()`, `extract_role()`, and `validate_file()` from `compliance_audit.py` into `specialist_log.py`. Update `extract_role()` to parse new naming convention format. Remove the import for `log_format` (already removed in step 2).
4. **Update naming convention**: Modify `get_next_log_path()` to produce `{timestamp}_{role}.log`. Update `show_logs()` filtering logic. Update `clean_logs()` timestamp parsing. Ensure all internal references are consistent.
5. **Consolidate test fixtures**: Merge both test files into a single `test_specialist_log.py`. Rename classes as needed, update filename strings in all fixtures and assertions to use new naming convention format. Remove cross-module identity assertions.
6. **Run full test suite**: Execute `pytest python_tests/test_specialist_log.py` — target: 135+ tests passing. Fix any regressions from naming convention change or function reorganization.
7. **Delete obsolete modules**: Remove `toolbox/compliance_audit.py` and `toolbox/log_format.py`. Run the complete test suite one final time to confirm zero regressions.
8. **Verify backward compatibility**: Test that LOG, SHOW, VALIDATE, CLEAN commands work with identical argument formats as before. Verify VALIDATE produces clear error messages for all edge cases (empty brackets, invalid timestamps, missing fields).

# Acceptance Criteria

- `toolbox/compliance_audit.py` and `toolbox/log_format.py` no longer exist in the repository.
- `specialist_log.py` contains all specialist log functionality: constants (`ENTRY_PATTERN`, `VALID_STATUS_LABELS`, `LOG_DIR`, `REPORTS_DIR`), validation functions (`validate_entry()`, `format_entry()`), diagnostic utilities (`_calc_compliance_rate()`, `_get_issue_description()`, `extract_role()`, `validate_file()`), and CLI commands (LOG, SHOW, VALIDATE, CLEAN).
- All 135+ unit tests pass from a single consolidated test file.
- No circular import risk — `specialist_log.py` imports only standard library modules and `board_utils`.
- New log files use `<YYYYMMDD_HHMMSS>_<role>.log` naming convention; existing old-format logs remain untouched.
- VALIDATE command output format is backward-compatible with identical argument formats.
- Diagnostic utilities produce clear, human-readable error messages for all validation edge cases.

# Definition of Done

- All implementation tasks completed and verified.
- 135+ tests written and passing in single consolidated test file.
- Code implemented, reviewed, and free of circular import risks.
- Obsolete modules deleted from repository.
- Relevant documentation (PLAN-003) updated with any changes discovered during implementation.

# Dependencies / Risks

- **Dependency**: REQ-004 must be APPROVED before this feature can begin implementation. PLAN-003 provides the sequencing guidance.
- **Dependency**: RAD-002 analysis document contains all technical findings that guide implementation decisions (permissive regex adoption, naming convention change rationale).
- **Risk**: Test count may drop below 135 if duplicate test classes are merged aggressively. Mitigation: Review each test class during consolidation; preserve unique coverage even if some overlap exists.
- **Risk**: Naming convention change could introduce subtle bugs in `show_logs()` filtering or `clean_logs()` date parsing. Mitigation: Add explicit unit tests for the new filename parsing logic (`extract_role()`, timestamp extraction) before running full suite.

# Implementation Notes

- The consolidated module will be approximately 400–450 lines — significantly smaller than the sum of all three source modules (328 + 450 + 73 = 851 lines). Much of `compliance_audit.py`'s report generation code is excluded since no new CLI commands are added.
- The permissive regex variant (`[^\]]*`) from compliance_audit becomes canonical, but secondary validation still rejects empty SUBTASK/DETAILS fields with clear messages — no valid entry becomes invalid; previously-rejected entries now get better error descriptions.
- All diagnostic utilities folded in from `compliance_audit.py` are internal functions only (no CLI surface). They support the VALIDATE command's ability to report per-entry validation status with actionable descriptions.
- The naming convention change is backward-compatible: existing log files use old format and remain untouched; new logs follow the date-first pattern for chronological sorting.
