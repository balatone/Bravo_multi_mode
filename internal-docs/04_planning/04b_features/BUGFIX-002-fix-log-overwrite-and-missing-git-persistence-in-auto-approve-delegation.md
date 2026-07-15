---
id: BUGFIX-002
title: Fix log overwrite and missing git persistence in auto_approve_delegation
version: 1.0.0
status: APPROVED
created: 2026-07-15 16:12:42
updated: 2026-07-15 16:14:46
related_docs: ["REVIEW-002", "TASK-0002"]
priority: MEDIUM
---
# Summary

Fixes two critical issues identified in REVIEW-002: (1) `_log_auto_approval()` overwrites the specialist log file on each call instead of appending, destroying prior auto-approval audit trail entries; and (2) `auto_approve_delegation()` does not stage and commit document changes via git after updating a YAML preamble, creating inconsistency with all other board utility functions and risking data loss without traceability.

# Scope

## In Scope

- Fix `_log_auto_approval()` to append log lines instead of overwriting the file (use `mode='a'` or `.open('a')`).
- Add `stage_board()` + `run_git(["commit", ...])` calls in `auto_approve_delegation()` after successful document preamble update.
- Update unit tests to verify append behavior and git persistence.

## Out of Scope

- Changes to `_log_auto_approval()` role attribution (Issue 4 from REVIEW-002 — minor, non-blocking).
- Adding status validation guard for SUPERSEDED/DEPRECATED documents (Issue 3 from REVIEW-002 — minor, non-blocking).
- Refactoring `updated` timestamp assignment order (Issue 5 from REVIEW-002 — cosmetic).

# Proposed Fix

### Issue 1: Log File Overwrite

In `_log_auto_approval()` at line ~389 of `toolbox/board_utils.py`, replace the single-line write with an append-mode open call. The log filename includes a per-call timestamp, so each new auto-approval event creates or appends to its own file — but within the same second, multiple calls would overwrite. Using append mode ensures all events are preserved even if filenames collide (which they won't in practice since timestamps differ by second).

**Before:**
```python
log_path.write_text(log_line, encoding="utf-8")
```

**After:**
```python
with log_path.open("a", encoding="utf-8") as f:
    f.write(log_line)
```

### Issue 2: Missing Git Persistence

In `auto_approve_delegation()` at lines ~465–478 of `toolbox/board_utils.py`, after the successful call to `write_document_preamble()`, add git staging and committing. This mirrors the pattern used by all other board utility functions (`create_task`, `transition_task`, `log_event`, `update_task`).

**Add after line ~465 (after write succeeds):**
```python
stage_board()
run_git(["commit", "-m", f"feat: auto-approve {doc_id} for delegation"])
```

# Implementation Tasks

1. **Read REVIEW-002 findings**: Confirm the two major issues and their exact line references in `board_utils.py`.
2. **Fix `_log_auto_approval()` log append behavior** (line ~389): Replace `write_text` with append-mode file open.
3. **Add git persistence to `auto_approve_delegation()`** (after line ~465): Insert `stage_board()` and `run_git(["commit", ...])` calls after successful preamble write.
4. **Update unit tests**: Add test for log append behavior (verify multiple calls produce separate entries) and test that git staging/commit occurs after approval.
5. **Run full test suite**: Verify all 17 existing tests still pass plus new tests.

# Acceptance Criteria

- `_log_auto_approval()` appends to the log file; calling it twice in quick succession preserves both entries (not just the last one).
- `auto_approve_delegation()` triggers a git add + commit after successfully updating a document's YAML preamble.
- All 17 existing unit tests continue to pass, plus at least 2 new tests covering the fixes.
- No regression in error handling paths — errors during write still return failure dict without partial commits.

# Verification Plan

| Check | Method |
|-------|--------|
| Log append behavior | Run `_log_auto_approval()` twice with different `was_approved` values; verify both log lines exist in the file |
| Git persistence | Call `auto_approve_delegation()` on a test document; run `git log --oneline -1` to confirm commit exists |
| Existing tests pass | `uv run python -m pytest python_tests/test_board_utils_auto_approve.py -v` — expect 19/19 passing (17 existing + 2 new) |
| Error path safety | Call with invalid doc_id; verify no git staging occurs on error paths |

# Risks / Notes

- **Git commit message convention**: The auto-commit uses `feat:` prefix. If the project prefers `chore:` for board operations, this should be adjusted to match existing patterns (other functions use `chore: transition`, `chore: update`, etc.). Recommendation: use `chore: auto-approve {doc_id} for delegation` to stay consistent with other board utility commits.
- **Concurrent approvals**: If two delegations approve the same document simultaneously, both may stage/commit. Git will handle this via merge conflict resolution on the YAML file, but it's worth noting as a known limitation.
- **Test isolation**: New tests for git persistence should use `tmp_path` fixtures to avoid polluting the real repo's `.git` history.

# Supporting Materials

## Code Paths Referenced

| Function | File | Lines (approx) | Issue |
|----------|------|----------------|-------|
| `_log_auto_approval()` | `toolbox/board_utils.py` | ~360–392 | Issue 1: log overwrite at line ~389 |
| `auto_approve_delegation()` | `toolbox/board_utils.py` | ~395–478 | Issue 2: missing git persistence after line ~465 |

## Review Reference

- **REVIEW-002**: `internal-docs/05_review/REVIEW-002-feat-002-auto-approval-delegation-review.md`
  - Major Issue #1 — Log File Overwrite (line ~389)
  - Major Issue #2 — Missing Git Persistence (lines ~465–478)

## Existing Test Coverage

All tests in `python_tests/test_board_utils_auto_approve.py`:
- `TestResolveDocumentPath` — 4 tests
- `TestReadDocumentPreamble` — 2 tests
- `TestWriteDocumentPreamble` — 1 test
- `TestAutoApproveDelegation` — 8 tests
- `TestLogAutoApproval` — 2 tests (needs expansion for append verification)
