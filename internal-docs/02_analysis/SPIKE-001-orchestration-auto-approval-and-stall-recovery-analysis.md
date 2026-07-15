---
id: SPIKE-001
title: Orchestration Auto-Approval and Stall Recovery Analysis
version: 1.0.0
status: IN_REVIEW
created: 2026-07-15 13:58:44
updated: 2026-07-15 14:02:15
related_docs: ["REQ-002", "RETRO-001"]
---
# Executive Summary

This spike investigates two orchestration gaps identified during FEAT-001 that cause workflow stalls in multi-step agentic delegation chains. **Finding**: Both auto-approval on delegation and stall recovery (manual resume vs. re-delegation) are feasible to implement within the existing board-based task management architecture using Python utility scripts (`board_utils.py` extensions). The recommended approach is a two-phase implementation: (1) an `auto_approve_delegation()` function in `board_utils.py`, and (2) a stall detection module with dual recovery paths. Both changes are low-risk, localized to orchestrator logic, and fully compatible with the current `.board/` system.

# Question / Hypothesis

**Primary Questions:**
1. Can automatic document approval be safely integrated into the delegation process without bypassing final review gates?
2. What is the correct architecture for distinguishing between stall types (`max_turns` exhaustion vs. unresponsiveness) and routing them to appropriate recovery paths (manual resume vs. re-delegation)?

**Hypothesis:** Both features can be implemented as extensions to existing orchestrator tooling without architectural changes, with auto-approval gated by delegation context and stall detection using configurable timeout thresholds.

# Scope / Objectives

## In Scope
- Analysis of the current delegation flow in `recipes/execution-cycle.yaml`, `implement-feat.yaml`, and `review-feat.yaml`.
- Feasibility assessment for automatic document approval during delegation, including security implications.
- Design analysis for stall detection (max_turns tracking + configurable timeout) and recovery path routing.
- Evaluation of integration points with existing `board_utils.py` and `.board/` task management system.
- Assessment of logging requirements per REQ-002 functional requirement #5.

## Out of Scope
- Implementation code (covered by subsequent FEAT).
- Changes to the board-based task management system structure itself (per REQ-002 constraints).
- Modifications to subagent prompt content or behavioral standards (REQ-003 scope).
- Specialist log utility script implementation (REQ-003 scope).

# Methodology / Evidence

**Sources Reviewed:**
1. **REQ-002** (`internal-docs/01_requirements/REQ-002-orchestration-resilience-enhancements.md`) — primary requirements document with 6 functional requirements and success criteria.
2. **RETRO-001** (`internal-docs/06_retrospective/RETRO-001-feat-001-implementation-retrospective.md`) — retrospective documenting the two orchestration gaps as HIGH-priority action items from FEAT-001.
3. **`toolbox/board_utils.py`** (410 lines) — current board task management utility with `transition_task()`, `log_event()`, and state persistence logic.
4. **`recipes/execution-cycle.yaml`**, **`implement-feat.yaml`**, **`review-feat.yaml`** — YAML recipe artifacts defining the intended orchestration flow. **Note**: These are reference/design documents only; they are not actively executed by Goose because provider/model values cannot be dynamically assigned within hard-coded recipes. Actual delegation occurs through ad-hoc tool calls (e.g., `summon`, direct model invocation).
5. **`toolbox/get_delegation_params.py`** (107 lines) — provides `max_turns` configuration per complexity level (`low: 20`, `medium: 40`, `high: 60`). Used by ad-hoc delegation flow.
6. **`.board/status_board_protocol.md`** — board task lifecycle protocol defining status transitions and metadata requirements.
7. **Existing specialist logs** in `logs/specialist_logs/` — demonstrating current logging patterns (inconsistent format).

**Assumptions:**
- The orchestrator has programmatic access to document state via the filesystem.
- Subagent health data (turn count, last activity timestamp) is available through the Rolecast API or local tracking.
- At least one alternative agent with matching role specialization exists for re-delegation scenarios.
- **Ad-hoc delegation** is the active orchestration mechanism; all auto-approval and stall detection logic must integrate into this flow, not into YAML recipe execution.

# Findings

## Finding 1: Auto-Approval Is Feasible and Low-Risk

**Current State:** There is no auto-approval mechanism anywhere in the codebase. The `board_utils.py` has a `transition_task()` function that moves tasks between statuses, but document approval status (in YAML preambles of REQ/FEAT/REVIEW documents) is managed separately via `doc_utils.py`. No delegation step currently triggers any document state change — whether through ad-hoc delegation or recipe execution.

