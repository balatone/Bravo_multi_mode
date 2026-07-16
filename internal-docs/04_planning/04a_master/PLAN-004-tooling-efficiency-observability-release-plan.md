---
id: PLAN-004
title: Tooling Efficiency & Observability Release Plan
version: 1.0.0
status: APPROVED
created: 2026-07-16 14:25:14
updated: 2026-07-16 14:39:02
related_docs: ["REQ-005", "REQ-006", "FEAT-008", "FEAT-009"]
---
# Release Summary

This release introduces two complementary tooling improvements that address friction points identified during TASK-0006 execution. Both features enhance agent efficiency by reducing token waste (REQ-005) and improving project visibility (REQ-006). They are independent utilities targeting different subsystems (`doc_utils.py` and `board_utils.py`) and can be developed in parallel without cross-dependencies.

# Timebox

- Start: 2026-07-16
- End: TBD (end of current sprint cycle following REQ-004 approval)
- Duration: 1 sprint

# Release Goal

Deliver two lightweight CLI utility enhancements that improve agent operational efficiency:

1. A `SHOW` command for `doc_utils.py` that extracts and displays only the YAML preamble metadata from documentation files, reducing token consumption when agents need to inspect document status without reading full body content.
2. A `LIST` command for `board_utils.py` that provides a consolidated ASCII table dashboard of all tasks across `.board/` subdirectories, eliminating manual directory traversal for project status assessment.

# Features Included

1. **FEAT-008** — Semantic Metadata Extraction (`doc_utils.py SHOW`): Implements the `SHOW <filepath>` subcommand to parse and display YAML preamble fields (ID, Title, Status, Verdict, Related Docs) from documentation files. Lightweight parser targeting only the block-delimited preamble; no external dependencies added. [Feature Document](../04b_features/FEAT-008-semantic-metadata-extraction-for-documentation.md)

2. **FEAT-009** — Project Board Dashboard (`board_utils.py LIST`): Implements the `LIST` subcommand to scan all `.board/` subdirectories (to-do/, in-progress/, done/) and output a formatted ASCII table summarizing every task with its ID, Title, and Status sorted by pipeline stage. Supports optional flags for filtered views: `--active-only` shows only TO-DO and IN-PROGRESS tasks; `--last-n <count>` appends the N most recently completed (DONE) tasks to an active view. Default behavior (no flags) shows all tasks across all statuses. [Feature Document](../04b_features/FEAT-009-project-board-dashboard.md)

## FEAT-009 CLI Usage Specification

```bash
python3 board_utils.py LIST                          # Full board — all tasks across all statuses (default)
python3 board_utils.py LIST --active-only            # Active only — TO-DO and IN-PROGRESS tasks only
python3 board_utils.py LIST --last-n 5               # Active + last 5 completed tasks
```

| Flag | Behavior | Output Composition |
|------|----------|-------------------|
| *(none)* | Full board view | All tasks from to-do/, in-progress/, and done/ sorted by pipeline stage |
| `--active-only` | Filtered active view | Only TO-DO and IN-PROGRESS tasks; DONE excluded entirely |
| `--last-n <count>` | Active + recent completions | All active tasks (TO-DO, IN-PROGRESS) plus the N most recently completed tasks from done/ |

**Notes:**
- When `--active-only` is used and no active tasks exist, output: "No active tasks found in .board/"
- When `--last-n <count>` is used with fewer than `<count>` completed tasks, all available are shown (no error).
- The full board view remains the default for completeness but is acknowledged as less practical for day-to-day use.

# Sequencing / Dependencies

**These two features are independent and can be implemented in parallel.** There is no cross-dependency between them:

- **FEAT-008 (doc_utils.py SHOW)** operates on `internal-docs/` files and modifies only `toolbox/doc_utils.py`.
- **FEAT-009 (board_utils.py LIST)** operates on `.board/` directory structure and modifies only `toolbox/board_utils.py`.

