---
id: RAD-002-notes
title: Consolidate Specialist Log Tooling — Companion Notes
version: 1.0.0
status: DRAFT
created: 2026-07-16 11:54:30
updated: 2026-07-16 11:54:30
related_docs: ["REQ-004", "RAD-002"]
---

# Companion Notes — Raw Evidence and Detailed Analysis

## Focus: Ensuring Consistent Log Entries Through Unified Validation

The consolidation's primary goal is **log format consistency**. Currently, two different validation patterns exist in the codebase:
- `specialist_log.py` (via `log_format.py`): strict regex `[^\]]+` — rejects empty brackets at parse time
- `compliance_audit.py`: permissive regex `[^\]]*` — allows empty brackets through to secondary checks

This means an entry like `[2026-07-15 18:30:38] - [] - [STATUS: IN_PROGRESS] - [Details]` is rejected by `specialist_log.py create_log()` but would be accepted by the regex in `compliance_audit.py validate_entry()`. The consolidation adopts the **permissive** variant as canonical, ensuring all validation goes through a single code path that produces clear, actionable error messages.

## H. Naming Convention Change — Detailed Impact Analysis

### Current vs. New Format

| Aspect | Current | New (consolidated) |
|---|---|---|
| Pattern | `<role>_<YYYYMMDD_HHMMSS>.log` | `<YYYYMMDD_HHMMSS>_<role>.log` |
| Example | `technical-analyst_20260715_140130.log` | `20260715_140130_technical-analyst.log` |

### Affected Code Paths

#### 1. `get_next_log_path(role)` in `specialist_log.py`
```python
# Current (line ~28):
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
filename = f"{role}_{timestamp}.log"

# New:
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
filename = f"{timestamp}_{role}.log"
```

#### 2. `show_logs(role=None)` in `specialist_log.py` — filtering logic
```python
# Current (line ~108):
if role and not filename.startswith(f"{role}_"):
    continue

# New: need suffix-based match since role is at the end of the name.
# Option A — regex:
import re
pattern = rf"^\d{{8}}_\d{{6}}_re.escape(role)\.log$"
if role and not re.match(pattern, filename):
    continue

# Option B — simple string check (role never contains underscores in practice):
parts = filename[:-4].rsplit("_", 1)  # strip .log, split on last _
if role and parts[-1] != role:
    continue
```

#### 3. `clean_logs(days=30)` in `specialist_log.py` — timestamp parsing
```python
# Current (line ~145):
timestamp_str = filename.split("_")[1]  # "20260715_140130" is at index [1]
file_date = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")

# New: timestamp is now at index [0]:
timestamp_str = filename.split("_")[0]  # "20260715_140130" is at index [0]
file_date = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
```

#### 4. `extract_role(filename)` from `compliance_audit.py` — role extraction
```python
# Current:
def extract_role(filename):
    name = Path(filename).stem  # strip .log
    parts = name.split("_")
    if len(parts) < 2:
        return None
    timestamp_str = "_".join(parts[1:])  # everything after first _
    try:
        datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
    except ValueError:
        return None
    return parts[0]

# New (role is now the last segment):
def extract_role(filename):
    name = Path(filename).stem  # strip .log
    parts = name.rsplit("_", 1)  # split on LAST underscore only
    if len(parts) < 2:
        return None
    timestamp_str = parts[0]  # "YYYYMMDD_HHMMSS" is now the first segment
    try:
        datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
    except ValueError:
        return None
    return parts[-1]  # role name is now the last segment
```

### Test Fixture Updates Required

Both test files contain hardcoded filename strings. Every occurrence of `{role}_{timestamp}.log` must become `{timestamp}_{role}.log`. Key locations:

**test_specialist_log.py**:
- `TestConstants.log_file_pattern`: regex pattern string contains `{role}_` → change to `\d{{8}}_\d{{6}}_{role}`
- All test methods in `TestGetNextLogPath`, `TestCreateLog`, `TestShowLogs`, etc. that construct expected filenames

**test_compliance_audit.py**:
- `TestExtractRole`: all 6 test cases reference `{role}_{timestamp}.log` pattern → update to `{timestamp}_{role}.log`
- `TestValidateFile`: file path construction in fixtures
- Any other filename assertions across the 72 tests

### Backward Compatibility Note

Existing log files on disk (created before this change) will retain the old naming format. The new `clean_logs()` logic parses timestamps from index `[0]`, which would fail on old-format filenames like `role_20260715_140130.log` (timestamp is at index [1]). Two options:
- **Option A**: `clean_logs()` tries both formats — parse timestamp from `[0]` first, fall back to `[1]` if that fails. Simple and safe.
- **Option B**: Leave old files as-is; they won't be cleaned by date-based logic but will eventually be manually archived or the directory will be recreated.

