#!/usr/bin/env python3
"""
Compliance Audit & Validation Mechanism (FEAT-006)

Scans all specialist log files and validates entries against the standardized
format defined in REQ-003 FR#2. Produces structured markdown reports with
per-role compliance rates and actionable remediation guidance.

Usage:
    python3 compliance_audit.py [--format json] [--task-id TASK-XXXX]
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

# Repository root and log directories
ROOT_DIR = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT_DIR / "logs" / "specialist_logs"
REPORTS_DIR = ROOT_DIR / "logs" / "compliance_audit"

# Ensure parent directory is on path for imports when run as CLI
sys.path.insert(0, str(ROOT_DIR))

# Import shared validation logic from log_format module
from toolbox.log_format import VALID_STATUS_LABELS  # noqa: E402

# Regex pattern for role-based log file naming: <role>_<YYYYMMDD_HHMMSS>.log
LOG_FILE_PATTERN = re.compile(r"^([a-z0-9_-]+)_\d{8}_\d{6}\.log$")

# Permissive pattern for compliance audit: allows empty brackets (validated separately)
# This enables distinct error keys (empty_subtask, empty_details) for remediation mapping
ENTRY_PATTERN = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] - \[([^\]]*)\] - \[STATUS: (IN_PROGRESS|COMPLETE|FAILED)\] - \[([^\]]*)\]$"
)

# Remediation guidance mapped by issue type
REMEDIATION_GUIDANCE = {
    "empty_line": "Remove empty lines from log files or ensure all lines contain valid entries.",
    "format_mismatch": "Use specialist_log.py LOG command instead of manual file writes. Refer to prompts/snippets/specialist-log-formatting.md for correct format: [TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]",
    "invalid_timestamp": "Ensure timestamp includes complete seconds component (not xx placeholders). Use specialist_log.py LOG command which auto-generates valid timestamps.",
    "empty_subtask": "Provide a non-empty SUBTASK field. Use specialist_log.py LOG --subtask <description>.",
    "invalid_status": "STATUS must be one of: IN_PROGRESS, COMPLETE, FAILED. Use specialist_log.py LOG --status <STATUS>.",
    "empty_details": "Provide non-empty DETAILS field. Use specialist_log.py LOG --details <description>.",
    "filename_pattern": "Log files must follow pattern: <role>_<YYYYMMDD_HHMMSS>.log. Use specialist_log.py LOG --role <role> to create properly named files.",
}


def extract_role(filename: str) -> str | None:
    """Extract the role name from a log filename.

    Returns the role name if the filename matches the expected pattern,
    or None if the pattern does not match.
    """
    match = LOG_FILE_PATTERN.match(filename)
    if match:
        return match.group(1)
    return None


def validate_entry(line: str) -> tuple[bool, str]:
    """Validate a log entry against the required format.

    Returns (True, "") if compliant or (False, issue_type_key) if not.
    Issue keys map to remediation guidance in REMEDIATION_GUIDANCE.
    """
    line = line.strip()

    if not line:
        return (False, "empty_line")

    match = ENTRY_PATTERN.match(line)
    if not match:
        return (False, "format_mismatch")

    timestamp_str = match.group(1)
    subtask = match.group(2)
    status_label = match.group(3)
    details = match.group(4)

    # Validate timestamp is a real date/time
    try:
        datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return (False, "invalid_timestamp")

    # Validate subtask is non-empty
    if not subtask.strip():
        return (False, "empty_subtask")

    # Validate status label
    if status_label not in VALID_STATUS_LABELS:
        return (False, "invalid_status")

    # Validate details is non-empty
    if not details.strip():
        return (False, "empty_details")

    return (True, "")


def validate_file(filepath: Path) -> dict[str, Any]:
    """Validate all entries in a log file.

    Returns a dict with file validation results including violations
    with line numbers and issue descriptions.
    """
    result = {
        "filepath": str(filepath),
        "filename": filepath.name,
        "role": extract_role(filepath.name),
        "total_entries": 0,
        "compliant_entries": 0,
        "violations": [],
    }

    if not filepath.exists():
        return result

    try:
        with open(filepath, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except (IOError, OSError):
        return result

    if not lines or all(line.strip() == "" for line in lines):
        return result

    for line_num, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped:
            continue

        result["total_entries"] += 1
        is_valid, issue = validate_entry(stripped)

        if is_valid:
            result["compliant_entries"] += 1
        else:
            result["violations"].append(
                {
                    "line_number": line_num,
                    "content": stripped,
                    "issue_type": issue,
                    "issue_description": _get_issue_description(issue),
                    "remediation": REMEDIATION_GUIDANCE.get(
                        issue, "Review entry format and correct manually."
                    ),
                }
            )

    return result


def _get_issue_description(issue_type: str) -> str:
    """Human-readable description of an issue type."""
    descriptions = {
        "empty_line": "Empty line found",
        "format_mismatch": "Entry does not match required format: [TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]",
        "invalid_timestamp": "Invalid timestamp value",
        "empty_subtask": "SUBTASK field is empty",
        "invalid_status": "Invalid status label (must be IN_PROGRESS, COMPLETE, or FAILED)",
        "empty_details": "DETAILS field is empty",
        "filename_pattern": "Filename does not match pattern: <role>_<YYYYMMDD_HHMMSS>.log",
    }
    return descriptions.get(issue_type, issue_type)


def scan_log_files() -> list[Path]:
    """Scan the log directory and return all log file paths."""
    if not LOG_DIR.exists():
        return []

    log_files = []
    for filename in sorted(os.listdir(LOG_DIR)):
        filepath = LOG_DIR / filename
        if filepath.is_file():
            log_files.append(filepath)
    return log_files


def aggregate_results(file_results: list[dict[str, Any]]) -> dict[str, Any]:
    """Aggregate validation results across all files.

    Returns a summary dict with overall and per-role compliance statistics.
    """
    summary = {
        "total_files": len(file_results),
        "total_entries": 0,
        "compliant_entries": 0,
        "total_violations": 0,
        "compliant_files": 0,
        "non_compliant_files": 0,
        "per_role": {},
        "file_results": file_results,
    }

    for result in file_results:
        summary["total_entries"] += result["total_entries"]
        summary["compliant_entries"] += result["compliant_entries"]
        summary["total_violations"] += len(result["violations"])

        if result["violations"]:
            summary["non_compliant_files"] += 1
        elif result["total_entries"] > 0:
            summary["compliant_files"] += 1

        # Aggregate by role
        role = result["role"] or "unknown"
        if role not in summary["per_role"]:
            summary["per_role"][role] = {
                "total_files": 0,
                "total_entries": 0,
                "compliant_entries": 0,
                "total_violations": 0,
                "compliant_files": 0,
                "non_compliant_files": 0,
            }

        role_stats = summary["per_role"][role]
        role_stats["total_files"] += 1
        role_stats["total_entries"] += result["total_entries"]
        role_stats["compliant_entries"] += result["compliant_entries"]
        role_stats["total_violations"] += len(result["violations"])

        if result["violations"]:
            role_stats["non_compliant_files"] += 1
        elif result["total_entries"] > 0:
            role_stats["compliant_files"] += 1

    return summary


def _calc_compliance_rate(compliant: int, total: int) -> str:
    """Calculate compliance rate as a percentage string."""
    if total == 0:
        return "N/A (no entries)"
    return "{:.1f}%".format((compliant / total) * 100)


def generate_markdown_report(summary: dict[str, Any]) -> str:
    """Generate a structured markdown compliance report."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    overall_rate = _calc_compliance_rate(
        summary["compliant_entries"], summary["total_entries"]
    )

    lines = [
        "# Compliance Audit Report",
        "",
        "**Audit Date**: {}".format(timestamp),
        "**Feature**: FEAT-006 - Compliance Audit & Validation Mechanism",
        "**Standard**: REQ-003 FR#2 - Specialist Log Format Standardization",
        "",
        "---",
        "",
        "## Summary",
        "",
        "| Metric | Value |",
        "|--------|-------|",
        "| Total log files audited | {} |".format(summary["total_files"]),
        "| Total entries scanned | {} |".format(summary["total_entries"]),
        "| Overall compliance rate | {} |".format(overall_rate),
        "| Compliant files | {} |".format(summary["compliant_files"]),
        "| Non-compliant files | {} |".format(summary["non_compliant_files"]),
        "| Total violations | {} |".format(summary["total_violations"]),
        "",
        "---",
        "",
        "## Per-Role Compliance Rates",
        "",
    ]

    for role, stats in sorted(summary["per_role"].items()):
        role_rate = _calc_compliance_rate(
            stats["compliant_entries"], stats["total_entries"]
        )
        lines.extend(
            [
                "### {}".format(role),
                "",
                "| Metric | Value |",
                "|--------|-------|",
                "| Files | {} |".format(stats["total_files"]),
                "| Total entries | {} |".format(stats["total_entries"]),
                "| Compliance rate | {} |".format(role_rate),
                "| Compliant files | {} |".format(stats["compliant_files"]),
                "| Non-compliant files | {} |".format(stats["non_compliant_files"]),
                "| Violations | {} |".format(stats["total_violations"]),
                "",
            ]
        )

    # Non-compliant entries section
    lines.extend(
        [
            "---",
            "",
            "## Non-Compliant Entries",
            "",
        ]
    )

    has_violations = False
    for result in summary["file_results"]:
        if not result["violations"]:
            continue

        has_violations = True
        lines.extend(
            [
                "### {}".format(result["filename"]),
                "",
            ]
        )
        for violation in result["violations"]:
            lines.extend(
                [
                    "- **Line {}**: {}".format(
                        violation["line_number"], violation["issue_description"]
                    ),
                    "  - Content: `{}`".format(violation["content"]),
                    "  - **Remediation**: {}".format(violation["remediation"]),
                    "",
                ]
            )

    if not has_violations:
        lines.extend(
            [
                "No violations found. All entries are compliant.",
                "",
            ]
        )

    # Remediation section
    lines.extend(
        [
            "---",
            "",
            "## Remediation Guidance",
            "",
            "For non-compliant entries, follow these steps:",
            "",
            "1. **Use the specialist_log.py LOG command** instead of manual file writes:",
            "   ```",
            "   python3 toolbox/specialist_log.py LOG --role <role> --subtask '<subtask>' --status <STATUS> --details '<details>'",
            "   ```",
            "2. **Reference the snippet library** for correct formatting:",
            "   - Read `prompts/snippets/specialist-log-formatting.md` for format examples",
            "   - Correct format: `[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]`",
            "3. **Verify status labels**: Must be one of IN_PROGRESS, COMPLETE, or FAILED",
            "4. **Ensure complete timestamps**: Include seconds component (no xx placeholders)",
            "",
            "---",
            "",
            "## Trend Tracking",
            "",
            "This report is stored in `logs/compliance_audit/` for historical tracking.",
            "Compare compliance rates across consecutive audit runs to measure progress",
            "toward the >=95% compliance target defined in REQ-003.",
            "",
            "---",
            "",
            "*Report generated by compliance_audit.py (FEAT-006)*",
            "",
        ]
    )

    return "\n".join(lines)


