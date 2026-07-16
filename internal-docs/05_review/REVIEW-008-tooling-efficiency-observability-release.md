---
id: REVIEW-008
title: Tooling Efficiency & Observability Release (FEAT-008, FEAT-009) Review
version: 1.0.0
status: APPROVED
created: "2026-07-16 15:17:00"
updated: "2026-07-16 15:17:00"
verdict: APPROVED
related_docs: ["FEAT-008", "FEAT-009", "RAD-003", "RAD-004", "REQ-005", "REQ-006"]
---

# Executive Summary

This review covers the implementation of two features under **TASK-0007** (Tooling Efficiency & Observability release):

1. **FEAT-008**: `doc_utils.py` SHOW subcommand for semantic metadata extraction from YAML preambles.
2. **FEAT-009**: `board_utils.py` LIST subcommand for a consolidated project board dashboard.

Both features were implemented using lightweight, dependency-free approaches consistent with the design specifications (RAD-003 and RAD-004). All 45 unit tests pass (13 for doc_utils, 32 for board_utils), and both commands function correctly against real repository data. The verdict is **APPROVED**.

## Key Takeaway

Both features are implemented to specification with clean code, comprehensive test coverage, and zero new external dependencies. Minor non-blocking issues exist but do not prevent approval.

# Review Scope

- `toolbox/doc_utils.py` -- `show_preamble()`, `display_preamble()` functions and CLI SHOW handler
- `python_tests/test_doc_utils.py` -- 13 unit tests for FEAT-008
- `toolbox/board_utils.py` -- `_get_dir_status()`, `collect_tasks()`, `format_table()`, `list_board()` functions and CLI LIST subparser
- `python_tests/test_board_utils.py` -- 32 unit tests for FEAT-009 (including integration with real board)

# Review Criteria

| Criterion | Assessment |
|---|---|
| **Correctness** | PASS -- Both features implement their specified behavior correctly. |
| **Design Alignment** | PASS -- Implementation follows RAD-003 and RAD-004 recommendations precisely. |
| **Test Coverage** | PASS -- 45 tests covering happy paths, edge cases, filters, formatting, and real-board integration. |
| **Code Quality** | PASS -- Clean structure, consistent naming, proper error handling. |
| **Performance** | PASS -- O(n) scanning with lightweight YAML preamble parsing; no caching needed at current scale. |
| **Security** | PASS -- No new external dependencies; input validation present for CLI arguments. |
| **Maintainability** | PASS -- Functions are well-documented, modular, and follow existing code patterns. |

# Findings Summary

- FEAT-008 correctly implements regex-based YAML preamble extraction with zero new dependencies, matching RAD-003's recommended approach.
- FEAT-009 correctly implements the LIST command with all required flags (--active-only, --last-n), mutual exclusivity enforcement, dynamic column widths, and proper sorting order.
- All 45 unit tests pass; integration tests against the real board also pass.
- Minor issues identified: non-positive value validation for `--last-n`, arbitrary minimum column width of 8 in format_table(), and a fallback status mapping that could produce labels outside VALID_STATUSES for unknown directories.

# Required Changes Before Approval

## Blockers

None. No blocking issues found.

## Major Issues

None. No major issues found.

## Minor Issues

1. **`--last-n` non-positive value validation**: The FEAT-009 specification states that `--last-n <count>` should "reject non-positive values with an error message." The current implementation accepts any integer via argparse without validating that the value is positive. A negative or zero value would silently produce unexpected results (e.g., `done_tasks[:0]` returns empty list).
   - **Recommendation**: Add validation in `list_board()` to check `last_n > 0` and print an error if not.

2. **Arbitrary minimum column width of 8**: In `format_table()`, header widths are initialized with `max(len(h), 8)`. The value 8 is arbitrary; a more principled approach would use the actual minimum needed (e.g., max of header lengths or a sensible default like 10).
   - **Recommendation**: Consider using `max(len(h), 10)` for better readability, though this does not affect correctness.

3. **Unknown directory status fallback**: The `_get_dir_status()` function maps unrecognized directories to their uppercase name (e.g., "custom-dir" -> "CUSTOM-DIR"). This label may not be in VALID_STATUSES or STATUS_ORDER, causing the task to sort with key 99 and potentially appear at unexpected positions.
   - **Recommendation**: Either add a default entry in FOLDERS for unknown directories, or document this behavior explicitly. Currently it is non-breaking but could confuse users.

