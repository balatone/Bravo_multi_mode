---
id: REQ-005
title: Semantic Metadata Extraction for Documentation (doc_utils.py SHOW)
version: 1.0.0
status: APPROVED
created: 2026-07-16 13:40:00
updated: 2026-07-16 13:37:34
related_docs: []
---
# Summary

Implement a `SHOW` command for the `doc_utils.py` utility that extracts and displays only the YAML preamble (metadata) of documentation files.

# Business Context / Rationale

Currently, agents must use the standard `cat` command to inspect documentation, which returns the entire file content. For large or complex documents, this increases token usage and cognitive load. A dedicated `SHOW` command allows for rapid inspection of a document's status, ID, verdict, and related links without processing the full body text.

# Scope

## In Scope

- Addition of the `SHOW <filepath>` subcommand to `doc_utils.py`.
- Implementation of a YAML parser specifically targeting the preamble block (delimited by `---`).
- Outputting formatted metadata fields: ID, Title, Status, Verdict, and Related Docs.

## Out of Scope

- AI-driven summarization of the document body.
- Full-text search capabilities.
- Modification of the documentation files themselves.

# Functional Requirements

1. The `SHOW` command must accept a single valid file path as an argument.
2. The utility must correctly identify and parse the YAML block at the beginning of the file.
3. If no YAML preamble is found, the tool should return a clear error message: "Error: No YAML preamble detected."
4. Output must be presented in a clean, human-readable format (e.g., key-value pairs).
5. The command must handle missing optional fields (like `verdict` or `related_docs`) gracefully without crashing.

# Success Criteria / Acceptance Criteria

- A user can run `python3 doc_utils.py SHOW <path>` and see only the metadata.
- The tool correctly handles files with different numbers of YAML fields.
- The tool does not attempt to read/output any content following the second `---` delimiter.

# Constraints / Guardrails / Dependencies

- **Dependency**: Relies on existing documentation standards (YAML preamble) being followed across all `internal-docs/`.
- **Constraint**: Must remain a lightweight utility; no heavy external dependencies should be added for parsing.

# Timing / Deadline / Trigger

- Trigger: Identified as a friction point during TASK-0006 execution.

# Notes / Assumptions

- Assumption: All project documentation follows the template defined in `internal-docs/07_templates/`.

# SMART Check

- **Specific:** Yes, defines a specific subcommand and behavior.
- **Measurable:** Yes, can be verified by checking output against file content.
- **Achievable:** Yes, simple YAML parsing task.
- **Relevant:** Yes, improves agent efficiency and reduces token waste.
- **Time-bound:** N/A (Triggered by current friction).
