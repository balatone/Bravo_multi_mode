---
id: FEAT-006
title: Compliance Audit & Validation Mechanism
version: 1.0.0
status: APPROVED
created: "2026-07-15 17:48:00"
updated: "2026-07-15 18:20:00"
related_docs: ["PLAN-002", "REQ-003", "SPIKE-002"]
---

# Feature Overview

This feature establishes a compliance audit mechanism for verifying that all specialist log entries conform to the standardized format defined in REQ-003 FR#2. The audit leverages the VALIDATE command from FEAT-005 (`toolbox/specialist_log.py`) as its primary tooling, running periodic checks across all agent roles and producing structured reports on compliance rates and non-compliant entries. This addresses REQ-003's success criterion of >=95% format compliance within two weeks of prompt updates and provides the observability infrastructure needed to track enforcement effectiveness over time.

# Objectives

- Establish automated or semi-automated periodic audits of all specialist log files against the required entry format.
- Produce structured compliance reports showing pass/fail rates per role, per date range, and overall.
- Provide actionable feedback on non-compliant entries (line numbers, specific issues) to enable targeted remediation.
- Integrate audit results into the board-based task management system for traceability.

# Scope

## In Scope

### Phase 1: Audit Execution Framework

1. **Audit Script**: Create a lightweight audit script at `toolbox/compliance_audit.py` (or implement as a shell-invoked workflow using existing tools) that:
   - Scans all files in `logs/specialist_logs/`.
   - Runs `specialist_log.py VALIDATE` on each file.
   - Collects results into a structured report.

2. **Report Format**: Each audit produces a summary containing:
   - Total log files audited.
   - Files passing validation (compliant count).
   - Files failing validation (non-compliant count with compliance rate percentage).
   - Per-role breakdown of compliance rates.
   - List of non-compliant entries with file, line number, and specific issue description.

3. **Audit Scheduling**: Define audit frequency — recommended: run after each major task completion or at minimum weekly during the initial enforcement period (first two weeks post-deployment).

### Phase 2: Reporting and Integration

4. **Report Output Location**: Store audit reports in `internal-docs/05_reports/compliance_audit_<YYYYMMDD_HHMMSS>.md` for historical tracking and trend analysis.

5. **Board Integration**: Log audit results to the relevant TASK entries via `board_utils.py log_event()` so that task owners can see compliance status alongside their work progress.

6. **Compliance Dashboard Concept**: While not implementing a full dashboard, structure reports in a way that supports future automation (e.g., JSON output option for integration with CI/CD or monitoring tools).

### Phase 3: Remediation Workflow

7. **Non-Compliant Entry Flagging**: For entries that fail validation, the audit report should categorize issues by type:
   - Missing DETAILS field.
   - Invalid status label (not one of IN_PROGRESS, COMPLETE, FAILED).
   - Malformed timestamp (incomplete or wrong format).
   - Incorrect bracket usage in subtask or status fields.
   - Non-conforming filename pattern.

8. **Remediation Guidance**: The audit report should include actionable guidance for fixing non-compliant entries — e.g., "Update prompt instructions to use `specialist_log.py LOG` command instead of manual file writes" or "Ensure timestamp includes complete seconds component (not xx placeholders)."

## Out of Scope

- Implementation of `toolbox/specialist_log.py` (covered by FEAT-005).
- Creation of the snippet library (`prompts/snippets/`) — covered by FEAT-004.
- Real-time compliance monitoring during agent execution (audit is periodic, not continuous).
- Automated remediation of non-compliant entries (human review required for existing logs).
- Changes to board task management structure or orchestrator delegation logic.

# Inputs to Review

Before implementation begins, the following documents were reviewed:

- **REQ-003**: Defines success criterion ">=95% compliance within two weeks of prompt updates" and functional requirement #2 (specialist log format standardization). The audit mechanism is the primary enforcement tool for tracking this metric.
- **SPIKE-002 Finding 1**: Documents current state: none of the 8 existing specialist log files fully comply with the required format. Issues include missing DETAILS fields, incomplete timestamps (`xx` placeholders), inconsistent bracket usage, and mixed naming conventions. This establishes the baseline compliance rate (near 0%) against which improvement will be measured.
- **SPIKE-002 Finding 3**: Notes that `specialist_log.py VALIDATE` returns exit code 0 for compliant files and 1 for violations — this is the primary audit mechanism. The utility cannot retroactively fix existing logs, so audits focus on new entries going forward.
- **SPIKE-002 Risk 2**: Acknowledges that >=95% compliance relies on prompt instructions alone without code-level enforcement. Mitigation: periodic VALIDATE-based audits provide visibility into compliance trends and flag non-compliant agents early.