Recommendation: Option A — `clean_logs()` should handle both formats for a smooth transition period. This adds ~3 lines of defensive parsing code and eliminates any risk of orphaned old-format files accumulating indefinitely.

### specialist_log.py imports
```python
import os, re, sys, time
from datetime import datetime
from pathlib import Path
from toolbox.log_format import VALID_STATUS_LABELS, validate_entry, format_entry  # noqa: E402
```

### compliance_audit.py imports
```python
import argparse, json, os, re, sys
from datetime import datetime
from pathlib import Path
from typing import Any
from toolbox.log_format import VALID_STATUS_LABELS  # noqa: E402
# Also defines its own ENTRY_PATTERN and validate_entry() — NOT imported from log_format
```

### log_format.py imports
```python
import re
from datetime import datetime
```
(Zero external dependencies)

## B. Function Export Summary

### specialist_log.py exports (callable by tests/CLI)
| Name | Signature | Purpose |
|---|---|---|
| `get_next_log_path(role)` | `(str) -> Path` | Find/create role's log file |
| `create_log(role, subtask, status, details)` | `(str,str,str,str) -> str|None` | Append formatted entry to log |
| `show_logs(role=None, since=None)` | `(str|None, str|None) -> int|None` | Display filtered entries |
| `validate_log(filepath)` | `(str) -> int|None` | Validate single file, print summary |
| `clean_logs(days=30)` | `(int) -> int|None` | Remove old log files |
| `main()` | `() -> None` | CLI entry point |

### compliance_audit.py exports (callable by tests/CLI)
| Name | Signature | Purpose |
|---|---|---|
| `extract_role(filename)` | `(str) -> str|None` | Extract role from filename |
| `validate_entry(line)` | `(str) -> tuple[bool, str]` | Validate with issue-type keys |
| `validate_file(filepath)` | `(Path) -> dict` | Full file validation → structured result |
| `scan_log_files()` | `() -> list[Path]` | List all log files in LOG_DIR |
| `aggregate_results(file_results)` | `(list[dict]) -> dict` | Compute per-role compliance stats |
| `_calc_compliance_rate(compliant, total)` | `(int,int) -> str` | Format percentage string |
| `_get_issue_description(issue_type)` | `(str) -> str` | Human-readable issue text |
| `generate_markdown_report(summary)` | `(dict) -> str` | Markdown report content |
| `generate_json_report(summary)` | `(dict) -> str` | JSON report content |
| `save_report(content, format)` | `(str,str) -> Path` | Write report to disk |
| `log_to_board(task_id, summary)` | `(str,dict) -> None` | Board integration via board_utils |
| `run_audit(format, task_id)` | `(str,str|None) -> dict` | Full audit workflow → results+path |

### log_format.py exports (callable by both consumers)
| Name | Signature | Purpose |
|---|---|---|
| `ENTRY_PATTERN` | `Pattern[str]` | Regex for entry format validation |
| `VALID_STATUS_LABELS` | `set[str]` | {"IN_PROGRESS", "COMPLETE", "FAILED"} |
| `validate_entry(line)` | `(str) -> tuple[bool, str]` | Validate with human-readable message |
| `format_entry(subtask, status, details)` | `(str,str,str) -> str` | Format entry string |

## C. Test Count Breakdown (detailed)

### test_specialist_log.py — 63 tests across 8 classes
1. **TestConstants** (5): root_dir_exists, log_dir_defined, valid_status_labels, log_file_pattern, entry_pattern
2. **TestGetNextLogPath** (2): creates_directory_if_needed, returns_existing_file
3. **TestFormatEntry** (7): returns_string, contains_timestamp/subtask/status/details, validates_correctly, all_statuses
4. **TestValidateEntry** (12): valid_in_progress/complete/failed, empty_line, whitespace_only, invalid_format, invalid_status, missing_details, missing_subtask, invalid_timestamp, special_characters
5. **TestCreateLog** (13): invalid_status, empty_subtask/details, None subtask/details, whitespace_only, case_insensitive, creates_file, appends_to_existing
6. **TestShowLogs** (6): empty_directory, no_matching_role, invalid_date, valid_date_filter, creates_directory_if_missing
7. **TestValidateLog** (5): file_not_found, empty_file, compliant_file, non_compliant_file, only_empty_lines
8. **TestCleanLogs** (4): no_log_directory, no_old_files, removes_old_files, custom_days
9. **TestMain** (10): no_arguments, unknown_command, log_missing_role/subtask/status/details, validate_missing_filepath, show_no_args, clean_default/with_days/invalid_days
10. **TestIntegration** (3): create_and_validate, create_multiple_entries, shared_module_imports