**Analysis:** Auto-approval can be implemented as an extension to the **ad-hoc delegation flow**:
- The orchestrator calls a new utility function (e.g., `auto_approve_delegation(doc_id, task_id)`) before delegating via ad-hoc tool calls.
- This function reads the target document's YAML preamble via direct file parsing or `doc_utils.py show`.
- If status is not `APPROVED`, it updates the preamble to `APPROVED` using `doc_utils.py update`.
- The approval is scoped to delegation context only — final review gates for production deliverables remain intact (per REQ-002 constraints).

**Implementation Path:** Extend `board_utils.py` with an `auto_approve_delegation()` function that the orchestrator calls as part of its ad-hoc delegation sequence. This integrates naturally into the existing pattern:
```
discover_subagents.py → get_delegation_params.py → auto_approve_delegation(doc_id) → delegate via summon/tool call
```

**Important Note:** The YAML recipes (`execution-cycle.yaml`, `implement-feat.yaml`, `review-feat.yaml`) are reference artifacts only — they cannot be actively executed because provider/model values are hard-coded and Goose does not support dynamic assignment within recipe files. All orchestration logic must therefore target the ad-hoc delegation path, which is what actually drives work through the SDLC pipeline in practice.

## Finding 2: Stall Detection Requires Dual-Mechanism Architecture

**Current State:** The system has no stall detection or recovery logic. Subagents receive `max_turns` from `get_delegation_params.py`, but there is no monitoring to detect when they hit that limit or become unresponsive. The ad-hoc delegation flow (used in practice) simply delegates and waits for completion with no timeout, fallback, or recovery mechanism — unlike the YAML recipes which define an intended pattern that is never actually executed.

**Analysis:** Stall detection requires two independent mechanisms:
1. **max_turns exhaustion tracking**: The orchestrator must track each subagent's turn count against its configured `max_turns`. When the limit is reached, this triggers a `MANUAL_RESUME` recovery path.
2. **Unresponsiveness timeout**: A configurable idle timeout (default 15 minutes per REQ-002 notes) that detects when no activity occurs for a subagent session. This also routes to `MANUAL_RESUME`.

**Recovery Path Routing:**

| Stall Cause | Recovery Path | Rationale |
|---|---|---|
| max_turns exhaustion | Manual Resume (human operator) | Subagent completed its allocated turns; context preserved for continuation |
| Unresponsiveness timeout | Manual Resume (human operator) | May need human assessment of why subagent stopped responding |
| Unexpected crash / error | Re-delegation to another agent | Task needs immediate recovery without human intervention |

## Finding 3: Stall State Logging Is Straightforward Extension

