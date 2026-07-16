# Document Management Snippet

Standardized instructions for creating and updating formal project documentation via `toolbox/doc_utils.py`.

## Creating Documents

To create a new document, use the `CREATE` command:

```bash
uv run toolbox/doc_utils.py CREATE [TYPE] "[Title]"
```

- **`[TYPE]`**: The document type prefix (e.g., `REQ`, `RAD`, `SPIKE`, `DSGN`, `FEAT`, `REVIEW`, `PLAN`). Must match a template in `internal-docs/07_templates/`.
- **`[Title]`**: A descriptive title for the document. The tool will generate a slugified filename automatically.
- **Template Rendering**: The tool loads the matching template from `internal-docs/07_templates/[TYPE].md`, extracts metadata fields, and renders the document body with the template structure intact.
- **YAML Preamble**: The created file includes a YAML preamble with `id`, `title`, `version`, `status`, `created`, and `updated` fields populated automatically.

## Updating Documents

To update document metadata (status, verdict, priority, related docs), use the `UPDATE` command:

```bash
uv run toolbox/doc_utils.py UPDATE <filepath> <status> [verdict] [priority] '[["ID-001", "ID-002"]]'
```

- **`<filepath>`**: Path to the document file.
- **`<status>`**: New lifecycle status. Valid values: `DRAFT`, `IN_REVIEW`, `APPROVED`, `SUPERSEDED`, `DEPRECATED`, `ARCHIVED`.
- **`[verdict]`**: (Optional) Review verdict for `REVIEW` documents. Valid values: `APPROVED`, `REQUEST_CHANGES`, `REJECTED`.
- **`[priority]`**: (Optional) Priority level. Valid values: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `TRIVIAL`. Only allowed for types: `BUG`, `REQ`, `BUGFIX`, `FEAT`.
- **`related_docs`**: (Optional) A JSON-formatted list of strict document IDs (e.g., `'["REQ-001", "FEAT-002"]'`). Never use filenames or partial identifiers.

### YAML Preamble Protection

You are **STRICTLY FORBIDDEN** from using `edit` or `write` to modify any field within the YAML preamble block. All metadata updates must be performed via `toolbox/doc_utils.py`.

## Document Body Editing

You **MAY** use `edit` or `write` to manage the content in the body of the document (the section following the `---` closing delimiter). However:

- **Respect Template Structure**: When creating a new document via `doc_utils.py`, the file is initialized with a specific template structure. You **MUST NOT** overwrite the entire body in a way that destroys this intended structure (e.g., removing section headers). Instead, use `edit` to populate, expand, or refine existing sections.
- **Maintain Integrity**: Ensure your edits do not accidentally corrupt the YAML preamble.

## Validation

After any documentation operation, you **MUST** verify compliance using:

```bash
python3 toolbox/validate_docs.py
```

Information about the different templates can be found at `internal-docs/07_templates/README.md`.
