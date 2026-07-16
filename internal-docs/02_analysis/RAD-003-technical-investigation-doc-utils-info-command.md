---
id: RAD-003
title: Technical Investigation: doc_utils.py INFO Command Implementation
version: 1.0.0
status: APPROVED
created: 2026-07-16 13:45:00
updated: 2026-07-16 13:50:00
related_docs: ["REQ-005"]
---

# Executive Summary

This investigation evaluates the implementation of an `INFO` command for the `doc_utils.py` utility to enable semantic metadata extraction from documentation files. The preferred approach is to use regex-based parsing of the YAML preamble, which maintains the tool's lightweight nature and avoids adding new dependencies like `PyYAML`. This change will significantly improve agent efficiency by reducing token consumption during document inspection.

# Purpose / Question

To address the friction point identified in TASK-0006, where agents must consume large amounts of tokens to inspect documentation metadata via `cat`, a dedicated `INFO` command is required to extract only the YAML preamble.

# Scope

## In Scope

- Implementation of the `INFO <filepath>` subcommand for `doc_utils.py`.
- Selection of an optimal parsing strategy (Regex vs. YAML library).
- Definition of CLI interface and output format.
- Assessment of impact on token usage and workflows.
- Identification of edge cases (malformed YAML, missing fields).

## Out of Scope

- AI-driven summarization of document bodies.
- Full-text search capabilities within `doc_utils.py`.
- Modification of existing documentation files.

# Current State

Currently, agents inspect documentation using standard shell commands like `cat` or `less`. For large documents, this results in the entire file content being loaded into the context window, leading to:
1. High token usage and increased costs.
2. Increased cognitive load for the agent when searching for specific metadata (e.g., status or verdict).

# Methodology / Evidence

The analysis was performed through:
- **Requirement Review**: Detailed examination of `REQ-005`.
- **Code Analysis**: Inspection of `toolbox/doc_utils.py` to understand existing parsing logic and dependency constraints.
- **Document Inspection**: Review of various documentation types (REQ, REVIEW, etc.) in `internal-docs/` to confirm YAML preamble consistency.

# Findings

1. **Consistent Preamble Structure**: All project documentation follows a standardized YAML preamble delimited by `---`.
2. **Existing Logic**: `doc_utils.py` already utilizes regex for identifying and manipulating the preamble, suggesting that a regex-based approach is consistent with the current architecture.
3. **Simple Data Model**: The metadata fields are currently flat key-value pairs, making them well-suited for simple parsing without a full YAML engine.
4. **Dependency Constraint**: The requirement explicitly mandates keeping `doc_utils.py` lightweight and avoiding heavy external dependencies.

# Evaluation Criteria

- **Feasibility**: How easily can the command be integrated into the existing CLI?
- **Dependency Overhead**: Does the solution introduce new, heavy libraries?
- **Robustness**: How well does it handle malformed or missing data?
- **Efficiency**: Does it achieve the goal of reducing token usage?

# Options / Recommendations

## Options Considered

### Option 1: Regex-based Parsing (Recommended)
Use `re.search` to extract the block between the first two `---` delimiters, then split by lines and colons to extract key-value pairs.
- **Pros**: Zero additional dependencies; extremely fast; aligns with existing code patterns.
- **Cons**: Less robust for highly complex or nested YAML structures (though not currently present in project docs).

### Option 2: Dedicated YAML Library (e.g., PyYAML)
Integrate a standard library like `PyYAML` to parse the preamble block.
- **Pros**: Highly robust; handles all edge cases of the YAML specification.
- **Cons**: Introduces a new dependency; increases the footprint of a lightweight utility.

## Recommended Direction

**Option 1 (Regex-based Parsing)** is recommended. Given the current documentation standards and the explicit constraint to keep `doc_utils.py` lightweight, a regex approach provides the best balance of efficiency and simplicity.

# Risks / Trade-offs / Constraints

- **Risk**: If future documentation requirements evolve to include deeply nested YAML structures, the regex parser may require refactoring or replacement with a proper library.
- **Constraint**: The implementation must strictly adhere to the "no heavy dependencies" rule.
- **Trade-off**: We trade off absolute YAML specification compliance for minimal dependency overhead and maximum speed.

# Supporting Materials / Evidence

- `REQ-005`: Semantic Metadata Extraction requirement.
- `toolbox/doc_utils.py`: Current implementation of document utilities.
- Sample documentation files in `internal-docs/`.

# Next Steps

1. Implement the `INFO` subcommand in `toolbox/doc_utils.py`.
2. Verify the implementation against various document types (REQ, REVIEW, etc.).
3. Test edge cases including malformed YAML and missing fields.

# Companion Notes / Raw Evidence

No companion notes required for this investigation.
