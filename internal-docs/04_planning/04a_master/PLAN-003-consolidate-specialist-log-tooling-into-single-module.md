---
id: PLAN-003
title: Consolidate Specialist Log Tooling into Single Module
version: 1.0.0
status: APPROVED
created: 2026-07-16 12:24:23
updated: 2026-07-16 12:34:30
related_docs: ["REQ-004", "RAD-002", "FEAT-007"]
---
# Release Summary

This plan covers the consolidation of three specialist log tooling modules (`toolbox/specialist_log.py`, `toolbox/compliance_audit.py`, and `toolbox/log_format.py`) into a single cohesive module at `toolbox/specialist_log.py`. The consolidation eliminates cross-module dependencies, removes validation logic duplication (flagged in REVIEW-005/REVIEW-006), unifies the log entry naming convention to date-first format (`<YYYYMMDD_HHMMSS>_<role>.log`), and merges 135 unit tests into a single test file. This follows the established pattern of `doc_utils.py`, which keeps all constants, validation logic, CLI commands, and formatting functions in one file.

# Timebox

- Start: 2026-07-16
- End: TBD (end of current sprint cycle following REQ-004 approval)
- Duration: 1 sprint

# Release Goal

Deliver a single `toolbox/specialist_log.py` module that contains all specialist log functionality — constants, validation logic, formatting functions, CLI commands (LOG, SHOW, VALIDATE, CLEAN), and diagnostic utilities from the former compliance_audit module. Eliminate `compliance_audit.py` and `log_format.py`, reduce toolbox module count from 4 to 3, and ensure consistent log entry format across all operations with a unified validation code path.

# Features Included

1. **FEAT-007** — Implement Specialist Log Tooling Consolidation: The feature that implements the actual consolidation of modules, naming convention updates, test merging, and cleanup.

# Sequencing / Dependencies

- **Phase 1**: Inline `log_format.py` constants (`ENTRY_PATTERN`, `VALID_STATUS_LABELS`) and functions (`validate_entry()`, `format_entry()`) into `specialist_log.py`. Use the permissive regex variant (`[^\]]*`) from compliance_audit as canonical.
- **Phase 2**: Fold diagnostic utilities from `compliance_audit.py` (`_calc_compliance_rate`, `_get_issue_description`, `extract_role`, `validate_file`) into `specialist_log.py` as module-level functions — not exposed as new CLI subcommands.
- **Phase 3**: Update log file naming convention from `<role>_<YYYYMMDD_HHMMSS>.log` to `<YYYYMMDD_HHMMSS>_<role>.log`. This cascading change affects `get_next_log_path()`, `show_logs()`, `clean_logs()`, and all test fixtures.
- **Phase 4**: Consolidate tests from both files (63 + 72 = 135) into a single `test_specialist_log.py`, updating all assertions referencing the old naming convention.
- **Phase 5**: Delete `toolbox/compliance_audit.py` and `toolbox/log_format.py`. Run full test suite to confirm zero regressions.

Dependencies:
- REQ-004 must be APPROVED before implementation begins (currently in place).
- RAD-002 provides the technical analysis that guides all consolidation decisions.
- FEAT-005 and FEAT-006 are predecessor features whose outputs are being consolidated; they remain as reference documents but will no longer correspond to active modules.

# Milestones

1. **Milestone 1**: `log_format.py` inlined into `specialist_log.py` — constants, validate_entry(), format_entry() all present module-level with permissive regex variant.
2. **Milestone 2**: Compliance audit utilities folded in — `_calc_compliance_rate`, `_get_issue_description`, `extract_role`, `validate_file` available as internal functions; naming convention updated to date-first format.
3. **Milestone 3**: All 135 tests consolidated into single file and passing with updated fixtures for new naming convention.
4. **Milestone 4**: Obsolete modules deleted (`compliance_audit.py`, `log_format.py`); full test suite passes; backward compatibility of LOG/SHOW/VALIDATE/CLEAN commands verified.

# Risks / Constraints

- **Validation Logic Divergence Risk**: The permissive regex from compliance_audit allows empty brackets at the regex level, while strict validation still catches them via secondary checks. Mitigation: Both code paths produce identical error messages; no valid entry becomes invalid — previously-rejected entries now get better descriptions.
- **Test Count Regression**: During merge, some test classes may overlap or become redundant. Mitigation: Plan for 135+ baseline tests (63 + 72); review each class during consolidation to eliminate duplicates while preserving coverage.
- **Naming Convention Backward Compatibility**: Existing log files use the old `<role>_<timestamp>.log` format. Mitigation: Only new logs use the date-first format; existing files are untouched and can be cleaned by `clean_logs()` using date-based logic rather than filename parsing.
- **Module Size Growth**: Consolidated module will grow from 328 to ~400–450 lines (smaller than the sum of all three modules at 851). Mitigation: This is within acceptable bounds — comparable to `doc_utils.py` (342) and well under `board_utils.py` (410+).

# Success Criteria

- `toolbox/compliance_audit.py` and `toolbox/log_format.py` are deleted.
- All specialist log functionality accessible via `specialist_log.py`: LOG, SHOW, VALIDATE, CLEAN commands with identical argument formats; diagnostic utilities available as module-level functions.
- 135+ unit tests pass from a single consolidated test file (`test_specialist_log.py`).
- No circular import risk — `specialist_log.py` imports only standard library and `board_utils`.
- Log entry naming convention updated to `<YYYYMMDD_HHMMSS>_<role>.log` with consistent behavior across all functions.
- VALIDATE command produces clear, human-readable error messages for all edge cases using unified validation code path.

# Revision Notes

Use this section for plan updates as implementation progresses and new information emerges.
