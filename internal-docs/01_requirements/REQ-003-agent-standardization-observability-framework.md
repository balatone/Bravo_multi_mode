---
id: REQ-003
title: Agent Standardization & Observability Framework
version: 1.0.0
status: DRAFT
created: 2026-07-15 13:26:59
updated: 2026-07-15 13:27:48
related_docs: ["RETRO-001", "FEAT-001"]
---
# Summary

Establish behavioral standards for all agents through mandatory post-task actions and prompt standardization, while introducing a specialist log utility script to enforce consistent naming conventions and entry formats across the observability layer.

# Business Context / Rationale

During FEAT-001 implementation, four interconnected gaps were identified that undermined agent reliability and cross-agent visibility:

1. **Inconsistent Post-Task Actions**: Subagents did not consistently execute mandatory post-task actions — logging activities via `.board/`, updating `logs/specialist_logs/` entries, and committing changes to the current branch. This led to lost work and incomplete branches.
2. **Prompt Fragmentation**: Instructions for using `toolbox` utilities (doc creation, status updates, task logging) were not explicitly included in agent prompts. Workers received generic instructions that did not cover tooling-specific operations, leading to inconsistent execution. Document creation directives were scattered across general worker prompts rather than concentrated in authorized archetype/specialist prompts (`analyst.md`, `reviewer.md`).
3. **No Standardized Prompt Snippet Library**: There was no standardized prompt snippet library covering document management, board logging, and specialist log formatting. Each agent interpreted these responsibilities independently, resulting in variable compliance levels.
4. **No Specialist Log Tooling**: While `toolbox/doc_utils.py` handles document metadata uniformly, there is no equivalent Python script to enforce consistent naming conventions and entry formats for specialist logs (`logs/specialist_logs/`). This led to ad-hoc log entries with inconsistent timestamps, status labels, and subtask descriptions.

Additionally, reviewers did not log activities in the specialist log when delegated a task, creating blind spots where tasks appeared stuck without any diagnostic information.

# Scope

## In Scope

- Mandatory post-task actions enforcement for all agents: board logging, specialist log updates, and branch commits with descriptive messages referencing the task ID.
- Consolidation of document creation and management directives from general worker prompts into `analyst.md` and `reviewer.md` archetype/specialist prompts.
- Development of a standardized prompt snippet library covering three categories: (1) creating/updating documents via `toolbox/doc_utils.py`, (2) logging activities on the current task via `.board/`, and (3) specialist log formatting with consistent structure.
- Implementation of a Python utility script (`toolbox/specialist_log.py`) to enforce consistent naming conventions and entry formats for specialist logs, mirroring the existing `doc_utils.py` pattern.

## Out of Scope

- Changes to the orchestrator's delegation or failure-handling logic (covered in REQ-002).
- Modifications to the board-based task management system structure itself.
- Implementation of new agent archetypes beyond what is needed for prompt snippet integration.

# Functional Requirements

1. **Mandatory Post-Task Logging via Board**: Every subagent MUST log activities on the current task via `.board/` upon task completion, including status transition and any relevant notes about the outcome.
2. **Mandatory Specialist Log Update**: Every subagent MUST update their entry in `logs/specialist_logs/<role>_<timestamp>.log` upon task completion using the format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: IN_PROGRESS|COMPLETE|FAILED] - [DETAILS]`.
3. **Mandatory Branch Commit**: Every subagent MUST commit all changes to the current branch with a descriptive message referencing the task ID (e.g., `feat(REQ-002): complete orchestration logic`).
4. **Document Creation Directive Consolidation**: Move all document creation and management directives from general worker prompts into `analyst.md` and `reviewer.md` archetype/specialist prompts, ensuring only authorized agents perform document operations. General worker prompts MUST NOT contain document creation instructions.
5. **Standardized Prompt Snippet Library — Document Management**: Develop a reusable prompt snippet for creating and updating documents via `toolbox/doc_utils.py`, covering both the CREATE command (document initialization) and UPDATE command (metadata/status changes). This snippet MUST be referenced by all agent archetype and specialist prompts that require document operations.
6. **Standardized Prompt Snippet Library — Board Logging**: Develop a reusable prompt snippet for logging activities on the current task via `.board/`, specifying the exact format, required fields, and timing of board updates relative to task lifecycle events.
7. **Standardized Prompt Snippet Library — Specialist Log Formatting**: Develop a reusable prompt snippet enforcing consistent specialist log entry format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: IN_PROGRESS|COMPLETE|FAILED] - [DETAILS]`, including rules for timestamp formatting (ISO 8601 or project-standard), status label values, and required detail fields.
8. **Specialist Log Utility Script (`toolbox/specialist_log.py`)**: Introduce a Python script to enforce consistent naming conventions and entry formats for specialist logs, mirroring the existing `doc_utils.py` pattern. The utility MUST support:
   - ISO 8601 or project-standard timestamp format enforcement.
   - Standardized status labels (`IN_PROGRESS`, `COMPLETE`, `FAILED`).
   - Required fields validation (role, subtask, status, details).
   - Automatic file creation with role-based naming convention (`logs/specialist_logs/<role>_<timestamp>.log`) when a log entry is written for a new agent.

