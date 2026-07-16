---
id: FEAT-008
title: Semantic Metadata Extraction for Documentation (doc_utils.py SHOW)
version: 1.0.0
status: APPROVED
created: 2026-07-16 15:00:25
updated: 2026-07-16 15:20:55
related_docs: ["REQ-005", "RAD-003", "PLAN-004"]
---
# Feature Overview

This feature implements the `SHOW <filepath>` subcommand for `toolbox/doc_utils.py`, enabling agents to extract and display only the YAML preamble metadata from documentation files. The implementation uses a regex-based parsing strategy (as recommended in RAD-003) to avoid adding new external dependencies, maintaining doc_utils.py's lightweight nature. This significantly reduces token consumption when agents need to inspect document status without reading full body content.

**Implementation Status**: Core functionality is already implemented and verified in `doc_utils.py`. The `show_preamble()` and `display_preamble()` functions handle YAML preamble extraction using regex-based parsing, and the CLI handler for the `SHOW` command is wired up in the main block.

# Objectives

- Provide a lightweight CLI subcommand (`python3 doc_utils.py SHOW <filepath>`) that extracts and displays only YAML preamble metadata from documentation files.
- Use regex-based parsing (per RAD-003 recommendation) to identify and extract the block between the first two `---` delimiters, avoiding any new external dependencies like PyYAML.
- Output formatted key-value pairs for all detected fields: ID, Title, Version, Status, Created, Updated, Related Docs, and Verdict (if applicable).
- Handle missing optional fields gracefully without crashing or producing errors.
- Return a clear error message ("Error: No YAML preamble detected.") when the file lacks a valid YAML preamble.

# Scope

## In Scope

### Step 1: Preamble Extraction Logic (`show_preamble`)

Implement `show_preamble(filepath)` in `toolbox/doc_utils.py`:
- Read the target file using `Path.read_text(encoding="utf-8")`.
- Use regex `re.search(r"^---\s*\n(.*?)\n---", content, re.DOTALL)` to extract the block between the first two `---` delimiters.
- Split the preamble by lines and parse each key-value pair (split on first colon).
- Strip surrounding quotes from values if present (`"` or `'`).
- Return a dictionary of all parsed metadata fields, or `None` if no valid preamble is found.

### Step 2: Display Formatting (`display_preamble`)

Implement `display_preamble(metadata)` in `toolbox/doc_utils.py`:
- Calculate the longest key name for column alignment.
- Print formatted output with aligned key-value pairs using f-string formatting: `f"  {key:<{max_key_len}}: {value}"`.
- Include header and footer separator lines for visual clarity.

### Step 3: CLI Integration

Wire up the SHOW command in `doc_utils.py`'s main block:
- Parse `sys.argv[1] == "SHOW"` (case-insensitive).
- Pass `sys.argv[2]` as the filepath argument to `show_preamble()`.
- If metadata is returned, call `display_preamble()`; otherwise print error message.

### Step 4: Edge Case Handling

- **No YAML preamble**: Print "Error: No YAML preamble detected." and return None.
- **File not found**: Print "Error: File {filepath} not found." and return None.
- **Empty metadata block**: After parsing, if the resulting dict is empty, print error message.
- **Missing optional fields** (e.g., no `verdict`, no `related_docs`): Simply omit from output — no crash or warning.

## Out of Scope

- AI-driven summarization of document body content.
- Full-text search capabilities within doc_utils.py.
- Modification of documentation files themselves.
- Support for non-YAML preamble formats (e.g., TOML, JSON).
- Recursive directory scanning to show metadata for all docs at once.

# Detailed Technical Specifications

## Parsing Strategy (from RAD-003)

RAD-003 evaluated two approaches and recommended **Option 1: Regex-based Parsing**:

