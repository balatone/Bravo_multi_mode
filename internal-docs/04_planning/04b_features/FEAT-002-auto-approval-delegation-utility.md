---
id: FEAT-002
title: Auto-Approval Delegation Utility
version: 1.0.0
status: APPROVED
created: 2026-07-15 14:45:00
updated: 2026-07-15 15:51:49
related_docs: ["PLAN-001", "REQ-002", "SPIKE-001"]
---
# Feature Overview

This feature implements automatic approval of target documents as part of the orchestrator's delegation process. When an orchestrator delegates a task and the target document is not yet approved, the system automatically approves it — preventing workflow stalls without requiring manual intervention at every handoff point. The implementation follows SPIKE-001 Option A: a dedicated `auto_approve_delegation()` utility function in `board_utils.py`.

# Objectives

- Eliminate workflow stalls caused by unapproved delegation targets (REQ-002 functional requirement #1).
- Provide an explicit, auditable auto-approval mechanism scoped strictly to the delegation context.
- Maintain compatibility with existing board-based task management system and document lifecycle gates.

# Scope

## In Scope

- Implementation of `auto_approve_delegation(doc_id)` function in `toolbox/board_utils.py`.
- The function reads the target document's YAML preamble, checks if status is not `APPROVED`, and updates it to `APPROVED` using `doc_utils.py update`.
- Integration guidance for the ad-hoc delegation flow: `discover_subagents.py → get_delegation_params.py → auto_approve_delegation(doc_id) → delegate via summon/tool call`.
- Logging of auto-approval events in specialist logs.

## Out of Scope

- Auto-approval outside of delegation context (per REQ-002 constraints).
- Changes to final review/approval gates for production deliverables.
- Modifications to `doc_utils.py` core logic — only usage of existing update mechanism.
- YAML recipe integration (recipes are reference artifacts only, not actively executed per SPIKE-001 findings).

# Inputs to Review

Before implementation begins, the following documents were reviewed:

- **REQ-002**: Defines functional requirement #1 for auto-approval on delegation, with constraints that approval must be scoped to delegation context only and cannot bypass final review gates.
- **SPIKE-001 (Option A)**: Recommends a dedicated `auto_approve_delegation()` function in `board_utils.py` as the cleanest approach — explicit intent, easy to test independently, no coupling to recipe parameters or middleware overhead.
- **PLAN-001**: Establishes FEAT-002 as Phase 1 of REQ-002 implementation, with sequencing dependency on being completed before FEAT-003 begins.

**Open Questions from SPIKE-001**: None directly impact this feature's scope. The three open questions (turn count source, context preservation scope, timeout storage) are relevant to FEAT-003 only.

# Implementation Tasks

1. **Review related requirements and spike findings**: Confirm understanding of auto-approval constraints from REQ-002 and the recommended Option A approach from SPIKE-001.
2. **Design `auto_approve_delegation()` function signature**: Define parameters (`doc_id`, optional `task_id` for logging), error handling (document not found, already approved, invalid status), and return value (success/failure with context).
3. **Implement the auto-approval logic in `board_utils.py`**:
   - Read target document YAML preamble from filesystem or via `doc_utils.py show`.
   - Check if current status is not `APPROVED`.
   - If not approved, use `doc_utils.py update` to set status to `APPROVED`.
   - Log the auto-approval event with timestamp and doc_id.
4. **Write unit tests**: Test cases for: document already approved (no-op), unapproved document (approval applied), invalid doc_id (error raised), non-existent file (error raised).
5. **Integration testing**: Verify that `auto_approve_delegation()` works correctly within the ad-hoc delegation flow alongside `discover_subagents.py` and `get_delegation_params.py`.
6. **Fix any defects found during verification**.

# Acceptance Criteria

- The `auto_approve_delegation(doc_id)` function exists in `board_utils.py` and is callable from orchestration code.
- When called with an unapproved document ID, the document's YAML preamble status is updated to `APPROVED`.
- When called with an already-approved document ID, no changes are made (idempotent behavior).
- Auto-approval events are logged in specialist logs following the format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: FAILED|INFO] - [DETAILS]`.
- The function raises appropriate errors for invalid doc_ids or non-existent documents.
- No auto-approval occurs outside of explicit delegation context calls (verified via code review).

# Definition of Done

- Tests written and passing.
- Code implemented in `board_utils.py` and reviewed against REQ-002 constraints.
- Relevant documentation updated (this FEAT document, PLAN-001 revision notes if needed).
- Integration with ad-hoc delegation flow verified.

# Dependencies / Risks

- **Dependency**: Requires access to target documents via filesystem path resolution; the orchestrator must know the `doc_id` before calling auto-approval.
- **Risk**: If `doc_utils.py update` mechanism changes between now and implementation, this feature may need adaptation. Mitigation: Monitor `doc_utils.py` for breaking changes during sprint cycle.
- **Constraint**: Auto-approval MUST only apply during delegation — never outside of explicit `auto_approve_delegation()` calls. This is enforced by design (no other code path triggers approval).

# Implementation Notes

- The function should accept a `task_id` parameter (optional) for enhanced logging context, allowing correlation between the auto-approval event and the specific delegation task.
- Per SPIKE-001's recommended integration pattern: `discover_subagents.py → get_delegation_params.py → auto_approve_delegation(doc_id) → delegate via summon/tool call`. The orchestrator should call this function immediately before the actual delegation step.
- Consider adding a configuration flag (e.g., `AUTO_APPROVE_ON_DELEGATION_ENABLED`) to allow toggling this behavior without code changes, though per REQ-002 it is expected to be always-on for delegation flows.

# Test Infrastructure Note

Tests for `board_utils.py` will live in the new top-level directory `python_tests/`, separate from Lua/Busted tests in `tests/`. This project has no existing Python test infrastructure — pytest configuration, fixtures, and conventions are greenfield.
