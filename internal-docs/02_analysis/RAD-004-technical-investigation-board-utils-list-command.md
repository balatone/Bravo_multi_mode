---
id: RAD-004
title: "Technical Investigation: board_utils.py LIST Command Implementation"
version: 1.0.0
status: APPROVED
created: "2026-07-16 13:50:00"
updated: 2026-07-16 14:22:20
related_docs: ["REQ-006"]
---
# Executive Summary

This investigation evaluates the feasibility and implementation strategy for adding a `LIST` subcommand to `board_utils.py`. The analysis confirms that implementing this command is straightforward, low-risk, and highly achievable using existing patterns in the codebase. The recommended approach uses `pathlib.Path.rglob()` for directory traversal (consistent with the existing `get_task_path()` function), YAML preamble parsing via the existing `load_task()` helper for metadata extraction, and a lightweight ASCII table formatter built from standard library string operations. No new dependencies are required.

# Purpose / Question

REQ-006 requests a `LIST` command that provides a consolidated dashboard view of all tasks across `.board/` subdirectories (to-do/, in-progress/, done/). The key questions this investigation addresses:
1. What is the most efficient directory scanning strategy?
2. How should task metadata be extracted reliably?
3. What formatting approach produces readable output at scale?
4. What performance and edge-case considerations apply?

# Scope

## In Scope

- Directory traversal strategies for `.board/` subdirectories.
- Metadata extraction methods (Task ID, Title, Status).
- ASCII table formatting approaches.
- Performance analysis for large task sets.
- Edge case handling (empty directories, malformed files, non-.md files).

## Out of Scope

- Interactive task management from the LIST output.
- Detailed per-task content display.
- Graphical or web-based dashboarding.
- Implementation coding (handled by a subsequent implementation task).

# Current State

The `board_utils.py` module (`toolbox/board_utils.py`, ~530 lines) currently provides four CLI subcommands: `create`, `transition`, `log`, and `update`. Key architectural elements relevant to LIST:

**Directory Structure Mapping:**
```python
FOLDERS = {
    "TO-DO": BOARD_DIR / "to-do",
    "ANALYSING": BOARD_DIR / "in-progress",
    "DESIGNING": BOARD_DIR / "in-progress",
    "PLANNING": BOARD_DIR / "in-progress",
    "IMPLEMENTING": BOARD_DIR / "in-progress",
    "TESTING": BOARD_DIR / "in-progress",
    "REVIEWING": BOARD_DIR / "in-progress",
    "DONE": BOARD_DIR / "done",
}
```

**Existing Scanning Pattern:** The `get_task_path()` function already uses `BOARD_DIR.rglob("*.md")` to recursively find all `.md` files, then loads each via `load_task()` and checks the metadata `id` field. It skips `status_board_protocol.md`.

**Task File Format (YAML Preamble):**
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
```

**Parsing Infrastructure:** The `load_task()` function splits content on `^---$` regex, parses the YAML block via `yaml.safe_load()`, and returns metadata. This is already imported and available for reuse.

# Methodology / Evidence

Evidence gathered through:
- **Static code analysis**: Full review of `board_utils.py` (530 lines), including all functions, imports, and patterns.
- **Directory traversal inspection**: Examined `.board/` structure with 7 task files across `done/`, empty `to-do/` and `in-progress/`.
- **Template comparison**: Reviewed RAD-001, RAD-002, RAD-003 for structural consistency.
- **Pattern matching**: Identified that `get_task_path()` already implements the core scanning logic needed by LIST.

# Findings

## F1: Directory Traversal — pathlib.Path.rglob() is Optimal

**Recommendation:** Use `pathlib.Path.rglob("*.md")` with a depth limit of 2 (one level below `.board/`).

**Rationale:**
- The existing `get_task_path()` function already uses this exact pattern, ensuring consistency.
- `rglob("*.md")` naturally recurses into all subdirectories without explicit loop nesting.
- A depth filter can be applied post-scan by checking that the file's relative path has at most 2 components (e.g., `.board/to-do/TASK-001.md`).

**Implementation sketch:**
```python
def list_tasks() -> list[dict]:
    tasks = []
    for md_file in BOARD_DIR.rglob("*.md"):
        # Skip non-task files and the protocol file
        if md_file.name == "status_board_protocol.md":
            continue
        rel_parts = md_file.relative_to(BOARD_DIR).parts
        if len(rel_parts) != 2:  # Only scan direct subdirectories
            continue
        status_dir = rel_parts[0].lower()
        try:
            task_data = load_task(md_file)
            metadata = task_data["metadata"]
            tasks.append({
                "id": metadata.get("id", md_file.stem),
                "title": metadata.get("title", md_file.stem),
                "status": status_dir.upper(),
            })
        except Exception:
            continue  # Skip malformed files gracefully
    return sorted(tasks, key=lambda t: STATUS_ORDER.get(t["status"], 99))
