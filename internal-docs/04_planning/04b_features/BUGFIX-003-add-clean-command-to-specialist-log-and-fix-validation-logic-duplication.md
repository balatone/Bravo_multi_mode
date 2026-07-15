---
id: BUGFIX-003
title: Add CLEAN command to specialist_log and fix validation logic duplication
version: 1.0.0
status: APPROVED
created: "2026-07-15 20:40:04"
updated: 2026-07-15 20:47:37
related_docs: ["REVIEW-005", "PLAN-002"]
priority: MEDIUM
---
# Summary

Addresses four issues identified in REVIEW-005 for PLAN-002 implementation: (1) adds the missing CLEAN command to `specialist_log.py` as specified in PLAN-002's LOG/SHOW/CLEAN design; (2) eliminates validation logic duplication between `compliance_audit.py` and `specialist_log.py` by extracting shared patterns into a common module; (3) standardizes return value conventions across all public functions in `specialist_log.py`; (4) moves compliance audit report output from tracked documentation directory (`internal-docs/05_reports/`) to untracked logs directory (`logs/compliance_audit/`).

# Scope

## In Scope

- Implement CLEAN command in `toolbox/specialist_log.py` with configurable retention period.
- Extract shared validation constants and regex patterns from both files into `toolbox/log_format.py`.
- Refactor `compliance_audit.py` to import validation logic from the new shared module.
- Standardize return values: use `None` for failures (with stdout error messages), consistent success types.
- Move compliance audit report output from `internal-docs/05_reports/` to `logs/compliance_audit/`.
- Update unit tests in `test_specialist_log.py` and `test_compliance_audit.py` accordingly.

## Out of Scope

- Changes to specialist log entry format specification (existing format remains unchanged).
- Modifications to compliance audit report generation logic or output formats.
- Updates to snippet documentation (`specialist-log-formatting.md`) — handled separately if needed.

# Proposed Fix

### Issue 1: Missing CLEAN Command

Add a `CLEAN` subcommand to the CLI in `main()` that accepts an optional `--days` flag (default: 30). The function will scan `LOG_DIR`, identify log files older than the retention period, and either delete them or move them to an archive directory. This mirrors the lifecycle management pattern expected by PLAN-002's design specification.

### Issue 2: Validation Logic Duplication

Create a new module `toolbox/log_format.py` containing shared constants (`ENTRY_PATTERN`, `VALID_STATUS_LABELS`) and validation functions (`validate_entry()`, `format_entry()`). Both `specialist_log.py` and `compliance_audit.py` will import from this module instead of duplicating logic. This eliminates the risk of format divergence if changes are made to one file but not the other.

### Issue 3: Return Value Inconsistency

Standardize all public functions in `specialist_log.py`:
- Functions that produce output (e.g., `show_logs()`, `validate_log()`) return structured data on success, `None` on failure with error printed to stdout.
- Functions that perform actions (e.g., `create_log()`) return the result of the action (file path string) on success, `None` on failure with error printed to stdout.
- CLI exit codes remain 0 for all cases (errors are communicated via stdout messages, matching doc_utils.py pattern).

### Issue 4: Compliance Audit Reports in Tracked Directory

Change `REPORTS_DIR` from `ROOT_DIR / "internal-docs" / "05_reports"` to `ROOT_DIR / "logs" / "compliance_audit"`. This moves auto-generated audit reports out of the version-controlled documentation folder into an untracked logs directory, keeping internal-docs clean for authored documents only. Update the report header text that references the storage location accordingly.

# Implementation Tasks

1. Create `toolbox/log_format.py` with shared constants and validation functions extracted from both existing modules.
2. Update `specialist_log.py`:
   - Import from `log_format.py`.
   - Add `clean_logs()` function implementing the CLEAN command logic.
   - Add `CLEAN` case to CLI argument parsing in `main()`.
   - Standardize return values across all public functions.
3. Update `compliance_audit.py`:
   - Import validation logic from `log_format.py` instead of duplicating it.
   - Remove duplicate ENTRY_PATTERN and validate_entry() function.
4. Add unit tests:
   - Tests for CLEAN command (valid retention period, file deletion, no-op when all files recent).
   - Tests verifying shared module imports work correctly in both consumers.
   - Regression tests ensuring existing functionality unchanged after refactoring.
4. Move `REPORTS_DIR` from `internal-docs/05_reports/` to `logs/compliance_audit/`, update report header text, and ensure directory creation logic handles the new path.
5. Run full test suite to verify 122+ tests pass with zero regressions.

# Acceptance Criteria

- `python3 specialist_log.py CLEAN --days 7` removes log files older than 7 days from the log directory.
- `python3 specialist_log.py CLEAN` (no flag) uses default 30-day retention period.
- `compliance_audit.py` imports validation logic from `log_format.py` — no duplicate regex or validate_entry() function exists in either file.
- All public functions in `specialist_log.py` return `None` on failure with error message to stdout (matching doc_utils.py pattern).
- Compliance audit reports are saved to `logs/compliance_audit/`, not `internal-docs/05_reports/`.
- 122+ unit tests pass after changes, including new CLEAN command tests and shared module import verification.

# Verification Plan

- Run full test suite: `python3 -m pytest python_tests/test_specialist_log.py python_tests/test_compliance_audit.py -v`
- Manually verify CLEAN command: create test log files with various timestamps, run CLEAN with --days flag, confirm correct files removed/retained.
- Verify compliance audit still produces identical reports after refactoring (compare output of two consecutive runs).
- Confirm no circular import errors when both modules import from `log_format.py`.

# Risks / Notes

- **Backward compatibility**: Changing return values in public functions may affect any external callers. Since these are internal toolbox utilities called only by specialist agents via CLI or direct imports within the project, risk is low but should be verified during testing.
- **Shared module design**: `log_format.py` must not import from either consumer module to avoid circular dependencies. All shared logic must be pure functions/constants.
- **CLEAN command safety**: Consider adding a dry-run mode (`--dry-run`) in a future iteration to prevent accidental deletion of important log history.

# Supporting Materials

## Files Modified

| File | Change Type | Description |
|------|-------------|-------------|
| `toolbox/log_format.py` | New | Shared validation constants and functions extracted from specialist_log.py and compliance_audit.py |
| `toolbox/specialist_log.py` | Modified | Import shared module, add CLEAN command, standardize return values |
| `toolbox/compliance_audit.py` | Modified | Remove duplicate logic, import from shared module; change REPORTS_DIR to logs/compliance_audit/ |
| `python_tests/test_specialist_log.py` | Updated | Add CLEAN tests, verify shared imports, update assertions for new return types |
| `python_tests/test_compliance_audit.py` | Updated | Verify compliance_audit uses shared validation and correct report directory, add regression tests |

## Current Validation Logic (to be extracted)

From `specialist_log.py`:
```python
ENTRY_PATTERN = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] - "
    r"\[([^\]]*)\] - "
    r"\[STATUS: ([^\]]+)\] - "
    r"\[([^\]]*)\]$"
)

VALID_STATUS_LABELS = {"COMPLETE", "IN_PROGRESS", "FAILED"}
```

From `compliance_audit.py`:
```python
ENTRY_PATTERN = re.compile(
    r"^\[(.*?)\] - \[(.*?)\] - \[STATUS: (.*?)\] - \[(.*?)\]$"
)
# Note: uses [^\]]* instead of [^\]]+ — allows empty brackets, validated separately
```

These will be consolidated into `log_format.py` with the stricter pattern from `specialist_log.py`.
