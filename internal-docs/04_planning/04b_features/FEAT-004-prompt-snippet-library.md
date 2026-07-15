---
id: FEAT-004
title: Prompt Snippet Library Implementation
version: 1.0.0
status: APPROVED
created: "2026-07-15 17:48:00"
updated: "2026-07-15 18:20:00"
related_docs: ["PLAN-002", "REQ-003", "SPIKE-002"]
---

# Feature Overview

This feature creates a centralized prompt snippet library at `prompts/snippets/` containing three reusable markdown fragments for document management, board logging, and specialist log formatting. The snippets replace scattered inline directives currently embedded in archetype/specialist prompts (`analyst.md`, `reviewer.md`) which perform document creation operations. Worker prompts (`backend-engineer.md`, `generic-worker.md`, `qwen_worker_specialist.md`) do not create documents — they only modify the codebase and update activity logs — so their doc-creation directives are removed entirely rather than replaced with snippet references. Workers reference only `board-logging.md` and `specialist-log-formatting.md`. Versioning is handled by git history on the snippet files themselves. This addresses REQ-003 functional requirements #5, #6, and #7 (document management, board logging, and specialist log formatting snippets).

# Objectives

- Create `prompts/snippets/` directory with three category sub-files for centralized instruction storage.
- Remove doc-creation directives from worker prompts entirely (workers do not create documents); replace board logging and specialist log formatting directives with references to `board-logging.md` and `specialist-log-formatting.md`.
- Establish a clear reference pattern so archetype/specialist prompts can include standardized instructions via textual descriptions of snippet content.
# Scope

## In Scope

### Phase 1: Snippet Library Creation

1. **`prompts/snippets/doc-management.md`**: Contains the standardized CREATE and UPDATE command patterns for `doc_utils.py`, including YAML preamble management, template rendering notes, and validation requirements. This consolidates directives currently in:
   - `prompts/reviewer.md` lines 49-72

2. **`prompts/snippets/board-logging.md`**: Contains the exact command format for board activity logging via `board_utils.py log`, including required fields (TASK-ID, actor, message), timing rules relative to task lifecycle events, and git persistence notes. This consolidates directives currently in:
   - `prompts/worker/generic-worker.md` line 37

3. **`prompts/snippets/specialist-log-formatting.md`**: Contains the exact entry format `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: IN_PROGRESS|COMPLETE|FAILED] - [DETAILS]`, timestamp rules (project-standard `YYYY-MM-DD HH:MM:SS`), status label values, and error report formatting. This consolidates directives currently in:
   - `prompts/worker/generic-worker.md` lines 32-33
   - `prompts/reviewer.md` lines 49-50

**Note**: Worker prompts (`backend-engineer.md`, `generic-worker.md`, `qwen_worker_specialist.md`) do not create documents per their role definition — they only modify the codebase and update activity logs. Their doc-creation directives are removed entirely (not replaced with snippet references). Workers reference only `board-logging.md` and `specialist-log-formatting.md`.

### Phase 2: Prompt Migration

4. Update archetype/specialist prompts (`analyst.md`, `reviewer.md`) to reference the new snippets instead of containing inline directives. Each prompt includes a directive like:
   > "For document management operations, refer to `prompts/snippets/doc-management.md` for the standardized CREATE and UPDATE command patterns."

5. Update worker prompts (`backend-engineer.md`, `generic-worker.md`, `qwen_worker_specialist.md`): Remove doc-creation directives entirely (workers do not create documents). Replace board logging directive with reference to `board-logging.md`. Replace specialist log formatting directives with references to `specialist-log-formatting.md`.

## Out of Scope

- Implementation of `toolbox/specialist_log.py` (covered by FEAT-005).
- Compliance audit mechanism setup (covered by FEAT-006).
- Changes to `.board/` task management structure or orchestrator delegation logic.

# Inputs to Review

Before implementation begins, the following documents were reviewed:

- **REQ-003**: Defines 8 functional requirements covering prompt standardization (FR#4), snippet library creation (FRs #5-7), specialist log utility (FR#8), and compliance validation. Success criteria require >=95% format compliance within two weeks of deployment.
- **SPIKE-002 Finding 2**: Recommends `prompts/snippets/` directory with three category subdirectories (`doc-management.md`, `board-logging.md`, `specialist-log-formatting.md`). Option A (centralized snippets) is strongly preferred over inline duplication or YAML/JSON formats. Naming convention: `<category>.md` files in the snippets root.
- **PLAN-002**: Establishes FEAT-004 as Phase 1 of REQ-003, with all worker prompt directives removed and replaced with snippet references in a single update cycle.

**Open Questions from SPIKE-002 (resolved)**:
1. **Snippet Reference Mechanism** — RESOLVED: The orchestrator will reference specific snippets in the instruction delegated to each subagent. Subagents are instructed to read the specified snippet files at runtime. Snippets must be self-contained and complete enough for an agent to follow without external context.
2. **Example Entries in Snippets** — RESOLVED: Yes, include correct vs. incorrect formatting examples. While tools return correct syntax when used incorrectly, examples reduce the chance of subagents using wrong format by providing a visual reference alongside command syntax. This is especially important for specialist-log-formatting.md where bracket/field conventions are easy to get wrong.

# Implementation Tasks

## Phase 1: Create Snippet Library Files

1. Create `prompts/snippets/` directory (if it does not exist).
2. Author `prompts/snippets/doc-management.md`:
   - Include standardized CREATE command pattern for `doc_utils.py`.
   - Include standardized UPDATE command pattern with YAML preamble protection rules.
   - Add validation notes referencing `python3 toolbox/validate_docs.py` execution requirement.
   - Document the template rendering flow (metadata extraction, body generation).

3. Author `prompts/snippets/board-logging.md`:
   - Include exact `board_utils.py log` command format: `uv run toolbox/board_utils.py log <TASK-ID> --actor "<role>" --message "<msg>"`.
   - Document required fields and their constraints (TASK-ID must exist in `.board/`, actor is the role name, message describes the event).
   - Specify timing rules: log events at task transitions, completion, and error conditions.

4. Author `prompts/snippets/specialist-log-formatting.md`:
   - Include exact entry format: `[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]`.
   - Specify timestamp format: `YYYY-MM-DD HH:MM:SS` (project standard, matching `doc_utils.py`).
   - List valid status labels: `IN_PROGRESS`, `COMPLETE`, `FAILED`.
   - Include example entries showing both correct and incorrect formatting to reduce agent errors with bracket/field conventions.

## Phase 2: Update Archetype/Specialist Prompts

5. Update `prompts/analyst.md`: Replace inline document management directives with references to the appropriate snippet files. Add a "Standardized Instructions" section that points to each relevant snippet.

6. Update `prompts/reviewer.md`: Replace inline directives (currently at lines 49-72) with references to `doc-management.md` and `specialist-log-formatting.md`. Preserve any reviewer-specific logic not covered by snippets.

## Phase 3: Update Worker Prompts (Board Logging & Specialist Log Formatting Only)

Workers do not create documents — they only modify the codebase and update activity logs. Their doc-creation directives are removed entirely; they reference only `board-logging.md` and `specialist-log-formatting.md`.

7. Update `prompts/worker/backend-engineer.md`: Remove the inline document creation directive at line 17 entirely (no snippet reference needed — workers do not create documents). No other changes required for this prompt.

8. Update `prompts/worker/generic-worker.md`: Replace inline directives at lines 21-37:
   - Lines 21-33 (doc creation + specialist log formatting): Remove doc creation portion entirely; replace specialist log formatting directive with reference to `specialist-log-formatting.md`.
   - Line 37 (board logging): Replace with reference to `board-logging.md`.

9. Update `prompts/worker/qwen_worker_specialist.md`: Remove the inline document creation directive at line 17 entirely (no snippet reference needed — workers do not create documents). No other changes required for this prompt.

## Phase 4: Validation and Testing

10. Run `python3 toolbox/validate_docs.py` on all modified prompt files to ensure YAML preamble integrity is maintained after edits.
11. Verify that each snippet file is valid markdown (no broken references, consistent formatting).
12. Verify that all worker prompts still function correctly post-migration — each worker should be able to perform required actions using the new snippet-based instructions.

# Risks / Constraints

- **Snippet Content Accuracy**: Snippets must accurately reflect the actual behavior of `doc_utils.py` and `board_utils.py`. Any mismatch between snippet instructions and tool capabilities will cause agent errors. Mitigation: Cross-reference each snippet command against the source code of the referenced utilities.
- **Snippet Content Accuracy**: Snippets must accurately reflect the actual behavior of `doc_utils.py` and `board_utils.py`. Any mismatch between snippet instructions and tool capabilities will cause agent errors. Mitigation: Cross-reference each snippet command against the source code of the referenced utilities.
- **Prompt File Size Increase**: Adding snippet references increases prompt file size slightly. This is acceptable as long as total token count stays within model context limits for all supported agents.

# Success Criteria

- All three snippet files exist in `prompts/snippets/` with complete, accurate content covering the required command patterns and format specifications.
- Archetype/specialist prompts (`analyst.md`, `reviewer.md`) reference snippets instead of containing inline directives for document management, board logging, or specialist log formatting.
- Doc-creation directives fully removed from worker prompts (`backend-engineer.md`, `generic-worker.md`, `qwen_worker_specialist.md`); board logging and specialist log formatting directives replaced with references to the appropriate snippets — no worker prompt should contain duplicate instructions that overlap with snippet content after migration.
- All modified files pass `python3 toolbox/validate_docs.py` without errors.

# Revision Notes

Initial feature spec created based on SPIKE-002 Finding 2 recommendations (Option A: centralized snippets in `prompts/snippets/`). Three category sub-files identified from the spike analysis. All worker prompt directives replaced with snippet references in a single update cycle per PLAN-002.
