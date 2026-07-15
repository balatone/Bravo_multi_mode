---
id: REQ-002
title: Orchestration & Resilience Enhancements
version: 1.0.0
status: APPROVED
created: 2026-07-15 13:26:53
updated: 2026-07-15 13:58:04
related_docs: ["RETRO-001", "FEAT-001"]
---
# Summary

Enhance the orchestrator's delegation and failure-handling logic by implementing automatic approval of target documents during delegation and defining a clear subagent stall recovery protocol (manual resume vs. re-delegation).

# Business Context / Rationale

During FEAT-001 implementation, two critical orchestration gaps were identified that caused workflow stalls:

1. **Auto-Approval Gap**: When an orchestrator delegates a task to a subagent and the target document is not yet approved, the workflow stalls because there is no automatic approval trigger during delegation. This creates unnecessary bottlenecks in multi-step workflows where documents are created and reviewed sequentially.
2. **Subagent Stall Handling**: When a subagent hits `max_turns` or becomes unresponsive (stalls), there was no clear fallback path for resumption. Without distinction between stall types, stalled sessions can block downstream tasks indefinitely.

These gaps directly impact the project's ability to execute multi-step agentic workflows efficiently and require deterministic recovery behavior.

# Scope

## In Scope

- Automatic approval of target documents as part of the delegation process when the orchestrator delegates a task and the document is not yet approved.
- Definition and implementation of a subagent stall recovery protocol with two distinct paths:
  - Human-operator manual resume for `max_turns` or unresponsive stalls.
  - Re-delegation to another available agent for all other failure cases.

## Out of Scope

- Changes to the board-based task management system (`.board/`) structure itself.
- Modifications to subagent prompt content or behavioral standards (covered in REQ-003).
- Implementation of a specialist log utility script (covered in REQ-003).

# Functional Requirements

1. **Auto-Approval on Delegation**: When the orchestrator delegates a task and the target document is not yet approved, the system MUST automatically approve the target document as part of the delegation process, preventing workflow stalls without requiring manual intervention at every handoff point.
2. **Stall Detection**: The orchestrator MUST detect when a subagent has hit `max_turns` or become unresponsive (no activity for a configurable timeout period).
3. **Manual Resume Path**: When a stall is caused by `max_turns` exhaustion or unresponsiveness, the system MUST allow a human operator to manually resume the session and continue execution from where it left off.
4. **Re-Delegation Path**: In all other failure cases (e.g., subagent crashes, unexpected errors), the orchestrator MUST prefer re-delegation of the task to another available agent rather than attempting manual resumption.
5. **Stall State Logging**: The orchestrator MUST log stall events with full context (subagent ID, reason for stall, timestamp) in `logs/specialist_logs/orchestrator_<timestamp>.log` following the format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: FAILED] - [DETAILS]`.
6. **Recovery State Persistence**: After any recovery action (manual resume or re-delegation), the orchestrator MUST update the `.board/` task entry to reflect the new state and assignee, ensuring traceability of the recovery event.

# Success Criteria / Acceptance Criteria

- **Zero Stalls from Unapproved Delegation Targets**: Measure the number of manual interventions required due to auto-delegation gaps before and after implementation. Target: 0 stalls caused by unapproved delegation targets across all multi-step workflows.
- **Stall Recovery Coverage**: Verify that both recovery paths (manual resume and re-delegation) are exercised in test scenarios. Target: 100% of stall events follow the correct recovery path based on root cause classification.
- **Recovery Traceability**: Audit `.board/` entries and specialist logs for all recovery events. Target: Every stall event has a corresponding log entry and board state update within 5 seconds of detection.

# Constraints / Guardrails / Dependencies

- The orchestrator logic must remain compatible with the existing board-based task management system (`.board/`).
- Auto-approval MUST only apply during delegation — it does not bypass final review/approval gates for production deliverables.
- Re-delegation MUST respect agent availability and role specialization constraints already defined in the prompt architecture.
- Dependency: Requires access to subagent health monitoring data (turn count, last activity timestamp).

# Timing / Deadline / Trigger

- Needed by: End of next sprint cycle following REQ-003 approval.
- Trigger: These enhancements are required before any new multi-step feature implementation that involves delegation chains exceeding two levels.

# Notes / Assumptions

- The configurable timeout for unresponsiveness detection should default to a reasonable value (e.g., 15 minutes) and be adjustable via configuration.
- Manual resume requires the orchestrator to preserve subagent context state so execution can continue from the point of interruption without data loss.
- Re-delegation assumes at least one alternative agent with matching role specialization is available; if none exist, escalation to human operator is required.

# SMART Check

- **Specific:** The requirement clearly defines two distinct behaviors (auto-approval and stall recovery) with explicit conditions for each path.
- **Measurable:** Success criteria include quantifiable targets: zero stalls from delegation gaps, 100% correct recovery path selection, and full traceability of all events.
- **Achievable:** The changes are confined to orchestrator logic and do not require architectural overhauls; they build on the existing board-based task management system.
- **Relevant:** Directly addresses two HIGH-priority action items from RETRO-001 that were identified as root causes of workflow inefficiency during FEAT-001.
- **Time-bound:** Targeted for completion within one sprint cycle, with a trigger condition tied to multi-step delegation chains exceeding two levels.
