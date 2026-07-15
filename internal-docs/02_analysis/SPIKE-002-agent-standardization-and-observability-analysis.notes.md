---
id: SPIKE-002-notes
title: Agent Standardization & Observability Framework Analysis — Companion Notes
version: 1.0.0
status: DRAFT
created: 2026-07-15 14:13:00
updated: 2026-07-15 14:13:00
related_docs: ["SPIKE-002", "REQ-003"]
---

# Companion Notes / Raw Evidence

This file contains raw evidence, detailed comparisons, and supplementary data supporting SPIKE-002. The main document (`SPIKE-002-agent-standardization-and-observability-analysis.md`) provides the summary, decisions, and recommendations.

## A. Full Specialist Log File Inventory

### `backend-engineer_20260714_180000.log` (5 entries)
```
[2026-07-14 18:00:00] - FEAT-001 Phase 4 - IN_PROGRESS - Creating tests/decoder_spec.lua with Busted tests
[2026-07-14 18:02:00] - FEAT-001 Phase 4 - IN_PROGRESS - Tests run but fail due to debounce timing; adding os.clock() mock
[2026-07-14 18:03:00] - FEAT-001 Phase 4 - COMPLETE - All 15 tests pass with busted --helper tests/init.lua tests/
[2026-07-14 18:03:30] - FEAT-001 Phase 5 - IN_PROGRESS - Creating .luacov.cfg and generating coverage report
[2026-07-14 18:04:30] - FEAT-001 Phase 5 - COMPLETE - luacov_report.html generated; decoder.lua at 91.33% coverage
```

**Format Issues:** Subtask not bracketed, status not wrapped in `[STATUS: ...]`, no DETAILS field delimiter (all info is part of subtask).

### `backend-engineer_20260715_115700.log` (3 entries)
```
[2026-07-15 11:57:10] - [BUGFIX-001] - [STATUS: IN_PROGRESS] - [Starting diagnostic phase: investigating luacov coverage issue]
[2026-07-15 12:18:02] - [BUGFIX-001] - [STATUS: COMPLETE] - [Committed fix: added require('luacov') to tests/_bootstrap.lua, created .luacov config. All 45 tests pass, luacov.stats.out generated, luacov_utils.py parses output correctly.]
[2026-07-15 12:39:34] - [BUGFIX-001 follow-up] - [Committed fix: replaced hardcoded absolute paths in _bootstrap.lua with relative resolution via debug.getinfo(1).source. All 45 tests pass, luacov output verified.]
```

**Format Issues:** Third entry missing `[STATUS: ...]` field entirely — no status label at all. Inconsistent bracket usage across entries.

### `backend-engineer_20260715_115707.log` (1 entry)
```
[2026-07-15 11:57:07] - [BUGFIX-001] - [STATUS: IN_PROGRESS] - [Starting diagnostic phase]
```

**Format Issues:** Only one entry; appears to be a duplicate/early version of the first entry in `backend-engineer_20260715_115700.log`.

### `technical-analyst_2026-07-14.log` (5 entries)
```
[2026-07-14 17:30:00] - [FEAT-001 creation] - [STATUS: IN_PROGRESS] - Starting feature plan document generation for Lua tech stack documentation and tooling.
[2026-07-14 17:35:00] - [FEAT-001 creation] - [STATUS: COMPLETE] - FEAT-001-implement-lua-tech-stack-documentation-and-tooling.md created (435 lines) with 5 implementation phases, 8 acceptance criteria, and full dependency/risk analysis.
[2026-07-14 17:36:00] - [TASK-001 activity logging] - [STATUS: COMPLETE] - Appended session activities to TASK-001 activity log.
[2026-07-14 17:45:xx] - [FEAT-001 Phase 6 addition] - [STATUS: IN_PROGRESS] - User requested Python pre-commit hook configuration task.
[2026-07-14 17:48:xx] - [FEAT-001 Phase 6 addition] - [STATUS: COMPLETE] - Added Phase 6 with .pre-commit-config.yaml spec (ruff, StyLua, pre-commit-hooks, validate_docs local hook), AC-9 through AC-11. FEAT-001 now has 6 phases and 11 acceptance criteria (524 lines).
```