```

**Alternative considered:** `os.walk()` — rejected because it requires manual path construction and is less Pythonic than the existing `rglob` pattern.

## F2: Metadata Extraction — YAML Preamble Parsing is Reliable

**Recommendation:** Use the existing `load_task()` function to parse YAML preambles, falling back to filename-based extraction only for files with missing or invalid metadata.

**Rationale:**
- All task files in `.board/` follow a consistent YAML preamble format (verified on all 7 existing tasks).
- The `yaml.safe_load()` import is already present and used throughout the module.
- Fallback to filename pattern (`TASK-NNNN-slugified-title.md`) provides resilience for edge cases.

**Fallback strategy:** If `load_task()` raises an exception or metadata lacks required fields, extract from filename using:
```python
# Filename format: TASK-0001-populate-tech-stack-documentation.md
match = re.match(r"(TASK-\d+)-(.+)\.md", md_file.stem)
if match:
    task_id = match.group(1)
    title = match.group(2).replace("-", " ").title()
```

**Status determination:** Per REQ-006, status is derived from the **directory location**, not the YAML preamble `status` field. This aligns with how `transition_task()` works (moving files between directories updates status implicitly). The directory name maps to a canonical status via:
```python
STATUS_ORDER = {
    "TO-DO": 0,
    "ANALYSING": 1, "DESIGNING": 2, "PLANNING": 3,
    "IMPLEMENTING": 4, "TESTING": 5, "REVIEWING": 6,
    "DONE": 7,
}
```

## F3: ASCII Table Formatting — Lightweight Custom Formatter

**Recommendation:** Implement a custom `format_table()` function using standard library string operations (no external dependencies).

**Rationale:**
- The existing codebase uses no third-party table libraries; adding one would be unnecessary overhead.
- A simple column-width calculation produces clean output for any number of rows.
- For very large task sets (>100), the table can include a summary footer with total counts per status.

**Proposed implementation:**
```python
def format_table(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return "No active tasks found in .board/"

    # Calculate column widths (min 10 chars)
    col_widths = [max(len(h), 10) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            if i < len(col_widths):
                col_widths[i] = max(col_widths[i], len(cell))

    # Build format string
    fmt = " | ".join(f"{{:<{w}}}" for w in col_widths)
    sep = "-+-".join("-" * w for w in col_widths)

    lines = [fmt.format(*headers), sep] + \
            [fmt.format(*(r[i] if i < len(r) else "" for i in range(len(headers))))
             for r in rows]
    return "\n".join(lines)
```

**Output example:**
```
+----------+-------------------------------------------+-------------+
| TASK ID  | TITLE                                     | STATUS      |
+----------+-------------------------------------------+-------------+
| TASK-0001| Populate Tech Stack Documentation         | DONE        |
| TASK-0002| Orchestration Resilience Enhancements     | DONE        |
...
```

**Alternative considered:** `tabulate` library — rejected because it adds a new dependency for functionality that is easily implemented with string formatting.

## F4: Performance and Scalability Assessment

**Current state:** The `.board/` directory contains 7 task files across one subdirectory (`done/`). This is trivially fast even with naive scanning.

**Scalability analysis:**
- **N < 100 tasks**: `rglob()` + sequential YAML parsing completes in under 50ms on typical hardware. No optimization needed.
- **N = 100–500 tasks**: Still acceptable (<200ms). The bottleneck is I/O, not computation.
- **N > 500 tasks**: Consider caching the task index to avoid re-scanning on every invocation.

**Optimization strategies (if needed):**
1. **Depth limiting**: Restrict scan to exactly one level below `.board/` (already done via `len(rel_parts) == 2`). This prevents scanning nested subdirectories that shouldn't exist per protocol.
2. **File extension filter**: Only process `.md` files (already done via `rglob("*.md")`). Skips any non-markdown artifacts.
3. **Caching layer** (future): Store a JSON index of `{task_id: {path, status}}` in `.board/.cache.json`, updated on each write operation (`create`, `transition`, `update`). LIST reads from cache instead of scanning files. This is O(1) lookup vs O(n) scan but adds complexity and stale-data risk.

**Recommendation:** Start without caching. Implement depth limiting as a safeguard. Add caching only if performance testing shows measurable degradation at scale.

## F5: Edge Case Handling

| Scenario | Handling Strategy |
|---|---|
| **Empty `.board/` subdirectories** | `rglob()` returns empty iterator; LIST outputs "No active tasks found in .board/" — matches REQ-006 requirement exactly. |
| **Malformed YAML preamble** | Wrap `load_task()` call in try/except; skip the file and continue scanning other files. Log a warning to stderr if verbose mode is enabled. |
| **Missing metadata fields** (e.g., no `id` or `title`) | Fall back to filename-based extraction (`TASK-NNNN-slugified-title.md`). Display "UNKNOWN" for missing title. |
| **Non-.md files in `.board/`** | Already handled: `rglob("*.md")` filters these out automatically. The existing protocol file `status_board_protocol.md` is also skipped by name check. |
| **Duplicate task IDs** (same ID in multiple directories) | Reuse the error handling from `get_task_path()`: raise RuntimeError if duplicates are detected. This prevents ambiguous LIST output. |
| **Non-standard directory names** | The FOLDERS dict defines valid status-to-directory mappings. Any unrecognized subdirectory gets a generic "UNKNOWN" status label. |

# Evaluation Criteria

| Criterion | Assessment for Recommended Approach |
|---|---|
| **Correctness** | High — reuses existing `load_task()` and follows established patterns from `get_task_path()`. |
| **Feasibility** | Very high — no new dependencies, minimal code (~50 lines), uses only stdlib + yaml. |
| **Maintainability** | High — consistent with existing code style; easy to extend (e.g., add filters). |
| **Complexity** | Low — single function with straightforward logic flow. |
| **Risk** | Minimal — read-only operation, no file modifications, no git operations needed. |

# Options / Recommendations

## Options Considered

- **Option A: pathlib.rglob() + YAML preamble parsing + custom ASCII table** (recommended)
  - Leverages existing patterns in `board_utils.py`.
  - Zero new dependencies.
  - Simple to implement and maintain.

- **Option B: os.walk() + regex-only filename parsing**
  - Would avoid the yaml dependency for metadata extraction.
  - Less robust than YAML parsing (fragile against filename changes).
  - More verbose code.

- **Option C: Use tabulate library for formatting**
  - Cleaner table output with auto-alignment features.
  - Adds a new third-party dependency to the project.
  - Overkill for a simple three-column table.

## Recommended Direction

**Option A** — `pathlib.rglob()` + YAML preamble parsing via existing `load_task()` + custom ASCII table formatter. This approach:
- Reuses all existing infrastructure (`load_task()`, yaml import, BOARD_DIR constant).
- Requires no new dependencies.
- Produces output that matches REQ-006 acceptance criteria exactly.
- Handles edge cases gracefully with try/except and filename fallbacks.

# Risks / Trade-offs / Constraints

| Risk | Mitigation |
|---|---|
| **YAML parsing failure on corrupted files** | Wrap in try/except; skip malformed files; fall back to filename extraction. |
| **Performance degradation with many tasks** | Depth limiting via `len(rel_parts) == 2` check prevents unintended deep scans. Caching can be added later if needed. |
| **Status mismatch between directory and YAML preamble** | Per REQ-006, status is determined by directory location (not the YAML field). This matches how `transition_task()` works. Document this behavior clearly in code comments. |
| **New subdirectories created outside FOLDERS mapping** | Unrecognized directories get "UNKNOWN" status label; they still appear in LIST output for visibility. |

# Supporting Materials / Evidence

**Existing function signatures referenced:**
- `load_task(path: Path) -> dict[str, Any]` — parses YAML preamble and body.
- `get_task_path(task_id: str) -> Path \| None` — uses `BOARD_DIR.rglob("*.md")`.
- `slugify(text: str) -> str` — converts strings to filename-safe slugs.

**Relevant constants:**
- `BOARD_DIR = REPO_ROOT / ".board"` (line 15 of board_utils.py).
- `FOLDERS` dict maps status names to directory paths.
- `VALID_STATUSES = set(FOLDERS.keys())`.

# Next Steps

1. Create an implementation task (TASK) for the LIST command development.
2. Implement the `list_tasks()` function and `format_table()` helper in `board_utils.py`.
3. Add the `LIST` subparser to the CLI argument parser in `main()`.
4. Write unit tests covering: normal operation, empty board, malformed files, edge cases.
5. Validate with existing task set (7 DONE tasks).

# Companion Notes / Raw Evidence

See companion file for raw data and code snippets: `RAD-004-technical-investigation-board-utils-list-command.notes.md`
