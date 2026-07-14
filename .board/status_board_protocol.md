---
id: PROTOCOL-001
title: Status Board Protocol (Lead Archetype)
version: 2.0.0
status: DONE
created: 2026-06-12 11:00:00
updated: 2026-07-01 12:14:00
related_docs: []
---

# Status Board Protocol (Lead Archetype)

## Purpose
Provide real-time, auditable visibility into the lifecycle of all project intake items that require orchestration.

The board is the execution tracker for:
- Requirements (`REQ`)
- Bugs (`BUG`)

The board does not replace the document system. It complements it by tracking work execution and current phase.

## Core Model

### 1. One board task per source document
Every `REQ` and every `BUG` must have exactly one corresponding board task.

- `REQ-xxx` -> one board `TASK-xxxx`
- `BUG-xxx` -> one board `TASK-xxxx`

The board task represents the lifecycle of that source document from intake to completion.

### 2. Dedicated task namespace
Board items must use a dedicated `TASK` namespace.

Recommended filename format:

`TASK-0001-short-descriptive-title.md`

Examples:
- `TASK-0001-historical-test-data-ingestion-for-demo.md`
- `TASK-0002-transaction-counterparty-consistency-fix.md`

This keeps board state separate from document IDs and makes the board easier to scan.

### 3. Required metadata
Each board task must contain the following fields in its YAML preamble:

- `id` - the board task ID, for example `TASK-0001`
- `title` - short descriptive title
- `status` - current lifecycle state
- `created` - creation timestamp
- `updated` - last update timestamp
- `primary_doc` - the corresponding `REQ` or `BUG` document ID
- `related_docs` - compact list of linked document IDs

Example:

```yaml
---
id: TASK-0001
title: Historical Test Data Ingestion for Demo
status: TO-DO
created: 2026-06-30 18:21:00
updated: 2026-07-01 12:14:00
primary_doc: REQ-005
related_docs: ["REQ-005"]
---
```

## Document Status vs Task Status
Document status and task status are separate concepts.

### Document status
This belongs to the artifact itself and indicates maturity of the document:
- `DRAFT`
- `APPROVED`
- `DEPRECATED`
- and other document lifecycle values used by the documentation system

### Board task status
This belongs to the execution workflow and indicates where the work is in the delivery pipeline:
- `TO-DO`
- `ANALYSING`
- `DESIGNING`
- `PLANNING`
- `IMPLEMENTING`
- `TESTING`
- `REVIEWING`
- `DONE`

Do not use document status to represent task progress.

## Lifecycle Management

### 1. Directory structure and states
The board is organized into folders representing the current state of the task. Moving a task between folders is the primary method of status tracking.

| Folder | Status | Meaning |
| :--- | :--- | :--- |
| `.board/to-do/` | `TO-DO` | Task exists, but no active orchestration has started yet. |
| `.board/in-progress/` | `ANALYSING` | Specialist is performing discovery or technical analysis. |
| `.board/in-progress/` | `DESIGNING` | Technical design, architecture, or schema modeling is in progress. |

**Note on `DESIGNING`**: This is an optional interim status. There is no dedicated design worker; design work may be performed by the Analyst (as part of `ANALYSING`) or the Lead (as part of `PLANNING`). Use `DESIGNING` only if the Lead explicitly separates design as a distinct phase. In most cases, tasks should transition directly from `ANALYSING` to `PLANNING`.
| `.board/in-progress/` | `PLANNING` | Lead is preparing or updating planning artifacts such as PLAN or FEAT. |
| `.board/in-progress/` | `IMPLEMENTING` | Active coding and development phase. |
| `.board/in-progress/` | `TESTING` | Verification, QA, or automated testing is in progress. |
| `.board/in-progress/` | `REVIEWING` | Code review or peer validation is underway. |
| `.board/done/` | `DONE` | Task is merged to `main` and complete. |

### 2. Creation rule
A board task must be created when the corresponding `REQ` or `BUG` is created.

This ensures:
- all intake items are tracked
- unstarted work remains visible
- the board can answer which requirements or bugs have not yet started

### 3. Initial state
New board tasks must start in `TO-DO`.

`TO-DO` is the normal initial state for any tracked `REQ` or `BUG`.

### 4. Source linkage
The board task must reference the source document as its `primary_doc`.

The `related_docs` list must remain a compact list of document IDs only, not file paths.

Typical entries may include:
- the source `REQ` or `BUG`
- analysis documents (`RAD`, `SPIKE`)
- planning documents (`PLAN`, `FEAT`)
- review documents (`REVIEW`)
- retrospective documents (`RETRO`), if relevant

## Orchestration Rules

### 1. Lead ownership
The Lead is the sole custodian of board state.

The Lead must:
- create the corresponding board task
- move it through the lifecycle states
- append activity log entries
- keep the board synchronized with the real execution state

### 2. Delegation handling
When the Lead delegates work to a specialist:
- the corresponding task must already exist
- the task must be in the appropriate active state
- the delegation must be logged in the task's activity log
- the log entry must include actor, action, and timestamp

### 3. Phase transitions
Every meaningful lifecycle change must be reflected on the board.

Examples:
- `TO-DO` -> `ANALYSING`
- `ANALYSING` -> `PLANNING`
- `PLANNING` -> `IMPLEMENTING`
- `IMPLEMENTING` -> `REVIEWING`
- `REVIEWING` -> `DONE`

### 4. Supporting documents
`RAD`, `SPIKE`, `PLAN`, `FEAT`, `REVIEW`, and `RETRO` are supporting artifacts.

They must be linked from the task through `related_docs`, but they must not become separate board identities unless they are themselves new `REQ` or `BUG` items requiring orchestration.

## Activity Log Rules
Every task file must contain a `# Activity Log` section.

Required log events include:
- task creation
- delegation to a specialist
- phase changes
- direct intervention by the Lead
- completion of delegated work
- review outcome
- completion or merge confirmation

Log entries must follow this format:

`[YYYY-MM-DD HH:MM:SS] - [Actor Name/Role] - [Action/Message]`

Example:

`[2026-06-30 18:21:00] - [lead] - Delegated analysis to technical-analyst for source doc REQ-005.`

## Completion Rules
A task may be moved to `DONE` only when:
- the relevant changes are complete
- review is approved
- the associated work is merged into `main`

The task must not be marked `DONE` merely because a document was written.

## Constraints
- **No Duplicate Tasks**: Do not create more than one board task for the same `REQ` or `BUG`.
- **No Orphan Tasks**: Every board task must point to exactly one source document via `primary_doc`.
- **Atomic Updates**: Every status transition and log entry MUST be followed by a `git commit`.
- **Consistency**: The board directory must not contain duplicate board files for the same source document.

## Migration Note
The board now uses the `TASK` namespace exclusively for active and historical board items.
Each `REQ` or `BUG` must have a single authoritative `TASK` card, and legacy source-named board files are no longer part of the supported model.
