# Implementation Loop Recipe

This recipe automates the implementation and review cycle for a given Feature Plan (FEAT) and Task ID (TASK). It acts as an orchestrator that manages workers and reviewers to drive a feature from "Implementation" to "Done".

## Prerequisites
1. A valid, `APPROVED` `FEAT-[ID]-[title].md` document exists in `internal-docs/04_planning/04b_features/`.
2. A valid task `TASK-[ID]-[title].md` exists in the `.board/` directory and is currently in a state that allows implementation (e.g., TO-DO, PLANNING).

## Workflow

### Phase 1: Initialization
1. **Transition Task**: Use `toolbox/board_utils.py transition <TASK-ID> IMPLEMENTING --actor "Orchestrator" --message "Starting automated implementation loop for <FEAT-ID>"` to move the task to the `IMPLEMENTING` state.
2. **Log Event**: Log the start of the loop in the task using `toolbox/board_utils.py log`.

### Phase 2: Implementation
1. **Select Specialist**: Identify the appropriate worker specialist (e.g., `backend-engineer`, `frontend-engineer`) based on the FEAT document requirements.
2. **Delegate Implementation**: Delegate to the chosen specialist with instructions to implement the features described in `<FEAT-ID>`.
    *   **Instruction**: "Implement the features described in <FEAT-ID>. Ensure all code is written, follows project standards, and passes all tests. If a BUGFIX document is provided, address it as well."
3. **Verify Implementation**: Once the worker completes, verify that the implementation is complete (e.g., by checking files or running tests).

### Phase 3: Review
1. **Transition Task**: Use `toolbox/board_utils.py transition <TASK-ID> REVIEWING --actor "Orchestrator" --message "Implementation complete. Starting review."` to move the task to the `REVIEWING` state.
2. **Delegate Review**: Delegate to a reviewer specialist (e.g., `code-reviewer`) with instructions to review the implementation against `<FEAT-ID>`.
    *   **Instruction**: "Review the implementation for <FEAT-ID>. Check against requirements and coding standards. You MUST provide a verdict in your response: `APPROVED` or `REQUEST_CHANGES`."

### Phase 4: Decision & Loop Control
1. **If Verdict is `APPROVED`**:
    *   **Transition Task**: Use `toolbox/board_utils.py transition <TASK-ID> DONE --actor "Orchestrator" --message "Implementation approved and completed."` to move the task to `DONE`.
    *   The loop is complete.
2. **If Verdict is `REQUEST_CHANGES`**:
    *   **Create BUGFIX**: Create a new `BUGFIX` document using `toolbox/doc_utils.py CREATE BUGFIX "[Title describing changes]"` based on the reviewer's feedback. Note the ID of the newly created `BUGFIX` document.
    *   **Transition Task**: Use `toolbox/board_utils.py transition <TASK-ID> IMPLEMENTING --actor "Orchestrator" --message "Review requested changes. Implementing BUGFIX-<ID>." --related-docs '["<BUGFIX-ID>"]'` to move the task back to `IMPLEMENTING`.
    *   **Repeat**: Return to **Phase 2: Implementation**, but instruct the worker to address both `<FEAT-ID>` and the new `<BUGFIX-ID>`.

## Safety & Validation
- After every document creation or update, run `toolbox/validate_docs.py` to ensure integrity.
- Always log significant transitions in the task board.