**Format Issues:** Timestamps `17:45:xx` and `17:48:xx` have incomplete seconds — placeholder values instead of real timestamps. DETAILS field not wrapped in brackets on these entries. File naming uses dashes (`technical-analyst_2026-07-14.log`) vs underscore-based convention used by other files.

### `technical-analyst_20260715_140130.log` (1 entry)
```
[2026-07-15 14:01:30] - [TASK-003 analysis] - [STATUS: IN_PROGRESS] - Starting investigation of REQ-003 requirements and codebase.
```

**Format Issues:** Only one entry; otherwise compliant with the target format (brackets around subtask, `[STATUS: ...]`, DETAILS in brackets). This is the most compliant existing file but still has minor formatting inconsistencies compared to the strict REQ-003 FR#2 specification.

### `test-engineer_20260714_202904.log` (8 entries)
```
[2026-07-14 20:29:04] - [FEAT-001 Phase 3] - [STATUS: IN_PROGRESS] - Running Busted tests on decoder_spec.lua with proper mocking setup.
[2026-07-14 20:30:15] - [FEAT-001 Phase 3] - [STATUS: COMPLETE] - All 15 tests pass; coverage report generated at luacov_report.html (91.33% on decoder.lua).
[2026-07-14 20:31:00] - [FEAT-001 Phase 4] - [STATUS: IN_PROGRESS] - Creating .luacov.cfg configuration file for coverage measurement.
[2026-07-14 20:32:00] - [FEAT-001 Phase 4] - [STATUS: COMPLETE] - luacov.cfg created with standard settings; coverage data collected and report generated.
[2026-07-14 20:33:00] - [FEAT-001 Phase 5] - [STATUS: IN_PROGRESS] - Running Stylua formatter on all Lua source files in bravo++/ directory.
[2026-07-14 20:34:00] - [FEAT-001 Phase 5] - [STATUS: COMPLETE] - All 16 Lua files formatted with StyLua; no formatting violations remaining.
[2026-07-14 20:35:00] - [FEAT-001 Phase 6] - [STATUS: IN_PROGRESS] - Creating .pre-commit-config.yaml for ruff, Stylua, and validate_docs hooks.
[2026-07-14 20:36:00] - [FEAT-001 Phase 6] - [STATUS: COMPLETE] - Pre-commit config created with three hooks; validation passes on all Lua files.
```

**Format Issues:** This is actually the most compliant file — uses brackets around subtask, `[STATUS: ...]` format, and DETAILS in brackets consistently. However, timestamps use `HHMMSS` suffix in filename but standard format in entries. No major issues except that this log was created by a different agent role (test-engineer) with slightly different formatting conventions than others.

## B. Worker Prompt Directive Locations — Full Content Excerpts

### `prompts/worker/backend-engineer.md`
```markdown
If you are explicitly instructed to create or update a formal document, use `uv run toolbox/doc_utils.py ...` and then run `python3 toolbox/validate_docs.py` before reporting completion.
```

### `prompts/worker/generic-worker.md` (lines 17–40)
```markdown
## Documentation & Error Handling
- **Documentation Tooling**: If you are explicitly instructed to create or update a formal document, use `uv run toolbox/doc_utils.py ...` and then run `python3 toolbox/validate_docs.py` before reporting completion.

## Resilience & Telemetry
- **Error Reporting**: If you encounter an environmental error (e.g., Network Timeout, Access Denied) that prevents research, do not simply fail. You MUST:
  1. Attempt one retry with a diagnostic command (e.g., `curl`, `env`).
  2. If failure persists, write a detailed error report to `logs/specialist_logs/<role>_<timestamp>.log`. Format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: FAILED] - [ERROR MESSAGE]`
- **Logging**: Maintain real-time visibility by appending status updates to `logs/specialist_logs/<role>_<timestamp>.log`. Format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: IN_PROGRESS|COMPLETE]`

## Status Board Synchronization (Mandatory)
Before beginning research or analysis, you **MUST** verify that the corresponding `TASK` in `.board/` is set to `status: ANALYSING`. If it is not, notify the Lead immediately and do not proceed.

To log activities on the current task via the board, use:
`uv run toolbox/board_utils.py log <TASK-ID> --actor "<your-role>" --message "<msg>"`
```