### test_compliance_audit.py — 72 tests across 8 classes
1. **TestConstants** (6): root_dir_exists, log_dir_defined, reports_dir_defined, valid_status_labels, log_file_pattern, entry_pattern, remediation_guidance_has_entries
2. **TestExtractRole** (6): valid_filename/hyphen/underscore, invalid_filename/no_timestamp, empty_string
3. **TestValidateEntry** (12): valid_in_progress/complete/failed, empty_line, whitespace_only, format_mismatch, invalid_status_label, missing_details/subtask, invalid_timestamp, special_characters, legacy_format_without_brackets
4. **TestValidateFile** (7): nonexistent_file, empty_file, compliant_file, non_compliant_file, file_with_role, file_with_invalid_role_name, mixed_compliance_file
5. **TestScanLogFiles** (3): existing_directory, returns_path_objects, empty_directory, nonexistent_directory
6. **TestAggregateResults** (4): empty_results, single_compliant/non_compliant, multiple_roles, unknown_role
7. **TestCalcComplianceRate** (4): full/partial/zero compliance, no_entries, one_decimal_precision
8. **TestGetIssueDescription** (2): format_mismatch, invalid_status, unknown_type
9. **TestGenerateMarkdownReport** (6): contains_summary/per_role/violations/remediation/trend_tracking/path, no_violations_message
10. **TestGenerateJsonReport** (3): json_is_valid, zero_entries, per_role_rate
11. **TestSaveReport** (3): save_markdown/json, creates_directory_if_needed
12. **TestRunAudit** (5): returns_results, json_format, summary_structure, report_saved, report_in_logs_dir
13. **TestSharedModule** (3): uses_shared_valid_status_labels, uses_shared_format_entry, has_own_entry_pattern
14. **TestIntegration** (2): full_audit_workflow, audit_with_json_output

## D. Validation Logic Comparison — What Needs Unifying

### specialist_log.py → log_format.py validate_entry()
```python
def validate_entry(line):
    if not line or not line.strip():
        return False, "Empty entry"

    match = ENTRY_PATTERN.match(line)  # strict: [^\]]+ requires non-empty
    if not match:
        return False, f"Entry does not match required format: {line}"

    timestamp_str, subtask, status, details = match.groups()

    try:
        datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return False, "Invalid timestamp"

    if not subtask.strip():
        return False, "SUBTASK field is empty"
    if not details.strip():
        return False, "DETAILS field is empty"

    return True, ""
```

### compliance_audit.py validate_entry() — permissive variant
```python
def validate_entry(line):
    if not line or not line.strip():
        return False, "empty_line"  # issue-type key

    match = ENTRY_PATTERN.match(line)  # permissive: [^\]]* allows empty
    if not match:
        return False, "format_mismatch"  # structural problem

    timestamp_str, subtask, status, details = match.groups()

    try:
        datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return False, "invalid_timestamp"

    if not subtask.strip():
        return False, "empty_subtask"  # distinct key for remediation mapping

    if not details.strip():
        return False, "empty_details"

    return True, ""
```

### Consolidation Decision: Permissive regex + human-readable messages
The consolidated `validate_entry()` will use the **permissive** `[^\]]*` pattern but produce **human-readable error messages** (not issue-type keys). This ensures that when an agent calls `create_log()` with a malformed entry, they get a clear message like "SUBTASK field is empty" rather than a generic format rejection or a machine key. The permissive regex catches structural issues; secondary checks catch semantic issues — all through one code path.

## E. What from compliance_audit.py Is Kept vs. Discarded for Log Consistency

## F. ENTRY_PATTERN Regex Comparison

| Module | Pattern | Empty brackets allowed? |
|---|---|---|
| `log_format.py` (strict) | `[^\]]+` | No — requires at least one character |
| `compliance_audit.py` (permissive) | `[^\]]*` | Yes — zero characters match |

**Consolidation decision**: Adopt the **permissive** variant (`[^\]]*`) as canonical. This allows empty brackets through to secondary validation, which produces clear error messages like "SUBTASK field is empty" instead of a generic format rejection. No valid entry becomes invalid; previously-rejected entries now get better diagnostics.

## G. validate_entry() Return Value Comparison

| Module | Success return | Failure return |
|---|---|---|
| `log_format.py` | `(True, "")` | `(False, "human-readable message")` |
| `compliance_audit.py` | `(True, "")` | `(False, "issue_type_key")` |

**Consolidation decision**: Keep the human-readable return format from `log_format.py`. This ensures backward compatibility with existing VALIDATE command output and agent-facing error messages. No issue-type keys needed — agents need to know *what's wrong*, not a machine code for remediation mapping.
