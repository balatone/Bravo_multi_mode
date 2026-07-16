---
id: REQ-006
title: Project Board Dashboard (board_utils.py LIST)
version: 1.0.0
status: APPROVED
created: 2026-07-16 13:40:00
updated: 2026-07-16 13:37:35
related_docs: []
---
# Summary

Implement a `LIST` command for the `board_utils.py` utility that provides a high-level, formatted dashboard view of all tasks currently managed in the `.board/` directory.

# Business Context / Rationale

The current method for assessing project status requires manual traversal of the `.board/` directory structure (e.g., checking `to-do/`, `in-progress/`, and `done/`). This is inefficient for agents and humans alike. A centralized `LIST` command provides an immediate "birds-eye view" of the entire project pipeline, facilitating better orchestration and planning.

# Scope

## In Scope

- Addition of the `LIST` subcommand to `board_utils.py`.
- Implementation of a directory crawler that scans `.board/` subdirectories.
- Parsing of task files (e.g., `.md` files) to extract Task ID, Title, and Status.
- Outputting a formatted ASCII table summarizing all tasks.

## Out of Scope

- Interactive task management via the `LIST` command (e.g., moving tasks directly from the list).
- Detailed view of individual task contents (this should remain a separate function or use `cat`).
- Graphical/Web-based dashboarding.

# Functional Requirements

1. The `LIST` command must scan all subdirectories within `.board/`.
2. For each task found, the utility must extract:
    * Task ID (from filename or preamble).
    * Title (from filename or preamble).
    * Current Status (based on the directory it resides in).
3. The output must be a single, consolidated table sorted by status (e.g., TO-DO -> IN-PROGRESS -> REVIEWING -> DONE).
4. If no tasks are found, the command should return: "No active tasks found in .board/".

# Success Criteria / Acceptance Criteria

- Running `python3 board_utils.py LIST` returns a table containing all existing tasks with correct status mapping.
- The output is readable and correctly handles varying numbers of tasks without breaking formatting.
- Adding or moving a task file results in an immediate update to the `LIST` output.

# Constraints / Guardrails / Dependencies

- **Dependency**: Relies on the consistent directory structure within `.board/`.
- **Constraint**: Must be highly performant; scanning should not become a bottleneck as the number of tasks grows.

# Timing / Deadline / Trigger

- Trigger: Identified as a friction point during TASK-0006 execution.

# Notes / Assumptions

- Assumption: Task status is primarily determined by the directory location within `.board/`.

# SMART Check

- **Specific:** Yes, defines a specific subcommand and output format.
- **Measurable:** Yes, can be verified by comparing table output to actual file locations.
- **Achievable:** Yes, standard filesystem traversal and string parsing task.
- **Relevant:** Yes, critical for efficient project orchestration.
- **Time-bound:** N/A (Triggered by current friction).
