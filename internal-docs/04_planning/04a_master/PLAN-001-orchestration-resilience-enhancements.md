---
id: PLAN-001
title: Orchestration Resilience Enhancements Plan
version: 1.0.0
status: APPROVED
created: 2026-07-15 14:45:00
updated: 2026-07-15 15:51:49
related_docs: ["REQ-002", "SPIKE-001"]
---
# Release Summary

This plan covers the implementation of REQ-002 (Orchestration & Resilience Enhancements), which addresses two critical workflow gaps identified during FEAT-001: automatic document approval on delegation and subagent stall recovery. The enhancements are designed to eliminate manual intervention bottlenecks in multi-step agentic workflows and provide deterministic failure recovery paths.

# Timebox

- Start: 2026-07-15
- End: TBD (end of next sprint cycle following REQ-003 approval)
- Duration: 1–2 sprints

# Release Goal

Deliver a resilient orchestration layer that automatically approves delegation targets and detects, classifies, and recovers from subagent stalls — enabling seamless multi-step agentic workflows without manual intervention at every handoff point.

# Features Included

1. **FEAT-002** — Auto-Approval Delegation Utility: Implements `auto_approve_delegation()` in `board_utils.py` to automatically approve target documents during the delegation process, preventing workflow stalls caused by unapproved delegation targets.
2. **FEAT-003** — Stall Detection and Recovery Protocol: Implements a hybrid stall detection mechanism (max_turns tracking + configurable unresponsiveness timeout) with dual recovery path routing (manual resume vs. re-delegation).

# Sequencing / Dependencies

- **Phase 1**: FEAT-002 must be implemented first, as it provides the foundational auto-approval utility that both features rely on for board state management consistency.
- **Phase 2**: FEAT-003 depends on FEAT-002's `board_utils.py` infrastructure and builds upon it with stall detection logic and recovery path routing.
- Both features depend on REQ-002 being APPROVED (currently in place).
- SPIKE-001 provides the technical analysis and recommended approaches (Option A for auto-approval, Option C hybrid for stall detection) that guide both feature implementations.

# Milestones

1. **Milestone 1**: FEAT-002 implementation complete — `auto_approve_delegation()` function added to `board_utils.py` with unit tests and integration into ad-hoc delegation flow.
2. **Milestone 2**: FEAT-003 Phase A (stall detection) implemented — hybrid max_turns tracking + unresponsiveness timeout monitoring operational.
3. **Milestone 3**: FEAT-003 Phase B (recovery routing) implemented — manual resume and re-delegation paths tested with full board state persistence and logging.
4. **Milestone 4**: End-to-end validation of both features in a multi-step delegation chain scenario.

# Risks / Constraints

- **Auto-Approval Scope Risk**: Auto-approval must be strictly scoped to the delegation context only — it cannot bypass final review/approval gates for production deliverables (per REQ-002 constraints). Mitigation: The `auto_approve_delegation()` function is explicitly gated behind delegation calls.
- **Stall Detection False Positives**: Network issues or long-running computations might trigger false unresponsiveness alarms. Mitigation: Configurable timeout with 15-minute default and human override via manual resume path (per SPIKE-001 recommendations).
- **Re-delegation Agent Availability**: If no alternative agent with matching specialization is available, re-delegation fails. Per REQ-002 notes, this requires escalation to the human operator — implemented as a fallback in recovery logic.
- **Context Preservation for Manual Resume**: The scope of "context" preserved during manual resume (conversation history, partial work results, board state) needs clarification before implementation begins. This is an open question from SPIKE-001.

# Success Criteria

- **Zero Stalls from Unapproved Delegation Targets**: No workflow stalls caused by unapproved delegation targets across all multi-step workflows post-implementation.
- **Stall Recovery Coverage**: Both recovery paths (manual resume and re-delegation) are exercised in test scenarios with 100% correct path selection based on root cause classification.
- **Recovery Traceability**: Every stall event has a corresponding log entry in `logs/specialist_logs/orchestrator_<timestamp>.log` and board state update within 5 seconds of detection, per REQ-002 functional requirements #5 and #6.

# Revision Notes

Initial plan created based on SPIKE-001 findings and recommendations (Option A for auto-approval, Option C hybrid for stall detection). Open questions from SPIKE-001 to be resolved with team lead before implementation begins:
1. Turn count data source clarification.
2. Manual resume context preservation scope definition.
3. Configurable timeout storage location decision.

# Test Infrastructure Note

Python utility scripts (`toolbox/board_utils.py`, `doc_utils.py`) will have Python tests placed in a new top-level directory `python_tests/` (parallel to existing `tests/`). This keeps them explicitly separated from Lua/Busted tests, which currently live in `tests/`. No pytest configuration or test infrastructure exists yet — this is a greenfield setup for the first Python tests.
