---
id: DOC-001
title: Internal Documentation Templates README
version: 1.2.0
status: DRAFT
created: 2026-06-07 16:15:00
updated: 2026-07-01 12:58:00
related_docs: []
---

# Internal Documentation Templates

This directory contains the standard templates used by all specialists to keep internal documentation consistent across the project.

Use these templates when creating or updating documents via `toolbox/doc_utils.py`.

## How to use the templates

1. Choose the template that matches the document type.
2. Keep the main document focused on the core purpose of that type.
3. Use a companion `.notes.md` file when the detailed evidence would make the main document too long.
4. Prefer concise, decision-oriented writing over exhaustive narrative in the primary document.
5. Use `related_docs` for document-to-document links.
6. Use body sections such as `Supporting Materials` or `Supporting Materials / Evidence` for code paths, diagrams, datasets, tickets, and other non-document artefacts.
7. For designs with multiple visual artefacts, place them in a companion folder named after the main DSGN file.

## Template overview

| Template | Purpose | Guidance |
| --- | --- | --- |
| `REQ` | Requirement statement | Should be SMART-aligned: Specific, Measurable, Achievable, Relevant, Time-bound. |
| `RAD` | Requirement analysis | Main document should be summary-level only; detailed evidence belongs in a companion `.notes.md` file. Target 120–160 lines; hard cap 200 lines. |
| `SPIKE` | Research / investigation spike | Main document should capture the question, methodology, findings, and recommendation; detailed evidence belongs in a companion `.notes.md` file. Target 120–160 lines; hard cap 200 lines. |
| `DSGN` | Design document | Capture the proposed solution, structure, constraints, implementation details, and references to visual artefacts. Companion folder recommended when many artefacts belong to one design. |
| `DEC` | Decision record | Record a decision, the rationale behind it, and the implications. |
| `FEAT` | Feature plan | Detail the work required to complete a feature: review inputs, translate acceptance criteria into tests, implement the code, and verify the result. |
| `PLAN` | Release plan | Time-boxed release-level plan (typically 1–2 weeks) that sequences one or more features, captures dependencies, and can be updated as new features are added. |
| `REVIEW` | Review report | Summarize review findings, required changes, and verification results. Store the formal verdict in the YAML preamble (`verdict`) and keep the body focused on evidence and analysis. Keep the main review concise; move extended evidence into a companion `.notes.md` file when needed. Target 150–220 lines; hard cap 250 lines. |
| `BUG` | Bug report | Describe the defect, evidence, impact, and suggested fix direction. Severity is stored in the YAML preamble. |
| `BUGFIX` | Bugfix implementation plan or solution | Describe the intended fix, scope, tasks, acceptance criteria, and verification approach. Link the bug via `related_docs`. |
| `RETRO` | Retrospective | Capture lessons learned, root causes, improvements, and follow-up actions. |

## Companion notes policy

For `RAD` and `SPIKE`, any material that is mostly raw evidence or detailed analysis should move to a separate file with the same base name and a `.notes.md` suffix.

Examples:

- `RAD-001-demo-environment-definition.notes.md`
- `SPIKE-001-investigation-of-req-005-historical-test-data-ingestion.notes.md`

The main document should remain readable on its own and should not depend on the companion notes to understand the conclusion.