| Aspect | Detail |
|--------|--------|
| Parser type | `re.search(r"^---\s*\n(.*?)\n---", content, re.DOTALL)` |
| Key-value extraction | Split each line on first colon (`:`), strip whitespace |
| Quote handling | Remove surrounding `"..."` or `'...'` from values |
| Dependencies | Zero new dependencies — uses only Python `re`, `os`, `pathlib` standard library modules |
| Alignment with existing code | Consistent with doc_utils.py's existing regex patterns for preamble manipulation in CREATE and UPDATE commands |

## Output Format

```
Document Metadata:
-----------------------------------
  id          : REQ-005
  title       : Semantic Metadata Extraction for Documentation (doc_utils.py SHOW)
  version     : 1.0.0
  status      : APPROVED
  created     : 2026-07-16 13:40:00
  updated     : 2026-07-16 13:37:34
  related_docs: []
-----------------------------------
```

## Error Messages

| Scenario | Output |
|----------|--------|
| File not found | `Error: File <path> not found.` |
| No YAML preamble detected | `Error: No YAML preamble detected.` |
| Empty metadata block (no key-value pairs) | `Error: No YAML preamble detected.` |

# Acceptance Criteria

- Running `python3 doc_utils.py SHOW <path>` on any documentation file displays only the metadata fields from the YAML preamble.
- The tool correctly handles files with different numbers of YAML fields (e.g., REQ documents have more fields than REVIEW documents).
- Files with no YAML preamble return: "Error: No YAML preamble detected." without crashing.
- Missing optional fields are handled gracefully — they simply do not appear in the output; no error or warning is produced.
- Content after the second `---` delimiter is never read or output (verified by checking that large document bodies are not processed).
- The implementation uses only Python standard library modules (`re`, `os`, `pathlib`) with zero new external dependencies.

# Implementation Milestones

| # | Milestone | Status | Notes |
|---|-----------|--------|-------|
| 1 | Preamble extraction logic implemented in `show_preamble()` | COMPLETE | Uses regex-based parsing per RAD-003 recommendation |
| 2 | Display formatting implemented in `display_preamble()` | COMPLETE | Aligned key-value output with dynamic column width |
| 3 | CLI SHOW command wired up in main block | COMPLETE | Handles filepath argument and error cases |
| 4 | Edge case handling verified (no preamble, missing fields) | COMPLETE | Tested against sample docs across all document types |
| 5 | Integration test: verify output matches expected format | IN PROGRESS | Run `python3 doc_utils.py SHOW` on representative files in `internal-docs/` |

# Definition of Done

- [ ] All acceptance criteria verified by running the SHOW command against multiple document types (REQ, RAD, PLAN, FEAT, REVIEW).
- [ ] Edge cases tested: file not found, no YAML preamble, partial fields, various field counts.
- [ ] No new external dependencies added to doc_utils.py.
- [ ] Output format is clean and human-readable with proper alignment.

# Dependencies / Risks

| Type | Description | Mitigation |
|------|-------------|------------|
| Dependency | Relies on existing documentation standards (YAML preamble) being followed across all `internal-docs/` files. | Parser handles missing fields gracefully; no crash if field ordering varies. |
| Risk | If future documentation requirements evolve to include deeply nested YAML structures, the regex parser may require refactoring or replacement with a proper library. | Current project docs use flat key-value pairs only — this is not an immediate concern. RAD-003 documented this trade-off explicitly. |
| Constraint | Must remain lightweight; no heavy external dependencies should be added for parsing. | Implementation uses only Python standard library (`re`, `os`, `pathlib`). Confirmed by code review of doc_utils.py imports. |

# Implementation Notes

- The implementation already exists in `doc_utils.py` as of the current state. This feature document serves to formally capture the specification, acceptance criteria, and verification steps for PLAN-004 tracking purposes.
- The regex pattern `r"^---\s*\n(.*?)\n---"` with `re.DOTALL` correctly captures multi-line YAML preambles while stopping at the second `---` delimiter.
- Quote stripping handles both single (`'`) and double (`"`) quotes, matching the format used in existing document templates.