# Success Criteria / Acceptance Criteria

- **Logging Compliance Rate**: Audit specialist log entries and board updates for completeness (timestamp, subtask, status) across a sample of completed tasks. Target: ≥95% compliance within two weeks of prompt updates.
- **Reviewer Visibility**: Verify that reviewer actions are logged in the specialist log when delegated a task. Track as a binary metric (logged / not logged) per review assignment. Target: 100% logging coverage for all delegated reviews.
- **Prompt Snippet Adoption**: Confirm all agent archetype and specialist prompts reference the standardized snippet library. Target: 100% coverage across `analyst.md`, `reviewer.md`, and worker prompts within one sprint cycle.
- **Specialist Log Utility Validation**: Verify that `toolbox/specialist_log.py` correctly enforces naming conventions, timestamp format, status labels, and required fields for all log entries. Target: 100% of log entries pass validation rules with zero ad-hoc formatting exceptions.

# Constraints / Guardrails / Dependencies

- Prompt snippet updates MUST be backward-compatible — existing agent prompts should continue to function after the snippets are introduced (migration via gradual adoption).
- The specialist log utility (`toolbox/specialist_log.py`) must follow the same API design patterns as `doc_utils.py` for consistency.
- Document creation directive consolidation requires coordination with the prompt engineering team and review of all existing worker prompts to identify directives that need migration.
- Dependency: Requires access to all agent archetype and specialist prompt files (`prompts/analyst.md`, `prompts/reviewer.md`, and any worker prompts).

# Timing / Deadline / Trigger

- Needed by: End of next sprint cycle, coordinated with REQ-002 completion.
- Trigger: These standardizations are required before any new multi-agent workflow that involves more than two distinct agent roles (orchestrator, subagent, reviewer) to ensure consistent observability and recovery behavior.

# Notes / Assumptions

- The specialist log utility should support both CLI usage (`uv run toolbox/specialist_log.py LOG --role <role> --subtask "<subtask>" --status STATUS --details "DETAILS"`) and programmatic import for use within agent prompts.
- Prompt snippet library should be stored as reusable markdown fragments in a dedicated directory (e.g., `prompts/snippets/`) to allow easy reference and versioning.
- The mandatory post-task actions are enforced through prompt instructions; actual compliance monitoring relies on the specialist log utility and periodic audits rather than automated enforcement at the code level.

# SMART Check

- **Specific:** The requirement clearly defines four distinct deliverables (post-task actions, directive consolidation, snippet library, log utility) with explicit formats, fields, and behavioral mandates for each.
- **Measurable:** Success criteria include quantifiable targets: ≥95% logging compliance, 100% reviewer visibility, 100% prompt snippet adoption, and zero formatting exceptions from the specialist log utility.
- **Achievable:** The changes are primarily documentation (prompt updates) and a new Python utility script; they build on existing patterns established by `doc_utils.py` and the current template system.
- **Relevant:** Directly addresses four action items from RETRO-001 (items 3, 4, 5, 6) that were identified as root causes of inconsistent agent behavior and poor observability during FEAT-001.
- **Time-bound:** Targeted for completion within one sprint cycle, with a trigger condition tied to multi-agent workflows involving more than two distinct roles.