def generate_json_report(summary: dict[str, Any]) -> str:
    """Generate a machine-readable JSON compliance report."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    report = {
        "audit_date": timestamp,
        "feature": "FEAT-006",
        "standard": "REQ-003 FR#2",
        "summary": {
            "total_files": summary["total_files"],
            "total_entries": summary["total_entries"],
            "compliant_entries": summary["compliant_entries"],
            "total_violations": summary["total_violations"],
            "compliant_files": summary["compliant_files"],
            "non_compliant_files": summary["non_compliant_files"],
            "overall_compliance_rate": (
                round(summary["compliant_entries"] / summary["total_entries"] * 100, 1)
                if summary["total_entries"] > 0
                else None
            ),
        },
        "per_role": {},
        "violations": [],
    }

    for role, stats in summary["per_role"].items():
        report["per_role"][role] = {
            "total_files": stats["total_files"],
            "total_entries": stats["total_entries"],
            "compliant_entries": stats["compliant_entries"],
            "total_violations": stats["total_violations"],
            "compliance_rate": (
                round(stats["compliant_entries"] / stats["total_entries"] * 100, 1)
                if stats["total_entries"] > 0
                else None
            ),
        }

    for result in summary["file_results"]:
        for violation in result["violations"]:
            report["violations"].append(
                {
                    "file": result["filename"],
                    "line_number": violation["line_number"],
                    "issue_type": violation["issue_type"],
                    "issue_description": violation["issue_description"],
                }
            )

    return json.dumps(report, indent=2)


def save_report(report_content: str, report_format: str) -> Path:
    """Save the report to the reports directory."""
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    if report_format == "json":
        filename = "compliance_audit_{}.json".format(timestamp)
    else:
        filename = "compliance_audit_{}.md".format(timestamp)

    report_path = REPORTS_DIR / filename
    report_path.write_text(report_content, encoding="utf-8")
    return report_path


def log_to_board(task_id: str, summary: dict[str, Any]) -> None:
    """Log audit results to the board task via board_utils.py log_event().

    Logs a compliance rate summary to the specified task for traceability.
    """
    overall_rate = _calc_compliance_rate(
        summary["compliant_entries"], summary["total_entries"]
    )

    log_message = (
        "Compliance audit complete: {} of specialist logs compliant "
        "across all roles ({}/{} files, "
        "{} violations in {} entries)".format(
            overall_rate,
            summary["compliant_files"],
            summary["total_files"],
            summary["total_violations"],
            summary["total_entries"],
        )
    )

    # Import board_utils for log_event
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from board_utils import log_event

    log_event(task_id=task_id, actor="compliance-audit", message=log_message)


def run_audit(format: str = "markdown", task_id: str | None = None) -> dict[str, Any]:
    """Execute the full compliance audit workflow.

    Args:
        format: Output format - "markdown" or "json"
        task_id: Optional task ID to log results to via board_utils

    Returns:
        Dict with audit results and report path.
    """
    # Scan log files
    log_files = scan_log_files()

    # Validate each file
    file_results = []
    for filepath in log_files:
        result = validate_file(filepath)
        file_results.append(result)

    # Aggregate results
    summary = aggregate_results(file_results)

    # Generate report
    if format == "json":
        report_content = generate_json_report(summary)
    else:
        report_content = generate_markdown_report(summary)

    # Save report
    report_path = save_report(report_content, format)

    # Log to board if task_id provided
    if task_id:
        try:
            log_to_board(task_id, summary)
        except Exception as exc:
            print("Warning: Failed to log to board: {}".format(exc), file=sys.stderr)

    return {
        "summary": summary,
        "report_path": str(report_path),
        "report_format": format,
    }


def main() -> None:
    """CLI entry point for compliance audit."""
    parser = argparse.ArgumentParser(
        description="Compliance Audit & Validation Mechanism (FEAT-006)"
    )
    parser.add_argument(
        "--format",
        choices=["markdown", "json"],
        default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument(
        "--task-id",
        default=None,
        help="Task ID to log results to via board_utils (e.g. TASK-0003)",
    )

    args = parser.parse_args()

    print("Running compliance audit...")
    print("Log directory: {}".format(LOG_DIR))
    print("Report format: {}".format(args.format))
    print()

    result = run_audit(format=args.format, task_id=args.task_id)

    summary = result["summary"]
    overall_rate = _calc_compliance_rate(
        summary["compliant_entries"], summary["total_entries"]
    )

    print("Audit complete.")
    print("  Files audited: {}".format(summary["total_files"]))
    print("  Total entries: {}".format(summary["total_entries"]))
    print("  Compliance rate: {}".format(overall_rate))
    print("  Violations: {}".format(summary["total_violations"]))
    print("  Report saved to: {}".format(result["report_path"]))

    if args.task_id:
        print("  Results logged to {}".format(args.task_id))


if __name__ == "__main__":
    main()
