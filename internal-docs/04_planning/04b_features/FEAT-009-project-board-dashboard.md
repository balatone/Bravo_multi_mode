---
id: FEAT-009
title: Project Board Dashboard (board_utils.py LIST)
version: 1.0.0
status: APPROVED
created: 2026-07-16 15:00:38
updated: 2026-07-16 15:20:55
related_docs: ["REQ-006", "PLAN-004"]
---
# Feature Overview

This feature implements the `LIST` subcommand for `toolbox/board_utils.py`, providing a consolidated ASCII table dashboard of all tasks across `.board/` subdirectories. The command eliminates manual directory traversal (to-do/, in-progress/, done/) for project status assessment, giving agents and humans an immediate "birds-eye view" of the entire project pipeline.

**Implementation Status**: Not yet implemented. This document defines the complete specification for implementation.

# Objectives

- Provide a CLI subcommand (`python3 board_utils.py LIST`) that scans all `.board/` subdirectories and outputs a formatted ASCII table summarizing every task with its ID, Title, and Status.
- Support optional filtering flags: `--active-only` (TO-DO + IN-PROGRESS only) and `--last-n <count>` (active tasks plus N most recent DONE tasks).
- Sort output by pipeline stage: TO-DO -> IN-PROGRESS -> REVIEWING -> DONE.
- Handle edge cases gracefully: empty board, varying task counts, fewer than requested last-N completions.

# Scope

## In Scope

### Step 1: Directory Crawler (`scan_board`)

Implement `scan_board()` function in `toolbox/board_utils.py`:
- Walk through `.board/` subdirectories (to-do/, in-progress/, done/) relative to the repository root.
- For each `.md` task file found, extract metadata:
  - **Task ID**: Parse from filename prefix (e.g., `TASK-0007-...`) or read from YAML preamble's `id` field.
  - **Title**: Extract from filename after the ID dash, or read from YAML preamble's `title` field.
  - **Status**: Map directory name to status label: `to-do/` -> "TO-DO", `in-progress/` -> "IN-PROGRESS", `done/` -> "DONE".
- Return a list of task dictionaries: `[{"id": ..., "title": ..., "status": ...}, ...]`.

### Step 2: ASCII Table Formatter (`format_table`)

Implement `format_table(tasks)` function in `toolbox/board_utils.py`:
- Build an ASCII table with columns: Task ID, Title, Status.
- Calculate dynamic column widths based on maximum field length across all rows (using Python string formatting).
- Sort tasks by pipeline stage order: TO-DO -> IN-PROGRESS -> REVIEWING -> DONE.
- Print header row, separator line, and data rows.

### Step 3: CLI Integration (`LIST` subcommand)

Add `LIST` subcommand to `board_utils.py`'s argparse setup:
```python
list_p = subparsers.add_parser("list")
list_p.add_argument("--active-only", action="store_true", help="Show only TO-DO and IN-PROGRESS tasks")
list_p.add_argument("--last-n", type=int, metavar="COUNT", help="Active + last N completed tasks")
```

### Step 4: Flag-Based Filtering Logic

#### `--active-only` flag
- Filter the task list to include only tasks with status TO-DO or IN-PROGRESS.
- If no active tasks exist after filtering, output: "No active tasks found in .board/" and exit.
- DONE tasks are excluded entirely from this view.

#### `--last-n <count>` flag
- Include all active tasks (TO-DO + IN-PROGRESS) plus up to N most recently completed tasks from done/.
- If fewer than N completed tasks exist, show all available without error or warning.
- The `<count>` argument must be a positive integer; reject non-positive values with an error message.

#### Flag Conflict Handling
- `--active-only` and `--last-n <count>` are mutually exclusive.
- If both flags are provided simultaneously, output: "Error: --active-only and --last-n are mutually exclusive." and exit with code 1.

### Step 5: Edge Case Handling

| Scenario | Behavior |
|----------|----------|
| Empty board (no task files) | Output: "No active tasks found in .board/" |
| `--active-only` with no active tasks | Same as above: "No active tasks found in .board/" |
| `--last-n 5` with only 3 DONE tasks | Show all 3 completed tasks plus any active tasks (no error) |
| Task files without YAML preamble | Fall back to filename-based ID and title extraction |
| Varying numbers of tasks (1 vs. 100+) | Dynamic column width calculation ensures table formatting never breaks |

## Out of Scope

- Interactive task management via the LIST command (e.g., moving tasks directly from the list).
- Detailed view of individual task contents (use `cat` or existing board commands for this).
- Graphical/Web-based dashboarding.
- Real-time monitoring or polling; each invocation is a snapshot.
- Filtering by assignee, priority, or other metadata beyond status and directory location.

# Detailed Technical Specifications

## Directory Structure Assumptions

The `.board/` directory follows the standard structure:
```
.board/
  to-do/     -> Status: TO-DO
  in-progress/ -> Status: IN-PROGRESS
  done/      -> Status: DONE
```