# Positive Findings

- **FEAT-008 dependency-free design**: The regex-based preamble extraction uses only Python stdlib (re, os, pathlib), exactly as RAD-003 recommended. No PyYAML or other external dependencies were introduced.
- **Comprehensive edge case coverage in tests**: Both test suites cover file-not-found, empty preambles, missing fields, quoted values, colons-in-values, whitespace handling, and more -- far exceeding the minimum requirements.
- **FEAT-009 sorting logic is correct**: The STATUS_ORDER dict correctly orders TO-DO(0) through DONE(7), with all intermediate stages (ANALYSING, DESIGNING, PLANNING, IMPLEMENTING, TESTING, REVIEWING) properly positioned.
- **Dynamic column width calculation in format_table()**: The function correctly computes per-column maximum widths across all rows and header, producing perfectly aligned ASCII tables regardless of content length. Verified with real data showing proper alignment for varying title lengths.
- **Mutual exclusivity enforcement**: `list_board()` correctly detects when both --active-only and --last-n are provided, prints a clear error to stderr, and exits with code 1.
- **Graceful degradation in collect_tasks()**: Malformed YAML files are caught via try/except and skipped; filename-based fallback extraction provides resilience for edge cases.
- **Integration tests against real board**: The test suite includes `TestIntegrationWithRealBoard` that validates the implementation works correctly with actual repository data, not just synthetic fixtures.

# Verification Results

## Commands Executed

```bash
# Test execution -- FEAT-008 (doc_utils.py)
uv run python -m pytest python_tests/test_doc_utils.py -v
# Result: 13 passed in 0.02s

# Test execution -- FEAT-009 (board_utils.py)
uv run python -m pytest python_tests/test_board_utils.py -v
# Result: 32 passed in 0.06s

# Functional test -- doc_utils.py SHOW against real file
uv run python toolbox/doc_utils.py SHOW internal-docs/02_analysis/RAD-003-technical-investigation-doc-utils-info-command.md
# Result: Correctly extracted and displayed all YAML preamble fields with proper alignment

# Functional test -- board_utils.py LIST (full board)
uv run python toolbox/board_utils.py list
# Result: All 7 tasks displayed in correct sort order (IN-PROGRESS first, then DONE sorted by recency)

# Functional test -- board_utils.py LIST --active-only
uv run python toolbox/board_utils.py list --active-only
# Result: Only TASK-0007 shown with IN-PROGRESS status; all DONE tasks correctly excluded
```

## Static Analysis Observations

- `doc_utils.py` imports remain unchanged from pre-feature state (json, os, re, sys, datetime, pathlib). No new dependencies.
- `board_utils.py` uses existing yaml import (already present for other functions) and standard library modules only.
- Both implementations follow the project's coding conventions: type hints, docstrings, consistent naming.

# Risks / Follow-ups

1. **Scalability of collect_tasks()**: At current scale (<50 tasks), rglob-based scanning is fast. If task count grows beyond 500, consider implementing a caching layer as suggested in RAD-004.
2. **FEAT-008 regex robustness**: The pattern `r"^---\s*\n(.*?)\n---"` works for flat key-value YAML but would fail on nested structures (e.g., lists or multi-line values). This is acceptable given current project constraints, as documented in RAD-003.
3. **Board directory naming conventions**: The _get_dir_status() function handles "reviewing" and "custom-dir" mappings that don't correspond to actual FOLDERS entries. Consider consolidating these fallbacks or removing them if they serve no practical purpose.

# Supporting Materials / Evidence

- RAD-003: `internal-docs/02_analysis/RAD-003-technical-investigation-doc-utils-info-command.md`
- RAD-004: `internal-docs/02_analysis/RAD-004-technical-investigation-board-utils-list-command.md`
- FEAT-008 spec: `internal-docs/04_planning/04b_features/FEAT-008-semantic-metadata-extraction-for-documentation.md`
- FEAT-009 spec: `internal-docs/04_planning/04b_features/FEAT-009-project-board-dashboard.md`
- Implementation files: `toolbox/doc_utils.py`, `toolbox/board_utils.py`
- Test suites: `python_tests/test_doc_utils.py`, `python_tests/test_board_utils.py`
