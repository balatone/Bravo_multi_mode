---
version: 1.0.0
type: reference
description: "Adhoc delegation reference for the implementation → review loop. NOT a Goose recipe."
---

# Implementation Loop (Adhoc Delegation Reference)

This document describes the implementation and review cycle for a given Feature Plan (FEAT)
and Task ID (TASK). It is **NOT a Goose recipe** — it is a reference for the Lead to follow
using adhoc delegation. Recipes cannot handle the branching logic required (review verdict
determines next step), so the Lead must orchestrate each step manually.

## Prerequisites
1. A valid, `APPROVED` `FEAT-[ID]-[title].md` document exists in `internal-docs/04_planning/04b_features/`.
2. A valid task `TASK-[ID]-[title].md` exists in the `.board/` directory and is currently in a state that allows implementation (e.g., TO-DO, PLANNING).

## Workflow

### Phase 1: Initialization
1. **Pre-delegation preparation**:
   ```bash
   uv run toolbox/delegation_utils.py prepare \
       --doc-type FEAT \
       --task-id <TASK_ID> \
       --title "<feat title>" \
       --primary-doc <FEAT_ID> \
       --target-status IMPLEMENTING
   ```
2. **Log Event**: Log the start of the loop in the task using `toolbox/board_utils.py log`.

### Phase 2: Implementation
1. **Select Specialist**: Identify the appropriate worker specialist (e.g., `backend-engineer`, `frontend-engineer`) based on the FEAT document requirements.
2. **Delegate Implementation**: Delegate to the chosen specialist with instructions to implement the features described in `<FEAT-ID>`.
    *   **Instruction**: "Implement the features described in `<FEAT-ID>`. Ensure all code is written, follows project standards, and passes all tests. If a BUGFIX document is provided, address it as well."
    *   **Mandatory Parameters**: Every delegation MUST include `model` (in `role:<role>:<specialist>` format), `provider`, `extensions`, `max_turns`, and `async` (must be `false`).
3. **Verify Implementation**: Once the worker completes, verify that the implementation is complete (e.g., by checking files or running tests).

### Phase 3: Review
1. **Transition Task**:
   ```bash
   uv run toolbox/board_utils.py transition <TASK-ID> REVIEWING \
       --actor "team-lead" --message "Implementation complete. Starting review."
   ```
2. **Delegate Review**: Delegate to a reviewer specialist (e.g., `code-reviewer`) with instructions to review the implementation against `<FEAT-ID>`.
    *   **Instruction**: "Review the implementation for `<FEAT-ID>`. Check against requirements and coding standards. You MUST provide a verdict in your response: `APPROVED` or `REQUEST_CHANGES`."
    *   **Mandatory Parameters**: Every delegation MUST include `model` (in `role:<role>:<specialist>` format), `provider`, `extensions`, `max_turns`, and `async` (must be `false`).

### Phase 4: Decision & Loop Control
1. **If Verdict is `APPROVED`**:
    *   **Transition Task**:
        ```bash
        uv run toolbox/board_utils.py transition <TASK-ID> DONE \
            --actor "team-lead" --message "Implementation approved and completed."
        ```
    *   The loop is complete.
2. **If Verdict is `REQUEST_CHANGES`**:
    *   **BUGFIX Loop Protocol** (Mandatory — Lead MUST NOT fix issues directly):

        **BUGFIX Creation** (who creates depends on source):
        - **From REVIEW**: Delegate to a **reviewer** specialist to write the BUGFIX
          document based on their review findings. The BUGFIX must reference the
          original FEAT and the REVIEW that requested changes.
        - **From BUG report**: Delegate to an **analyst** specialist to write the
          BUGFIX document based on the bug report.

        **BUGFIX Execution Cycle** (same transitions regardless of source):
        1. **Transition to PLANNING**:
           ```bash
           uv run toolbox/board_utils.py transition <TASK-ID> PLANNING \
               --actor "team-lead" --message "BUGFIX planning started"
           ```
        2. **Delegate BUGFIX creation** to the appropriate specialist (reviewer or analyst).
        3. **Transition to IMPLEMENTING**:
           ```bash
           uv run toolbox/board_utils.py transition <TASK-ID> IMPLEMENTING \
               --actor "team-lead" --message "BUGFIX implementation started"
           ```
        4. **Delegate BUGFIX implementation** to a worker specialist.
        5. **Transition to REVIEWING**:
           ```bash
           uv run toolbox/board_utils.py transition <TASK-ID> REVIEWING \
               --actor "team-lead" --message "BUGFIX implementation complete, requesting review"
           ```
        6. **Delegate a new review** to a reviewer specialist. This produces a **new** `REVIEW` document.
        7. **Loop**: If the new review also returns `REQUEST_CHANGES`, repeat from step 2.
        8. **Depth Limit**: If more than 3 review cycles are needed, stop and flag to human operator.

        **Branch & Task Context**:
        - **BUGFIX from REVIEW**: Reuse the existing `feat/` branch and the existing task.
        - **BUGFIX from BUG**: Create a new `bugfix/` branch and a new task.

## Safety & Validation
- After every document creation or update, run `toolbox/validate_docs.py` to ensure integrity.
- Always log significant transitions in the task board.
- **Zero Implementation**: The Lead MUST NEVER write code or fix issues directly. All implementation work is delegated to worker specialists.
- **Task Reuse**: Reuse existing tasks for BUGFIX work from reviews. Never create a new task for a BUGFIX from a review.
- **Mandatory Parameters**: Every delegation MUST include all mandatory parameters (`model`, `provider`, `extensions`, `max_turns`, `async`). No exceptions.

## Delegation Failure Handling

If a delegation fails (subagent stalls, exceeds max turns, or returns an error):

1. **STOP** — Do not attempt to re-delegate automatically
2. **Run post-delegation verification**:
   ```bash
   uv run toolbox/delegation_utils.py verify \
       --task-id <TASK_ID> --role <role> --specialist <specialist>
   ```
3. **Classify the failure**:
   - **Max turns exhausted**: Normal condition — human operator can resume subagent
   - **Subagent stalled**: Human operator should investigate
   - **Verification failed**: Subagent did not complete properly
4. **Notify human operator** with task ID, failure classification, and verification errors
5. **WAIT** for human guidance before proceeding

**DO NOT**:
- Automatically re-delegate without human input
- Implement the work yourself
- Create a new task to replace the failed delegation
- Silently ignore the failure and move on