Task files follow naming convention: `<TYPE>-<NNN>-<slug>.md` (e.g., `TASK-0007-implement-tooling-efficiency.md`).

## Pipeline Stage Sort Order

Tasks are sorted by status using this fixed order:
1. TO-DO
2. IN-PROGRESS
3. REVIEWING
4. DONE

This is implemented via a dictionary mapping:
```python
STATUS_ORDER = {"TO-DO": 0, "IN-PROGRESS": 1, "REVIEWING": 2, "DONE": 3}
tasks.sort(key=lambda t: STATUS_ORDER.get(t["status"], 99))
```

## Table Output Format Example

```
Project Board Dashboard
=======================
| Task ID      | Title                                        | Status       |
|--------------+----------------------------------------------+--------------|
| TASK-0007    | Implement Tooling Efficiency...              | IN-PROGRESS  |
| TASK-0001    | Populate Tech Stack Documentation            | DONE         |
| TASK-0002    | Orchestration Resilience Enhancements        | DONE         |
```

## CLI Usage Specification (from PLAN-004)

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

# Acceptance Criteria

- Running `python3 board_utils.py LIST` returns a formatted ASCII table containing all existing tasks with correct Task ID, Title, and Status mapping based on directory location (full board default).
- Tasks are sorted by pipeline stage: TO-DO -> IN-PROGRESS -> REVIEWING -> DONE.
- The output is readable and correctly handles varying numbers of tasks without breaking column alignment or formatting.
- Adding or moving a task file results in an immediate update to the LIST output on next invocation (no code changes needed).
- `--active-only` flag shows only TO-DO and IN-PROGRESS tasks; returns "No active tasks found in .board/" when no active tasks exist.
- `--last-n <count>` flag correctly limits completed tasks shown while including all active tasks; handles fewer than N available without error or warning.
- Providing both flags (`--active-only` and `--last-n`) produces a clear conflict error message: "Error: --active-only and --last-n are mutually exclusive." rather than undefined behavior.

# Implementation Milestones

| # | Milestone | Status | Notes |
|---|-----------|--------|-------|
| 1 | Directory crawler implemented in `scan_board()` | NOT STARTED | Scans to-do/, in-progress/, done/ subdirectories; extracts ID, Title, Status from filenames and preambles |
| 2 | ASCII table formatter implemented in `format_table()` | NOT STARTED | Dynamic column width calculation based on max field length across all rows |
| 3 | CLI LIST subcommand wired up with argparse | NOT STARTED | Adds --active-only (store_true) and --last-n (type=int, metavar=COUNT) flags |
| 4 | Flag filtering logic implemented | NOT STARTED | Handles active-only filter, last-n filter, and mutual exclusivity check |
| 5 | Edge case handling verified | NOT STARTED | Empty board, varying task counts, fewer than N completions, no preamble fallback |

# Definition of Done

- [ ] All acceptance criteria verified by running LIST command with all flag combinations.
- [ ] Edge cases tested: empty board, --active-only with no active tasks, --last-n with insufficient completed tasks, both flags provided simultaneously.
- [ ] Table formatting handles 1 task and 50+ tasks without breaking alignment.
- [ ] No new external dependencies added to board_utils.py (uses only standard library: os, argparse, re).

# Dependencies / Risks

| Type | Description | Mitigation |
|------|-------------|------------|
| Dependency | Relies on consistent directory structure within `.board/` (to-do/, in-progress/, done/ subdirectories must exist or be created). | Board creation commands already establish this structure; scanner handles missing directories gracefully. |
| Risk | Table formatting with dynamic data may break column alignment if task titles are extremely long. | Dynamic width calculation based on actual max field length across all rows ensures proper fitting. Truncation not needed — Python string formatting adapts to content. |
| Risk | Flag interaction complexity: --active-only and --last-n must be mutually exclusive. | Explicit check in CLI handler before processing; clear error message if both flags are provided. |
| Constraint | Performance constraint: scanner must remain performant as task count grows. | Simple directory listing with lightweight file parsing (only YAML preamble, not full body); no recursive deep scans of nested structures. |

# Implementation Notes

- The board_utils.py currently has `create`, `transition`, `log`, and `update` subcommands but lacks a `LIST` command. This feature adds the missing dashboard capability.
- Task status is determined by directory location (to-do/ -> TO-DO, in-progress/ -> IN-PROGRESS, done/ -> DONE), not from YAML preamble fields — this matches the assumption documented in REQ-006.
- For task ID and title extraction: prefer YAML preamble `id` and `title` fields if present; fall back to filename-based parsing (strip `.md`, extract prefix before first dash for ID, rest after second dash for Title).
- The `--last-n` flag should read DONE tasks from the done/ directory and sort them by creation date (from YAML preamble or filename timestamp) to determine "most recent."
