---
id: PLAN-002
title: Agent Standardization & Observability Framework Plan
version: 1.0.0
status: APPROVED
created: "2026-07-15 17:48:00"
updated: "2026-07-15 18:20:00"
related_docs: ["REQ-003", "SPIKE-002"]
---

# Release Summary

This plan covers the implementation of REQ-003 (Agent Standardization & Observability Framework), which addresses four critical gaps identified during SPIKE-002 and RETRO-001: scattered document creation directives across worker prompts, inconsistent specialist log formatting, missing prompt snippet library for reusable instruction fragments, and lack of a compliance audit mechanism. The framework consolidates agent behavioral standards into centralized snippets, provides a programmatic logging utility mirroring the established `doc_utils.py` CLI pattern, and introduces validation tooling to enforce 95%+ compliance within two weeks of deployment.

# Timebox

- Start: 2026-07-15
- End: TBD (end of next sprint cycle following REQ-003 approval)
- Duration: 1–2 sprints

# Release Goal

Deliver a standardized agent observability framework with centralized prompt snippets, a programmatic specialist log utility (`toolbox/specialist_log.py`), and automated compliance validation — enabling consistent cross-agent behavior without modifying core orchestration logic or board task management infrastructure.

# Features Included

1. **FEAT-004** — Prompt Snippet Library Implementation: Creates `prompts/snippets/` directory with three category files (`doc-management.md`, `board-logging.md`, `specialist-log-formatting.md`) containing reusable instruction fragments for document creation, board logging, and specialist log formatting.
2. **FEAT-005** — Specialist Log Utility Development: Implements `toolbox/specialist_log.py` with LOG/SHOW/CLEAN commands mirroring `doc_utils.py` CLI patterns, supporting both programmatic import and CLI usage.
3. **FEAT-006** — Compliance Audit & Validation Mechanism: Establishes periodic audit processes using the VALIDATE command from FEAT-005 to verify log format compliance across all agent roles, with reporting dashboards for tracking 95%+ compliance targets.

# Sequencing / Dependencies

- **Phase 1**: FEAT-004 must be implemented first — it creates the foundational snippet library that subsequent features and prompt updates depend on.
- **Phase 2**: FEAT-005 depends on no other feature but should reference FEAT-004's `specialist-log-formatting.md` for entry format standards in its implementation documentation. The utility must mirror `doc_utils.py` API patterns (module-level constants, sys.argv CLI parsing, validation functions).
- **Phase 3**: FEAT-006 depends on both FEAT-004 and FEAT-005 — it uses the specialist log VALIDATE command from FEAT-005 as its primary audit mechanism.
- All features depend on REQ-003 being APPROVED (currently in place).
- SPIKE-002 provides the technical analysis, design recommendations, and risk assessments that guide all three feature implementations.

# Milestones

1. **Milestone 1**: FEAT-004 complete — `prompts/snippets/` directory created with three category files; archetype/specialist prompts updated to reference snippets instead of inline directives.
2. **Milestone 2**: FEAT-005 Phase A (LOG command) implemented and tested — `specialist_log.py` creates/appends entries in standardized format, validates status labels, auto-generates timestamps.
3. **Milestone 3**: FEAT-005 Phase B (SHOW + VALIDATE commands) complete — log querying with role/date filtering operational; entry validation against required format returning correct exit codes.
4. **Milestone 4**: FEAT-006 audit process established — periodic compliance checks running against all specialist logs, reporting non-compliant entries with line numbers and specific issues.

# Risks / Constraints

- **Agent Compliance Without Automated Enforcement**: The >=95% compliance target relies on prompt instructions alone. No code-level enforcement mechanism exists for agent behavior. Mitigation: The `specialist_log.py VALIDATE` command enables periodic audits; the orchestrator can check log format during task transitions to flag non-compliant entries early (per FEAT-006).
- **Log File Naming Convention Conflict**: Existing files use two different naming patterns (`<role>_<YYYYMMDD_HHMMSS>.log` vs `<role>-YYYY-MM-DD.log`). Introducing a new convention via `specialist_log.py` will coexist with legacy formats. Mitigation: Standardize on underscore-based format going forward; VALIDATE command flags non-conforming filenames during audits (per FEAT-005).

- **Constraint**: The specialist log utility must follow the same API design patterns as `doc_utils.py` for consistency, including module-level constants, sys.argv CLI parsing, and returning None on failure with stdout error messages.

# Success Criteria

- **Snippet Library Completeness**: All three required snippet categories (`doc-management.md`, `board-logging.md`, `specialist-log-formatting.md`) created in `prompts/snippets/` with clear reference patterns for agent consumption.
- **Specialist Log Utility Functionality**: `toolbox/specialist_log.py` supports LOG (create/append), SHOW (query/filter), and VALIDATE (audit) commands; mirrors `doc_utils.py` CLI pattern exactly; importable as a Python module with programmatic API access.
- **Compliance Rate >=95%**: Within two weeks of prompt updates, >=95% of specialist log entries conform to the standardized format `[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]` across all agent roles.
- **Worker Prompt Migration Complete**: Doc-creation directives fully removed from worker prompts (`backend-engineer.md`, `generic-worker.md`, `qwen_worker_specialist.md`); board logging and specialist log formatting directives replaced with appropriate snippet references — no worker prompt contains document creation instructions.

# Revision Notes

Initial plan created based on SPIKE-002 findings and recommendations:
1. Prompt snippets stored in `prompts/snippets/` with three category subdirectories (Option A from SPIKE-002).
2. Specialist log utility follows `doc_utils.py` CLI pattern with LOG/SHOW/CLEAN commands (mirroring the design analysis in Finding 3 of SPIKE-002).
3. Worker prompts will have all document creation directives removed and replaced with snippet library references in a single update cycle.

# Open Questions from SPIKE-002 (resolved)

1. **Snippet Reference Mechanism** — RESOLVED: The orchestrator will reference specific snippets in the instruction delegated to each subagent. In other words, the subagent is instructed to read the specified snippet files at runtime. This means snippets must be self-contained and complete enough for an agent to follow without external context.
2. **Example Entries in Snippets** — RESOLVED: Yes, include examples showing correct vs. incorrect formatting. While tools return correct syntax when used incorrectly, examples reduce the chance of subagents using wrong format by providing a visual reference alongside command syntax. This is especially important for specialist-log-formatting.md where bracket/field conventions are easy to get wrong.
