# Document Management Snippet

Standardized instructions for creating and updating formal project documentation via `toolbox/doc_utils.py`.

## Creating Documents — Use the Tool, Never Write Manually

To create a new document, **ALWAYS** run:

```bash
uv run toolbox/doc_utils.py CREATE [TYPE] "[Title]"
```

- **`[TYPE]`**: The document type prefix in **UPPERCASE** (e.g., `REQ`, `BUG`, `RAD`, `SPIKE`, `DSGN`, `FEAT`, `REVIEW`, `PLAN`, `DEC`, `RETRO`). Must match a template in `internal-docs/07_templates/`.
- **`[Title]`**: A descriptive title for the document. The tool will generate an auto-incremented ID, slugify the filename, and place it in the correct directory automatically.

### What the Tool Handles Automatically

| Concern | Handled By `CREATE` Command |
|---|---|
| Filename (`[PREFIX]-[NNN]-[slug].md`) | ✅ Auto-generated |
| Sequential ID (one greater than existing) | ✅ Auto-incremented |
| Target directory (based on document type) | ✅ Placed correctly |
| YAML preamble with `id`, `title`, `version`, `status`, timestamps, `related_docs` | ✅ Populated automatically |
| Template body structure (section headers from template) | ✅ Loaded and preserved |

**You MUST NOT manually construct filenames, generate IDs, or write YAML preambles.** Use the CREATE command for every new document. The tool handles all of this correctly.

### After Creating a Document

The output of `CREATE` prints the full file path (e.g., `Created REQ document: internal-docs/01_requirements/REQ-003-new-feature.md`). Capture that path — you will need it for subsequent UPDATE commands and validation.

## Updating Documents

To update document metadata (status, verdict, priority, related docs), use the UPDATE command with **positional arguments**:

```bash
uv run toolbox/doc_utils.py UPDATE <filepath> <status> [verdict] [priority] '[["ID-001", "ID-002"]]'
```

- **`<filepath>`**: Full path to the document file (e.g., `internal-docs/05_review/REVIEW-001-initial-review.md`). Use the path printed by CREATE.
- **`<status>`**: New lifecycle status. Valid values: `DRAFT`, `IN_REVIEW`, `APPROVED`, `SUPERSEDED`, `DEPRECATED`, `ARCHIVED`.
- **`[verdict]`** (Optional): Review verdict for `REVIEW` documents. Valid values: `APPROVED`, `REQUEST_CHANGES`, `REJECTED`. Pass empty string `""` if not applicable.
- **`[priority]`** (Optional): Priority level. Valid values: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `TRIVIAL`. Only allowed for types: `BUG`, `REQ`, `BUGFIX`, `FEAT`. Pass empty string `""` if not applicable.
- **`related_docs`** (Optional): A JSON-formatted list of strict document IDs (e.g., `'["REQ-001", "FEAT-002"]'`). Never use filenames or partial identifiers.

### Examples

```bash
# Set status to IN_REVIEW (no verdict, no priority)
uv run toolbox/doc_utils.py UPDATE internal-docs/05_review/REVIEW-001-initial-review.md IN_REVIEW "" "" '["FEAT-001"]'

# Set verdict for a REVIEW document
uv run toolbox/doc_utils.py UPDATE internal-docs/05_review/REVIEW-002-code-audit.md APPROVED "APPROVED" "" '["FEAT-003", "BUGFIX-001"]'

# Set priority on a BUGFIX document
uv run toolbox/doc_utils.py UPDATE internal-docs/04_planning/04b_features/BUGFIX-001-fix-auth.md DRAFT "" "HIGH" '["FEAT-002"]'
```

### YAML Preamble Protection

You are **STRICTLY FORBIDDEN** from using `edit` or `write` to modify any field within the YAML preamble block. All metadata updates must be performed via `uv run toolbox/doc_utils.py UPDATE`.

## Document Body Editing

You **MAY** use `edit` or `write` to manage the content in the body of the document (the section following the `---` closing delimiter). However:

- **Respect Template Structure**: When creating a new document via `doc_utils.py CREATE`, the file is initialized with a specific template structure. You **MUST NOT** overwrite the entire body in a way that destroys this intended structure (e.g., removing section headers). Instead, use `edit` to populate, expand, or refine existing sections.
- **Maintain Integrity**: Ensure your edits do not accidentally corrupt the YAML preamble.

## Viewing Document Metadata

To inspect a document's YAML preamble:

```bash
python3 toolbox/doc_utils.py SHOW <filepath>
```

This prints all metadata key-value pairs in a readable format. Use this to verify status, verdicts, and related docs before proceeding with gates or transitions.

## Validation

After any documentation operation, you **MUST** verify compliance using:

```bash
uv run toolbox/validate_docs.py
```

Information about the different templates can be found at `internal-docs/07_templates/README.md`.