**Open Questions from SPIKE-002 (require team lead clarification)**:
1. **Audit Frequency**: What is the recommended audit frequency during the initial two-week enforcement period? Weekly seems reasonable, but daily or per-task-audit may be more effective for catching issues early.
2. **Remediation Process**: Should non-compliant entries trigger an automatic notification to the task owner, or should compliance reports be reviewed manually by the team lead during sprint reviews?

# Implementation Tasks

## Phase 1: Audit Execution Framework

1. Create `toolbox/compliance_audit.py` (or equivalent audit workflow):
   - Scan all files in `logs/specialist_logs/`.
   - For each file, invoke `specialist_log.py VALIDATE <filepath>` via subprocess or direct function import.
   - Capture stdout/stderr from VALIDATE for non-compliant entries.

2. Implement report generation:
   - Aggregate results into a structured markdown report.
   - Include compliance rate percentage per role and overall.
   - List specific non-compliant entries with file path, line number, and issue description.

3. Define audit scheduling mechanism:
   - For initial implementation: manual execution via `uv run toolbox/compliance_audit.py`.
   - Document recommended frequency (weekly minimum during enforcement period).

## Phase 2: Reporting and Integration

4. Implement report output to `internal-docs/05_reports/compliance_audit_<YYYYMMDD_HHMMSS>.md`:
   - Create the reports directory if it does not exist.
   - Use consistent naming convention for historical tracking.

5. Integrate with board task management:
   - After each audit, log results to relevant TASK entries via `board_utils.py log_event()`.
   - Include compliance rate summary in the log message (e.g., "Compliance audit complete: 92% of specialist logs compliant across all roles").

6. Add JSON output option for future automation:
   - Support `--format json` flag to produce machine-readable output suitable for CI/CD integration or monitoring dashboards.

## Phase 3: Remediation Workflow Documentation

7. Document the remediation process in the audit report template:
   - For each non-compliant entry, provide specific guidance on how to fix it.
   - Reference relevant snippets from FEAT-004 (e.g., "Use `specialist-log-formatting.md` for correct entry format").

8. Establish a feedback loop:
   - Track compliance rate trends over time across multiple audit runs.
   - Report improvement or regression in subsequent audits to measure enforcement effectiveness.

# Risks / Constraints

- **Historical Data Limitations**: Existing non-compliant log files cannot be fixed retroactively by the utility. The first few audit runs will show low compliance rates due to legacy data, which may skew initial metrics. Mitigation: Clearly distinguish between historical (legacy) and current entries in reports; focus remediation efforts on new entries going forward.
- **Agent Behavior Dependency**: Compliance ultimately depends on agents following prompt instructions when writing logs. Without code-level enforcement, the >=95% target relies entirely on agent adherence to `specialist_log.py LOG` command usage. Mitigation: The VALIDATE-based audit provides visibility; non-compliance can be flagged during task transitions via board_utils.py log_event().
- **Constraint**: Audit tooling must not modify any existing specialist log files — audits are read-only operations that only produce reports.

# Success Criteria

- Compliance audit script exists and produces structured markdown reports with per-role compliance rates, non-compliant entry details (file, line number, issue), and overall pass/fail percentages.
- Audit results are logged to relevant TASK entries via `board_utils.py log_event()` for traceability.
- Reports include actionable remediation guidance referencing FEAT-004 snippets for each type of non-compliance found.
- Compliance rate trend tracking is operational — reports from consecutive audit runs can be compared to measure improvement toward the >=95% target.

# Revision Notes

Initial feature spec created based on SPIKE-002 Finding 1 (current compliance baseline near 0%) and Risk 2 (no code-level enforcement). Audit leverages VALIDATE command from FEAT-005 as primary tooling. Reports stored in `internal-docs/05_reports/` for historical tracking.
