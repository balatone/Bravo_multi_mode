---
id: RAD-004-notes
title: "Companion Notes for RAD-004 Technical Investigation"
version: 1.0.0
status: APPROVED
created: "2026-07-16 13:50:00"
updated: 2026-07-16 14:22:47
related_docs: ["RAD-004"]
---
# Raw Evidence and Supporting Data for RAD-004

## Board Directory Structure (as of analysis)

```
.board/
├── status_board_protocol.md    (non-task file, skipped by LIST)
├── done/
│   ├── TASK-0001-populate-tech-stack-documentation.md
│   ├── TASK-0002-orchestration-resilience-enhancements.md
│   ├── TASK-0003-agent-standardization-observability-framework.md
│   ├── TASK-0004-fix-log-overwrite-and-missing-git-persistence-in-auto-approve-delegation.md
│   ├── TASK-0005-implement-bugfix-003-specialist-log-compliance-audit-refactor.md
│   └── TASK-0006-consolidate-specialist-log-tooling-into-single-module.md
├── in-progress/                 (empty)
└── to-do/                       (empty)
```

Total task files: 7 (all in `done/`)

## Sample Task File Structure (TASK-0001)

```yaml
---
id: TASK-0001
title: "Populate Tech Stack Documentation"
version: 1.0.0
status: DONE
created: "2026-07-14 16:33:59"
updated: "2026-07-15 13:55:33"
primary_doc: REQ-001
related_docs: ["REQ-001"]
---

# Activity Log
[2026-07-14 17:35:58] - [team-lead] - Technical analysis completed; feature planning in progress.
...
```

## FOLDERS Mapping (from board_utils.py)

| Status Key      | Directory Path              |
|-----------------|----------------------------|
| TO-DO           | `.board/to-do/`            |
| ANALYSING       | `.board/in-progress/`      |
| DESIGNING       | `.board/in-progress/`      |
| PLANNING        | `.board/in-progress/`      |
| IMPLEMENTING    | `.board/in-progress/`      |
| TESTING         | `.board/in-progress/`      |
| REVIEWING       | `.board/in-progress/`      |
| DONE            | `.board/done/`             |

## Status Sort Order (for LIST output)

```python
STATUS_ORDER = {
    "TO-DO": 0,
    "ANALYSING": 1,
    "DESIGNING": 2,
    "PLANNING": 3,
    "IMPLEMENTING": 4,
    "TESTING": 5,
    "REVIEWING": 6,
    "DONE": 7,
}
```

## Expected LIST Output (for current board state)

```
+----------+---------------------------------------------------------------+-------------+
| TASK ID  | TITLE                                                         | STATUS      |
+----------+---------------------------------------------------------------+-------------+
| TASK-0001| Populate Tech Stack Documentation                             | DONE        |
| TASK-0002| Orchestration Resilience Enhancements                         | DONE        |
| TASK-0003| Agent Standardization and Observability Framework             | DONE        |
| TASK-0004| Fix Log Overwrite and Missing Git Persistence in Auto Approve | DONE        |
| TASK-0005| Implement Bugfix 003 Specialist Log Compliance Audit Refactor | DONE        |
| TASK-0006| Consolidate Specialist Log Tooling into Single Module         | DONE        |
+----------+---------------------------------------------------------------+-------------+
```

## Code Paths Referenced in Analysis

1. **`get_task_path(task_id)`** — Uses `BOARD_DIR.rglob("*.md")`, iterates all .md files, loads each with `load_task()`, checks metadata.id. Skips `status_board_protocol.md`. Returns single match or raises on duplicates.
2. **`load_task(path)`** — Reads file, splits on `^---$` regex, parses YAML block via `yaml.safe_load()`, returns dict with metadata/body/full_content keys.
3. **`slugify(text)`** — Converts to lowercase, replaces non-alphanumeric chars with hyphens, strips leading/trailing hyphens. Used for filename generation.

## Performance Benchmarks (estimated)

| Task Count | rglob + YAML Parse Time | Notes                          |
|------------|------------------------|--------------------------------|
| 7          | <5ms                   | Current board state            |
| 10         | ~6ms                   | Linear scaling                 |
| 100        | ~50ms                  | Still imperceptible to user    |
| 500        | ~250ms                 | Acceptable; consider caching   |
| 1000       | ~500ms                 | Caching recommended            |

## Edge Case Test Cases (for implementation)

```python
# TC-1: Empty board — no task files in any subdirectory
# Expected: "No active tasks found in .board/"

# TC-2: Malformed YAML preamble (missing closing ---)
# Expected: File skipped, warning to stderr, other files still listed

# TC-3: Task file with missing 'title' field in metadata
# Expected: Fall back to filename-based title extraction

# TC-4: Non-.md file in .board/to-do/ (e.g., notes.txt)
# Expected: Ignored by rglob("*.md") filter

# TC-5: Duplicate task IDs across directories
# Expected: RuntimeError raised with duplicate paths listed

# TC-6: Subdirectory nested deeper than one level (.board/in-progress/subdir/)
# Expected: Skipped by rel_parts length check (len != 2)

# TC-7: Unrecognized directory name in .board/ (e.g., .board/archived/)
# Expected: Listed with "UNKNOWN" status label
```

## Implementation Sketch (for reference)

```python
def list_tasks() -> str:
    """List all tasks across .board/ subdirectories as an ASCII table."""

    STATUS_ORDER = {
        "TO-DO": 0, "ANALYSING": 1, "DESIGNING": 2, "PLANNING": 3,
        "IMPLEMENTING": 4, "TESTING": 5, "REVIEWING": 6, "DONE": 7,
    }

    tasks = []
    for md_file in BOARD_DIR.rglob("*.md"):
        if md_file.name == "status_board_protocol.md":
            continue

        rel_parts = md_file.relative_to(BOARD_DIR).parts
        if len(rel_parts) != 2:
            continue

        status_dir = rel_parts[0].upper()

        try:
            task_data = load_task(md_file)
            metadata = task_data["metadata"]
            task_id = metadata.get("id", md_file.stem.split("-")[0])
            title = metadata.get("title", md_file.stem.replace("-", " ").replace("_", " "))
        except Exception:
            # Fallback to filename extraction
            match = re.match(r"(TASK-\d+)-(.+)\.md", md_file.stem)
            task_id = match.group(1) if match else md_file.stem.split("-")[0]
            title = (match.group(2).replace("-", " ").title()
                     if match else md_file.stem.replace("-", " "))

        tasks.append({
            "id": task_id,
            "title": title,
            "status": status_dir,
            "sort_key": STATUS_ORDER.get(status_dir, 99),
        })

    # Sort by status order, then by ID within same status
    tasks.sort(key=lambda t: (t["sort_key"], t["id"]))

    if not tasks:
        return "No active tasks found in .board/"

    headers = ["TASK ID", "TITLE", "STATUS"]
    rows = [[t["id"], t["title"], t["status"]] for t in tasks]
    return format_table(headers, rows)


def format_table(headers: list[str], rows: list[list[str]]) -> str:
    """Format data as a clean ASCII table."""
    col_widths = [max(len(h), 10) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            if i < len(col_widths):
                col_widths[i] = max(col_widths[i], len(cell))

    fmt = " | ".join(f"{{:<{w}}}" for w in col_widths)
    sep = "-+-".join("-" * w for w in col_widths)

    lines = [fmt.format(*headers), sep] + \
            [fmt.format(*(r[i] if i < len(r) else ""
                         for i in range(len(headers))))
             for r in rows]
    return "\n".join(lines)
```
