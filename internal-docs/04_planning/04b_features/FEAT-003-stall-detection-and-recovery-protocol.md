---
id: FEAT-003
title: Stall Detection and Recovery Protocol
version: 1.0.0
status: APPROVED
created: 2026-07-15 14:45:00
updated: 2026-07-15 15:51:49
related_docs: ["PLAN-001", "REQ-002", "SPIKE-001"]
---
# Feature Overview

This feature implements a hybrid stall detection mechanism with dual recovery path routing for subagent sessions. The system detects when a subagent has hit `max_turns` or become unresponsive, classifies the root cause, and routes to the appropriate recovery action: manual resume (for max_turns exhaustion and unresponsiveness) or re-delegation (for unexpected crashes/errors). This follows SPIKE-001 Option C — combining local turn counter tracking with configurable polling-based heartbeat monitoring.

# Objectives

- Detect subagent stalls caused by `max_turns` exhaustion, unresponsiveness, or unexpected errors (REQ-002 functional requirement #2).
- Route stall events to the correct recovery path based on root cause classification (REQ-002 requirements #3 and #4).
- Log all stall events with full context in orchestrator specialist logs (REQ-002 requirement #5).
- Persist recovery state updates to `.board/` task entries for traceability (REQ-002 requirement #6).

# Scope

## In Scope

### Phase A: Stall Detection Mechanisms
1. **max_turns exhaustion tracking**: The orchestrator tracks each subagent's turn count against its configured `max_turns` (from `get_delegation_params.py`). When the limit is reached, a stall event is raised with cause = `MAX_TURNS_EXHAUSTED`.
2. **Unresponsiveness timeout monitoring**: A configurable idle timeout (default 15 minutes per REQ-002 notes) that detects when no activity occurs for a subagent session. Polling interval: every 60 seconds. When exceeded, stall event raised with cause = `UNRESPONSIVE_TIMEOUT`.

### Phase B: Recovery Path Routing
3. **Manual Resume Path**: For stalls caused by `MAX_TURNS_EXHAUSTED` or `UNRESPONSIVE_TIMEOUT`, the system routes to manual resume — preserving subagent context and allowing a human operator to continue execution from where it left off.
4. **Re-Delegation Path**: For stalls caused by unexpected errors/crashes, the orchestrator re-delegates the task to another available agent with matching role specialization. If no alternative is available, escalation to human operator occurs as fallback.

### Phase C: Logging and State Persistence
5. **Stall Event Logging**: All stall events logged to `logs/specialist_logs/orchestrator_<timestamp>.log` following format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: FAILED] - [DETAILS]`. Details include subagent ID, cause of stall, and recovery path selected.
6. **Recovery State Persistence**: After any recovery action, the `.board/` task entry is updated with new status and assignee via `board_utils.py transition_task()` and `log_event()`.

## Out of Scope

- Changes to board-based task management system structure (per REQ-002 constraints).
- Modifications to subagent prompt content or behavioral standards (REQ-003 scope).
- Implementation of a specialist log utility script (REQ-003 scope).
- Real-time event-driven callbacks from subagents (SPIKE-001 rejected Option B in favor of hybrid approach).

# Inputs to Review

Before implementation begins, the following documents were reviewed:

- **REQ-002**: Defines 6 functional requirements covering stall detection, dual recovery paths, logging format, and state persistence. Success criteria require 100% correct recovery path selection and full traceability of all events.
- **SPIKE-001 (Option C)**: Recommends hybrid approach — local turn counter for max_turns tracking + configurable polling interval for heartbeat monitoring. Recovery routing table maps stall causes to appropriate paths. Three open questions identified that need resolution before implementation.
- **PLAN-001**: Establishes FEAT-003 as Phase 2 of REQ-002, dependent on FEAT-002 completion.

**Open Questions from SPIKE-001 (require team lead clarification)**:
1. **Turn Count Source**: Where does the orchestrator get real-time turn count data? The `get_delegation_params.py` provides configured max_turns but not current count. Resolution needed on whether to track locally via Rolecast API or local execution state.
2. **Context Preservation for Manual Resume**: What exactly constitutes "context" — conversation history, partial work results, board state? Scope definition required before implementation of manual resume path.
3. **Configurable Timeout Storage**: Where should the unresponsiveness timeout configuration be stored — config file, environment variable, or within `get_delegation_params.py`? Default: 15 minutes per REQ-002 notes.

# Implementation Tasks

## Phase A: Stall Detection Mechanisms

1. Review related requirements (REQ-002) and spike findings (SPIKE-001 Option C).
2. Implement `max_turns_tracker()` function in `board_utils.py`:
   - Accept subagent ID, configured max_turns, and current turn count as parameters.
   - Compare current turns against max_turns threshold.
   - Return stall status with cause = `MAX_TURNS_EXHAUSTED` when limit is reached.
3. Implement `unresponsiveness_monitor()` function in `board_utils.py`:
   - Accept subagent ID and last activity timestamp as parameters.
   - Compare elapsed time against configurable timeout threshold (default 15 minutes).
   - Return stall status with cause = `UNRESPONSIVE_TIMEOUT` when exceeded.
4. Write unit tests for both detection mechanisms covering edge cases: boundary values, invalid timestamps, missing data.

## Phase B: Recovery Path Routing

5. Implement `classify_stall(stall_cause)` function that maps causes to recovery paths:
   - `MAX_TURNS_EXHAUSTED` → MANUAL_RESUME
   - `UNRESPONSIVE_TIMEOUT` → MANUAL_RESUME
   - Any error/unknown cause → RE_DELEGATION
6. Implement `execute_manual_resume(task_id, subagent_id)` function:
   - Preserve subagent context (conversation history, partial work results).
   - Update board task status to reflect manual resume state.
   - Log the recovery event with full context.
7. Implement `execute_re_delegation(task_id, original_subagent_id)` function:
   - Query available agents matching role specialization via existing discovery mechanisms.
   - Select alternative agent and re-delegate the task.
   - Update board task assignee and status.
   - Log the recovery event with full context.
   - If no alternative agent available, escalate to human operator as fallback.

## Phase C: Logging and State Persistence

8. Implement `log_stall_event(subagent_id, cause, recovery_path)` function that writes to `logs/specialist_logs/orchestrator_<timestamp>.log` following REQ-002 format specification.
9. Integrate board state persistence using existing `board_utils.py transition_task()` and `log_event()`.
10. Write integration tests covering end-to-end stall detection → classification → recovery → logging flow.

# Acceptance Criteria

- **Stall Detection**: The system correctly identifies stalls caused by max_turns exhaustion, unresponsiveness timeout (configurable default 15 min), and unexpected errors.
- **Recovery Path Routing**: 100% of stall events follow the correct recovery path based on root cause classification:
  - `MAX_TURNS_EXHAUSTED` → Manual Resume
  - `UNRESPONSIVE_TIMEOUT` → Manual Resume
  - Unexpected error/crash → Re-delegation (with human escalation fallback if no alternative agent available)
- **Logging**: Every stall event has a corresponding log entry in `logs/specialist_logs/orchestrator_<timestamp>.log` with full context (subagent ID, cause, timestamp, recovery path).
- **State Persistence**: After any recovery action, the `.board/` task entry is updated with new status and assignee within 5 seconds of detection.

# Definition of Done

- Tests written and passing for all detection mechanisms, routing logic, and recovery paths.
- Code implemented in `board_utils.py` and reviewed against REQ-002 constraints.
- Relevant documentation updated (this FEAT document, PLAN-001 revision notes if needed).
- End-to-end validation completed with multi-step delegation chain scenario including stall injection tests.

# Dependencies / Risks

- **Dependency**: Requires `FEAT-002` to be complete first (per PLAN-001 sequencing), as both features share `board_utils.py` infrastructure and logging patterns.
- **Dependency**: Depends on team lead clarification of SPIKE-001's three open questions before implementation can begin.
- **Risk**: Turn count data source uncertainty — if the Rolecast API does not provide real-time turn counts, local tracking must be implemented within the orchestration flow. Mitigation: Design `max_turns_tracker()` to accept turn count as a parameter rather than fetching it internally.
- **Risk**: Context preservation scope ambiguity for manual resume — without clear definition of what "context" means, implementation may over-engineer or under-deliver on this requirement. Mitigation: Request explicit context scope from team lead before Phase B implementation begins.
- **Constraint**: Re-delegation MUST respect agent availability and role specialization constraints already defined in the prompt architecture (per REQ-002). If no matching agent is available, escalation to human operator is required as fallback.

# Implementation Notes

- The hybrid detection approach means two independent checks run during each orchestration cycle:
  - **Turn counter check**: Lightweight comparison of current turns vs. max_turns — runs after every subagent turn completion (no polling overhead).
  - **Heartbeat poll**: Runs every 60 seconds, checking last activity timestamp against timeout threshold — coarse-grained but sufficient for the 15-minute default timeout window.
- Per SPIKE-001's recommendation, YAML recipes are reference artifacts only and not actively executed. All stall detection logic must integrate into the ad-hoc delegation layer used in practice.
- The `log_stall_event()` function should follow the existing specialist log naming convention observed in `logs/specialist_logs/` (e.g., `orchestrator_20260715_144500.log`).

# Test Infrastructure Note

Tests for stall detection and recovery logic will live in `python_tests/test_toolbox/`, separate from Lua/Busted tests. Shared fixtures (repo root path, mock board state) should be defined in `python_tests/conftest.py`.