**Current State:** Specialist logs exist in `logs/specialist_logs/` but follow inconsistent naming conventions and formats. The orchestrator has no dedicated log file (`orchestrator_<timestamp>.log`). REQ-002 requires format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: FAILED] - [DETAILS]`.

**Analysis:** This is a straightforward addition — create an `orchestrator.log` writer function that appends stall events with full context (subagent ID, reason, timestamp). The existing log pattern from other specialists can be followed. REQ-003 will standardize this further via a specialist_log.py utility.

## Finding 4: Recovery State Persistence Is Already Supported

**Current State:** `board_utils.py`'s `transition_task()` and `log_event()` already handle state persistence to `.board/` task files with proper metadata updates (timestamp, status changes). The activity log body accumulates entries chronologically.

**Analysis:** No new infrastructure needed for recovery state persistence. After manual resume or re-delegation:
- Update the board task's status field via `transition_task()`.
- Update assignee via a new `update_assignee()` function (or extend existing logic).
- Log the recovery event via `log_event()`.

All of this is already supported by the current `.board/` system.

# Evaluation / Options

## Auto-Approval Implementation Options

### Option A: Dedicated Utility Function
Create `auto_approve_delegation(doc_id, task_id)` as a standalone function in `board_utils.py`. The orchestrator calls it explicitly before delegating.
- **Pros:** Clean separation of concerns; easy to test independently; explicit intent in orchestration code.
- **Cons:** Requires calling convention change in all delegation points.

### Option B: Integrated Flag in Delegation Flow
Add an `auto_approve` parameter to the ad-hoc delegation sequence (e.g., as a flag passed alongside `discover_subagents.py` and `get_delegation_params.py`). When true, the orchestrator auto-approves before delegating.
- **Pros:** Declarative; no new function calls needed; integrates naturally with existing delegation parameters.
- **Cons:** Tightly couples document approval logic to delegation parameter passing.

**Note:** The YAML recipes (`implement-feat.yaml`, `review-feat.yaml`) are reference artifacts only and not actively executed, so any recipe-based integration point is not viable in practice.

### Option C: Middleware Hook in board_utils.py
Add a `pre_transition_hook` mechanism where any task transition can trigger side effects (like auto-approving target documents).
- **Pros:** Most flexible; supports future hook-based extensions.
- **Cons:** Over-engineered for current needs; adds complexity to the simple transition flow.

**Recommended: Option A** — Clean, explicit, and aligns with REQ-002's constraint that auto-approval "MUST only apply during delegation." It keeps the intent clear in orchestration code without coupling approval logic to recipe parameters or introducing unnecessary middleware.

## Stall Detection Implementation Options

### Option A: Polling-Based Monitor
A periodic check (e.g., every 30 seconds) of subagent turn counts and last-activity timestamps against configured thresholds.
- **Pros:** Simple implementation; works with existing async delegation model.
- **Cons:** Introduces latency between stall occurrence and detection; resource overhead from polling.

### Option B: Event-Driven Callbacks
Subagents report status updates (turn count, heartbeat) during execution; the orchestrator reacts to events in real-time.
- **Pros:** Immediate detection; no polling overhead; precise turn tracking.
- **Cons:** Requires subagent cooperation and protocol changes; more complex integration with existing delegation flow.

### Option C: Hybrid Approach
Polling for unresponsiveness (coarse-grained, configurable interval) combined with event-based max_turns reporting from the orchestrator's own turn counter.
- **Pros:** Best of both worlds — precise turn tracking via local counter + reasonable polling for heartbeat monitoring.
- **Cons:** Slightly more complex than pure Option A.

**Recommended: Option C** — The orchestrator already tracks `max_turns` per delegation (via `get_delegation_params.py`). It can increment a local turn counter and detect exhaustion without subagent cooperation. For unresponsiveness, polling every 60 seconds is sufficient given the 15-minute default timeout.

# Risks / Constraints / Open Questions

## Risks
- **Auto-Approval Bypass Risk:** If auto-approval is not properly scoped to delegation context only, it could inadvertently approve documents that should require human review. Mitigation: Gate approval behind explicit `auto_approve_delegation()` calls; never auto-approve outside delegation flow.
- **Stall Detection False Positives:** Network issues or long-running computations might trigger false unresponsiveness alarms. Mitigation: Use configurable timeouts with reasonable defaults (15 min) and allow human override via manual resume path.
- **Re-delegation Agent Availability:** If no alternative agent with matching specialization is available, re-delegation fails. Per REQ-002 notes, this requires escalation to the human operator — implement as a fallback in the recovery logic.

## Constraints (from REQ-002)
- Must remain compatible with existing `.board/` task management system.
- Auto-approval MUST only apply during delegation — no bypass of final review/approval gates.
- Re-delegation MUST respect agent availability and role specialization constraints.
- No changes to board structure, subagent prompts, or specialist log utility (per scope exclusions).

## Open Questions
1. **Turn Count Source:** Where does the orchestrator get real-time turn count data? The `get_delegation_params.py` provides the *configured* max_turns, but not the current count. Does the Rolecast API provide this, or must we track it locally in the execution cycle recipe state?
2. **Context Preservation for Manual Resume:** REQ-002 notes that "manual resume requires the orchestrator to preserve subagent context state." What exactly constitutes "context" — conversation history, partial work results, board state? This needs clarification before implementation.
3. **Configurable Timeout Storage:** Where should the unresponsiveness timeout configuration be stored — in a config file, environment variable, or within `get_delegation_params.py`? Default: 15 minutes (per REQ-002 notes).

# Next Steps

1. **Create FEAT Document** (REQ-002 dependent): Define detailed implementation tasks for auto-approval utility and stall detection module based on this spike's recommendations.
2. **Clarify Open Questions**: Resolve the three open questions above with the team lead before implementation begins:
   - Turn count data source clarification.
   - Manual resume context preservation scope definition.
   - Configurable timeout storage location decision.
3. **Implement Auto-Approval** (Phase 1): Add `auto_approve_delegation()` function to `board_utils.py` and integrate into the ad-hoc delegation flow used by Lead/Team Lead prompts.
4. **Implement Stall Detection** (Phase 2): Build hybrid stall detection module with max_turns tracking and configurable unresponsiveness timeout, plus dual recovery path routing logic — integrated at the ad-hoc delegation layer.

# Companion Notes / Raw Evidence

Detailed investigation notes, raw data tables, code snippets from analyzed files, and exhaustive evidence are stored in `SPIKE-001-orchestration-auto-approval-and-stall-recovery-analysis.notes.md`.