Recommended parallel implementation approach:

| Phase | FEAT-008 (doc_utils.py SHOW) | FEAT-009 (board_utils.py LIST) |
|-------|------------------------------|----------------------------------|
| 1. Design & Implementation | Parse YAML preamble block; implement key-value output format with graceful handling of missing fields. | Implement directory crawler for `.board/`; extract task ID, Title, Status from filenames and preambles; build sorted ASCII table. |
| 2. Unit Testing | Test edge cases: files without YAML preamble, partial fields, various field counts. | Test edge cases: empty board, varying numbers of tasks, status sorting order. |
| 3. Integration & Review | Verify output matches expected format against sample docs in `internal-docs/`. | Verify table formatting handles dynamic task counts without breaking layout. |

Dependencies:
- REQ-005 and REQ-006 must both be APPROVED before implementation begins (currently in place).
- Both features follow the existing CLI utility pattern established by `doc_utils.py` and `board_utils.py`.

# Milestones

1. **Milestone 1**: `doc_utils.py SHOW` command implemented — parses YAML preamble, outputs key-value pairs for ID/Title/Status/Verdict/Related Docs; handles missing fields gracefully; returns clear error when no YAML preamble is found.
2. **Milestone 2**: `board_utils.py LIST` command implemented — scans all `.board/` subdirectories, extracts task metadata, outputs sorted ASCII table with status-based ordering; supports `--active-only` (TO-DO + IN-PROGRESS only) and `--last-n <count>` (active + N most recent DONE tasks); default full-board view preserved.
3. **Milestone 3**: Both commands tested against representative data; edge cases verified (no YAML preamble, empty board, varying field counts, `--active-only` with no active tasks, `--last-n` with fewer than N completed); full test suite passes.

# Risks / Constraints

- **doc_utils.py SHOW — Preamble Format Variability**: Documentation files may have inconsistent YAML field ordering or missing optional fields. Mitigation: Parser reads all key-value pairs within the `---` delimiters; missing fields simply do not appear in output (no crash).
- **board_utils.py LIST — Table Formatting with Dynamic Data**: The ASCII table must handle varying numbers of tasks without breaking column alignment. Mitigation: Use Python's string formatting with dynamic width calculation based on maximum field length across all rows.
- **board_utils.py LIST — Flag Interaction Complexity**: `--active-only` and `--last-n` are mutually exclusive modes (not combinable). Mitigation: If both flags are provided, show a clear error message explaining the conflict; default to full board if neither is specified.
- **Performance Constraint (FEAT-009)**: The board scanner must remain performant as task count grows. Mitigation: Simple directory listing with lightweight file parsing; no recursive deep scans of nested structures.

# Success Criteria

**For FEAT-008 (`doc_utils.py SHOW`):**
- Running `python3 doc_utils.py SHOW <path>` displays only metadata fields (ID, Title, Status, Verdict, Related Docs) from the YAML preamble.
- Files with no YAML preamble return: "Error: No YAML preamble detected."
- Missing optional fields are handled gracefully without errors or crashes.
- Content after the second `---` delimiter is never read or output.

**For FEAT-009 (`board_utils.py LIST`):**
- Running `python3 board_utils.py LIST` returns a formatted ASCII table containing all tasks with correct Task ID, Title, and Status (full board default).
- Tasks are sorted by pipeline stage (TO-DO -> IN-PROGRESS -> REVIEWING -> DONE).
- `--active-only` flag shows only TO-DO and IN-PROGRESS tasks; returns "No active tasks found in .board/" when none exist.
- `--last-n <count>` flag shows all active tasks plus the N most recently completed (DONE) tasks; gracefully handles fewer than N available.
- Both flags are mutually exclusive — providing both produces a clear error message.
- Adding or moving task files results in an immediate update to the LIST output without code changes.

# Revision Notes

Use this section for release-plan updates, additions, or sequencing changes as new information emerges.