### `prompts/worker/qwen_worker_specialist.md`
```markdown
If you are explicitly instructed to create or update a formal document, use `uv run toolbox/doc_utils.py ...` and then run `python3 toolbox/validate_docs.py` before reporting completion.
```

### `prompts/reviewer.md` (lines 45–72)
```markdown
## Resilience & Telemetry
- **Error Reporting**: If you encounter an environmental error that prevents review, do not simply fail. You MUST:
  1. Attempt one retry with a diagnostic command.
  2. If failure persists, write a detailed error report to `logs/specialist_logs/<role>_<timestamp>.log`. Format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: FAILED] - [ERROR MESSAGE]`
- **Logging**: Maintain real-time visibility by appending status updates to `logs/specialist_logs/<role>_<timestamp>.log`. Format: `[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: IN_PROGRESS|COMPLETE]`

## Document Management Protocol (Mandatory)
You are responsible for maintaining high-fidelity documentation. You must distinguish between the **YAML Preamble** (metadata) and the **Document Body** (content).

### 1. YAML Preamble (Metadata) — TOOL ONLY
You are **STRICTLY FORBIDDEN** from using `edit` or `write` to modify any field within the YAML preamble block. All metadata updates must be performed via `toolbox/doc_utils.py`.

- **To Create**: `uv run toolbox/doc_utils.py CREATE [TYPE] "[Title]"`
- **To Update Status & Verdict**: `uv run toolbox/doc_utils.py UPDATE <filepath> <status> [verdict]`

### 2. Document Body (Content) — EDIT/WRITE ALLOWED (WITH STRUCTURE RESPECT)
You **MAY** use `edit` or `write` to manage the content in the body of the document (the section following the `---` closing delimiter). However, you must adhere to these rules:

- **Respect Template Structure**: When creating a new review report via `doc_utils.py`, the file is initialized with a specific template structure. You **MUST NOT** overwrite the entire body in a way that destroys this intended structure. Instead, use `edit` to populate, expand, or refine these existing sections.
```

## C. File Naming Convention Analysis

Current files and their naming patterns:

| Filename | Role | Date Format | Separator | Compliant? |
|----------|------|-------------|-----------|------------|
| `backend-engineer_20260714_180000.log` | backend-engineer | YYYYMMDD_HHMMSS | underscore | Yes (matches recommended) |
| `backend-engineer_20260715_115700.log` | backend-engineer | YYYYMMDD_HHMMSS | underscore | Yes |
| `backend-engineer_2026-07-14.log` | backend-engineer | YYYY-MM-DD only | mixed (dash after role) | No — inconsistent with others |
| `backend-engineer_20260715_115707.log` | backend-engineer | YYYYMMDD_HHMMSS | underscore | Yes |
| `technical-analyst_2026-07-14.log` | technical-analyst | YYYY-MM-DD only | mixed (dash after role) | No — inconsistent |
| `technical-analyst_20260715_140130.log` | technical-analyst | YYYYMMDD_HHMMSS | underscore | Yes |
| `test-engineer_20260714_202904.log` | test-engineer | YYYYMMDD_HHMMSS | underscore | Yes |

**Conclusion:** 5 of 8 files use the recommended `<role>_<YYYYMMDD_HHMMSS>.log` format. The 3 non-compliant files all use a simplified date-only suffix with dashes in the role name portion (which is fine since roles contain hyphens). Going forward, `specialist_log.py` should enforce the full timestamp-in-filename pattern for consistency.

## D. Prompt Snippet Library — Reference Pattern Examples

### Example: How an archetype prompt would reference a snippet
```markdown
## Document Management
For document creation and updates, follow the standardized patterns in `prompts/snippets/doc-management.md`. This covers both CREATE (initialization) and UPDATE (metadata/status changes) operations via `toolbox/doc_utils.py`.

**Key rules:**
- Never modify YAML preambles directly with edit/write.
- Always run `python3 toolbox/validate_docs.py` after document operations.
```

### Example: How a worker prompt would reference a snippet
```markdown
## Logging Activities
When logging specialist log entries, follow the format in `prompts/snippets/specialist-log-formatting.md`. Use the standardized entry structure with ISO 8601 timestamps and required status labels.
```
