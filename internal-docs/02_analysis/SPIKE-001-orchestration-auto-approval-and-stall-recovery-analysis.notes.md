---
id: SPIKE-001-notes
title: Orchestration Auto-Approval and Stall Recovery Analysis — Companion Notes
version: 1.0.0
status: DRAFT
created: 2026-07-15 14:00:00
updated: 2026-07-15 14:00:00
related_docs: ["SPIKE-001"]
---

# Companion Notes — Raw Evidence and Detailed Analysis

## Code Path Details

### board_utils.py Key Functions Analyzed

#### `transition_task(task_id, new_status, actor, message, related_docs_raw=None)`
- **Relevance**: Primary mechanism for task state changes. Auto-approval could be integrated here as a pre-transition hook or post-transition side effect.
- **Current behavior**: Loads task YAML → updates status/updated fields → moves file to correct folder → git commit.
- **Extension point**: After loading metadata, check if `auto_approve` flag is set; if so, approve target document before transition.

#### `log_event(task_id, actor, message)`
- **Relevance**: Used for recording stall events per REQ-002 FR#5.
- **Current behavior**: Appends timestamped log entry to task body → git commit.
- **Extension point**: Also append to `logs/specialist_logs/orchestrator_<timestamp>.log` with format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: FAILED] - [DETAILS]`.

#### `get_task_path(task_id)` and `load_task(path)`
- **Relevance**: Used by auto-approval function to read target document status.
- **Current behavior**: Searches `.board/` recursively for task matching ID; parses YAML preamble + body.
- **Note**: These functions are board-specific (search `.board/`). For approving arbitrary documents, need a parallel `get_doc_path()` and `load_doc()` that searches `internal-docs/`.

### execution-cycle.yaml Delegation Flow

```
Step B: Delegate Implementation → implement-feat subrecipe
  ├─ discover_subagents.py --role <worker_role>
  ├─ get_delegation_params.py --id role:<role>:<specialist_id>
  └─ (implicit) delegate to LLM with task instructions

Step E: Delegate Code Review → review-feat subrecipe
  ├─ discover_subagents.py --role reviewer
  ├─ get_delegation_params.py --id role:reviewer:<specialist_id>
  └─ (implicit) delegate to LLM with review instructions
```

**Auto-approval integration points**: Before Step B and before Step E, the orchestrator should call `auto_approve_delegation(feat_id, task_id)` or `auto_approve_delegation(review-feat target document, task_id)`.

### get_delegation_params.py max_turns Config

| Complexity | max_turns |
|---|---|
| low | 20 |
| medium | 40 (default) |
| high | 60 |

**Stall detection implication**: The orchestrator needs to track the current turn count for each delegated subagent. Since `get_delegation_params.py` only returns the *configured* max_turns, not the *current* count, we need either:
- A local counter in the execution cycle recipe state (simplest).
- An API call to Rolecast to get real-time turn data (more accurate but adds dependency).

## Document Status Flow Analysis

### Current Approval States Across Document Types

| Document Type | Initial Status | Approved By | Auto-Approval Safe? |
|---|---|---|---|
| REQ | DRAFT → APPROVED | Human operator only | No — requires human review |
| FEAT | DRAFT → APPROVED | Human operator only | Yes, during delegation (per REQ-002) |
| REVIEW | DRAFT with verdict set by reviewer | Reviewer subagent | N/A — verdict is not a status field |
| BUGFIX | DRAFT → APPROVED | Human operator only | Yes, during delegation (per REQ-002) |
| PLAN | DRAFT → APPROVED | Human operator only | No — requires human review |

**Key insight**: Auto-approval should target FEAT and BUGFIX documents that are created as part of the delegation chain. It should NOT auto-approve REQ or PLAN documents, which require explicit human review.

## Stall Detection Threshold Analysis

### Unresponsiveness Timeout Configuration

| Parameter | Default Value | Configurable? | Rationale |
|---|---|---|---|
| Idle timeout | 15 minutes | Yes (per REQ-002 notes) | Balances false positives against detection latency |
| Polling interval | 60 seconds | Suggested | Frequent enough to detect stalls within ~1 min of threshold breach |
| max_turns tracking | Per-complexity config from get_delegation_params.py | No (inherited) | Already configured per delegation call |

### Stall Classification Decision Tree

```
Subagent becomes unresponsive or completes execution
    │
    ├─ Turn count == max_turns? ─── YES → MANUAL_RESUME path
    │                                    (preserve context, notify human operator)
    │
    ├─ No activity for > idle_timeout? ── YES → MANUAL_RESUME path
    │                                        (may need human assessment)
    │
    ├─ Error code / crash detected? ─── YES → RE-DELEGATION path
    │                                       (find alternative agent, re-delegate task)
    │
    └─ Other failure condition? ─────── YES → RE-DELEGATION path
                                         (default to re-delegation for unknown errors)
```

## Logging Format Specification

Per REQ-002 FR#5, stall events must be logged in `logs/specialist_logs/orchestrator_<timestamp>.log`:

```
[2026-07-15 14:30:00] - [DELEGATION_STALL_DETECTED] - [STATUS: FAILED] - [subagent_id=role:worker:backend-engineer, reason=max_turns_exhausted, task_id=TASK-0002, feat_id=FEAT-001]
```

Fields to include in DETAILS:
- `subagent_id`: Full specialist ID (e.g., `role:worker:backend-engineer`)
- `reason`: Classification of stall cause (`max_turns_exhausted`, `unresponsive_timeout`, `crash_error`, etc.)
- `task_id`: Board task ID affected
- `feat_id` / `bugfix_id`: Relevant feature/bugfix IDs for traceability

## Cross-Reference with Other Requirements

### REQ-003 (Agent Standardization & Observability)
- REQ-003 covers specialist log utility script — the stall logging format defined here should be compatible with that future utility.
- REQ-003 also covers standardized prompt snippets for post-task actions, which may include mandatory stall reporting by subagents themselves.

### RETRO-001 Action Items
| Retrospective Item | Priority | Covered By This Spike? |
|---|---|---|
| Auto-Approval on Delegation (#1) | HIGH | Yes — Finding 1 + Evaluation section |
| Subagent Stall Recovery Protocol (#2) | HIGH | Yes — Finding 2 + Evaluation section |
| Mandatory Post-Task Actions (#3) | HIGH | Partially — logging format defined, but enforcement is prompt-level (REQ-003) |
| Consolidate Document Creation Directives (#4) | MEDIUM | No — out of scope per REQ-002 constraints |
| Standardized Prompt Snippet Library (#5) | HIGH | No — covered by REQ-003 |
| Specialist Log Utility Script (#6) | MEDIUM | No — covered by REQ-003 |
