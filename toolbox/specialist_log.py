import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

# Repository root and log directory locations
ROOT_DIR = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT_DIR / "logs" / "specialist_logs"
REPORTS_DIR = ROOT_DIR / "logs" / "compliance_audit"

# Ensure parent directory is on path for imports when run as CLI
sys.path.insert(0, str(ROOT_DIR))

# ---------------------------------------------------------------------------
# Module-level constants (inlined from log_format.py)
# ---------------------------------------------------------------------------

# Regex pattern for validating log entry format (permissive variant with [^\]]*)
# Allows empty brackets so secondary checks can produce distinct error keys
ENTRY_PATTERN = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] - \[([^\]]*)\] - \[STATUS: (IN_PROGRESS|COMPLETE|FAILED)\] - \[([^\]]*)\]$"
)

# Valid status labels for log entries
VALID_STATUS_LABELS = {"IN_PROGRESS", "COMPLETE", "FAILED"}

# Regex pattern for role-based log file naming: <YYYYMMDD_HHMMSS>_<role>.log
LOG_FILE_PATTERN = re.compile(r"^\d{8}_\d{6}_([a-z0-9_-]+)\.log$")


# ---------------------------------------------------------------------------
# Validation functions (inlined from log_format.py)
# ---------------------------------------------------------------------------


def validate_entry(line):
    """Validate a log entry against the required format.

    Args:
        line: The log entry string to validate.

    Returns:
        Tuple of (bool, str): (True, "") if compliant,
        (False, issue_description) if not.
    """
    line = line.strip()

    if not line:
        return (False, "Empty line")

    match = ENTRY_PATTERN.match(line)
    if not match:
        return (
            False,
            "Entry does not match required format: [TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]",
        )

    timestamp_str = match.group(1)
    subtask = match.group(2)
    status_label = match.group(3)
    details = match.group(4)

    # Validate timestamp is a real date/time
    try:
        datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return (False, "Invalid timestamp value: {}".format(timestamp_str))

    # Validate subtask is non-empty
    if not subtask.strip():
        return (False, "SUBTASK field is empty")

    # Validate status label
    if status_label not in VALID_STATUS_LABELS:
        return (
            False,
            "Invalid status label: {}. Must be one of: {}".format(
                status_label, VALID_STATUS_LABELS
            ),
        )

    # Validate details is non-empty
    if not details.strip():
        return (False, "DETAILS field is empty")

    return (True, "")


def format_entry(subtask, status, details):
    """Format a log entry in the standardized format.

    Args:
        subtask: Description of the current subtask.
        status: Status label (IN_PROGRESS, COMPLETE, or FAILED).
        details: Brief description of progress or findings.

    Returns:
        Formatted string in the format:
        [TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]
    """
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return "[{}] - [{}] - [STATUS: {}] - [{}]".format(
        timestamp, subtask, status, details
    )


# ---------------------------------------------------------------------------
# Diagnostic utilities (folded from compliance_audit.py)
# ---------------------------------------------------------------------------


def _calc_compliance_rate(compliant, total):
    """Calculate compliance rate as a percentage string."""
    if total == 0:
        return "N/A (no entries)"
    return "{:.1f}%".format((compliant / total) * 100)


def _get_issue_description(issue_type):
    """Human-readable description of an issue type."""
    descriptions = {
        "empty_line": "Empty line found",
        "format_mismatch": "Entry does not match required format: [TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]",
        "invalid_timestamp": "Invalid timestamp value",
        "empty_subtask": "SUBTASK field is empty",
        "invalid_status": "Invalid status label (must be IN_PROGRESS, COMPLETE, or FAILED)",
        "empty_details": "DETAILS field is empty",
        "filename_pattern": "Filename does not match pattern: <YYYYMMDD_HHMMSS>_<role>.log",
    }
    return descriptions.get(issue_type, issue_type)


def extract_role(filename):
    """Extract the role name from a log filename.

    Parses <YYYYMMDD_HHMMSS>_<role>.log format.
    Returns the role name if the filename matches the expected pattern,
    or None if the pattern does not match.
    """
    match = LOG_FILE_PATTERN.match(filename)
    if match:
        return match.group(1)
    return None


def validate_file(filepath):
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
                    "issue_type": _classify_issue(issue),
                    "issue_description": issue,
                    "remediation": REMEDIATION_GUIDANCE.get(
                        _classify_issue(issue),
                        "Review entry format and correct manually.",
                    ),
                }
            )

    return result


# Remediation guidance mapped by issue type
REMEDIATION_GUIDANCE = {
    "empty_line": "Remove empty lines from log files or ensure all lines contain valid entries.",
    "format_mismatch": "Use specialist_log.py LOG command instead of manual file writes. Refer to prompts/snippets/specialist-log-formatting.md for correct format: [TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]",
    "invalid_timestamp": "Ensure timestamp includes complete seconds component (not xx placeholders). Use specialist_log.py LOG command which auto-generates valid timestamps.",
    "empty_subtask": "Provide a non-empty SUBTASK field. Use specialist_log.py LOG --subtask <description>.",
    "invalid_status": "STATUS must be one of: IN_PROGRESS, COMPLETE, FAILED. Use specialist_log.py LOG --status <STATUS>.",
    "empty_details": "Provide non-empty DETAILS field. Use specialist_log.py LOG --details <description>.",
    "filename_pattern": "Log files must follow pattern: <YYYYMMDD_HHMMSS>_<role>.log. Use specialist_log.py LOG --role <role> to create properly named files.",
}


def _classify_issue(issue_description):
    """Map a human-readable issue description to an issue type key.

    Used by validate_file to produce issue_type keys for remediation mapping.
    """
    if "Empty line" in issue_description:
        return "empty_line"
    elif "required format" in issue_description:
        return "format_mismatch"
    elif "timestamp" in issue_description.lower():
        return "invalid_timestamp"
    elif "SUBTASK" in issue_description:
        return "empty_subtask"
    elif "status label" in issue_description.lower():
        return "invalid_status"
    elif "DETAILS" in issue_description:
        return "empty_details"
    return "format_mismatch"


# ---------------------------------------------------------------------------
# CLI command functions
# ---------------------------------------------------------------------------


def get_next_log_path(role):
    """Returns the path for a role's current log file, creating it if needed.

    Checks for existing log files matching the role suffix. If none exist,
    creates a new one with <YYYYMMDD_HHMMSS>_<role>.log naming convention.
    Returns the most recent existing file or the newly created file path.
    """
    # Ensure log directory exists
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    # Find existing log files for this role
    existing_files = []
    for filename in os.listdir(LOG_DIR):
        match = LOG_FILE_PATTERN.match(filename)
        if match and match.group(1) == role:
            existing_files.append(LOG_DIR / filename)

    if existing_files:
        # Return the most recent file
        return max(existing_files)

    # Create a new log file
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    new_filename = "{}_{}.log".format(timestamp, role)
    new_path = LOG_DIR / new_filename
    new_path.touch()
    return new_path


def create_log(role, subtask, status, details):
    """Creates a log entry by appending to the role's log file.

    Validates inputs, gets the log path, and appends the formatted entry.
    Returns the file path on success, None on failure with error printed to stdout.
    """
    # Validate status
    status_upper = status.upper() if status else None
    if status_upper not in VALID_STATUS_LABELS:
        print(
            "Error: Invalid status '{}'. Must be one of: {}".format(
                status, VALID_STATUS_LABELS
            )
        )
        return None

    # Validate subtask
    if not subtask or not subtask.strip():
        print("Error: subtask is required and cannot be empty")
        return None

    # Validate details
    if not details or not details.strip():
        print("Error: details is required and cannot be empty")
        return None

    # Get log file path
    log_path = get_next_log_path(role)
    if log_path is None:
        print("Error: Failed to get log file path")
        return None

    # Format and append entry
    entry = format_entry(subtask.strip(), status_upper, details.strip())
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(entry + "\n")

    print("Log entry created: {}".format(log_path))
    print("  {}".format(entry))
    return str(log_path)


def show_logs(role=None, since=None):
    """Lists log files with optional role and date filtering.

    Args:
        role: Optional role suffix to filter by.
        since: Optional date string (YYYY-MM-DD) to filter entries from that date forward.

    Returns the number of entries displayed on success, None on failure with error printed to stdout.
    """
    # Ensure log directory exists
    if not LOG_DIR.exists():
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        print("No log files found. Log directory created.")
        return 0

    # Find matching log files
    log_files = []
    for filename in os.listdir(LOG_DIR):
        filepath = LOG_DIR / filename

        # Filter by role if specified (role is at end of filename)
        if role:
            match = LOG_FILE_PATTERN.match(filename)
            if not match or match.group(1) != role:
                continue

        log_files.append(filepath)

    if not log_files:
        if role:
            print("No log files found for role '{}'.".format(role))
        else:
            print("No log files found.")
        return 0

    # Parse since date if provided
    since_date = None
    if since:
        try:
            since_date = datetime.strptime(since, "%Y-%m-%d")
        except ValueError:
            print("Error: Invalid date format '{}'. Expected YYYY-MM-DD".format(since))
            return None

    # Sort files by modification time (chronological)
    log_files.sort(key=lambda p: p.stat().st_mtime)

    # Display entries
    total_entries = 0
    for log_file in log_files:
        try:
            with open(log_file, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except (IOError, OSError) as e:
            print("Warning: Could not read {}: {}".format(log_file, e))
            continue

        file_entries = 0
        for line in lines:
            line = line.strip()
            if not line:
                continue

            # Filter by date if since is specified
            if since_date:
                # Extract timestamp from entry
                ts_match = re.match(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]", line)
                if ts_match:
                    try:
                        entry_date = datetime.strptime(
                            ts_match.group(1), "%Y-%m-%d %H:%M:%S"
                        )
                        if entry_date.date() < since_date.date():
                            continue
                    except ValueError:
                        # If timestamp is invalid, skip the entry
                        continue
                else:
                    # Cannot parse date from entry, skip
                    continue

            print("[{}] {}".format(log_file.name, line))
            file_entries += 1
            total_entries += 1

        if file_entries > 0:
            print()  # Blank line between files

    if total_entries == 0:
        print("No log entries found matching the specified filters.")
    else:
        print(
            "Total: {} entry/entries displayed across {} file(s).".format(
                total_entries, len(log_files)
            )
        )

    return total_entries


def validate_log(filepath):
    """Validates all entries in a specified log file against the required format.

    Returns the number of compliant entries on success, None on failure with error printed to stdout.
    Prints a summary report with line numbers and issues for non-compliant entries.
    """
    # Check if file exists
    if not os.path.exists(filepath):
        print("Error: File '{}' not found.".format(filepath))
        return None

    # Read all lines
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except (IOError, OSError) as e:
        print("Error: Could not read file '{}': {}".format(filepath, e))
        return None

    # Handle empty file
    if not lines or all(line.strip() == "" for line in lines):
        print("Validation complete: {}".format(filepath))
        print("  File is empty - no violations found.")
        print("  Status: COMPLIANT")
        return 0

    # Validate each line
    violations = []
    compliant_count = 0
    total_lines = 0

    for line_num, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped:
            continue  # Skip empty lines

        total_lines += 1
        is_valid, issue = validate_entry(stripped)

        if is_valid:
            compliant_count += 1
        else:
            violations.append((line_num, stripped, issue))

    # Print summary report
    print("Validation complete: {}".format(filepath))
    print("  Total entries: {}".format(total_lines))
    print("  Compliant: {}".format(compliant_count))
    print("  Violations: {}".format(len(violations)))

    if violations:
        print("\nViolation details:")
        for line_num, line, issue in violations:
            print("  Line {}: {}".format(line_num, issue))
            print("    Content: {}".format(line))

    if violations:
        print("\n  Status: NON-COMPLIANT")
        return compliant_count
    else:
        print("\n  Status: COMPLIANT")
        return compliant_count


def clean_logs(days=30):
    """Remove log files older than the specified number of days.

    Args:
        days: Retention period in days (default: 30).

    Returns the number of files removed on success, None on failure with error printed to stdout.
    """
    if not LOG_DIR.exists():
        print("Log directory does not exist. Nothing to clean.")
        return 0

    cutoff_time = time.time() - (days * 86400)
    removed_count = 0

    for filename in os.listdir(LOG_DIR):
        filepath = LOG_DIR / filename
        if not filepath.is_file():
            continue

        if filepath.stat().st_mtime < cutoff_time:
            try:
                filepath.unlink()
                print("Removed: {}".format(filepath))
                removed_count += 1
            except (IOError, OSError) as e:
                print("Error: Could not remove {}: {}".format(filepath, e))

    print(
        "Clean complete: {} file(s) removed (retention: {} days).".format(
            removed_count, days
        )
    )
    return removed_count


def main():
    """CLI entry point with sys.argv parsing mirroring doc_utils.py pattern."""
    if len(sys.argv) < 2:
        print("Usage:")
        print(
            '  python3 specialist_log.py LOG --role <role> --subtask "<subtask>" --status STATUS --details "DETAILS"'
        )
        print("  python3 specialist_log.py SHOW [--role <role>] [--since YYYY-MM-DD]")
        print("  python3 specialist_log.py VALIDATE <logfile>")
        print("  python3 specialist_log.py CLEAN [--days <days>]")
        return None

    cmd = sys.argv[1].upper()

    if cmd == "LOG":
        # Parse arguments for LOG command
        args = sys.argv[2:]

        role = None
        subtask = None
        status = None
        details = None

        i = 0
        while i < len(args):
            if args[i] == "--role" and i + 1 < len(args):
                role = args[i + 1]
                i += 2
            elif args[i] == "--subtask" and i + 1 < len(args):
                subtask = args[i + 1]
                i += 2
            elif args[i] == "--status" and i + 1 < len(args):
                status = args[i + 1]
                i += 2
            elif args[i] == "--details" and i + 1 < len(args):
                details = args[i + 1]
                i += 2
            else:
                print("Error: Unknown argument '{}'".format(args[i]))
                return None

        if not role:
            print("Error: --role is required")
            return None

        if not subtask:
            print("Error: --subtask is required")
            return None

        if not status:
            print("Error: --status is required")
            return None

        if not details:
            print("Error: --details is required")
            return None

        result = create_log(role, subtask, status, details)
        return result

    elif cmd == "SHOW":
        # Parse arguments for SHOW command
        args = sys.argv[2:]

        role = None
        since = None

        i = 0
        while i < len(args):
            if args[i] == "--role" and i + 1 < len(args):
                role = args[i + 1]
                i += 2
            elif args[i] == "--since" and i + 1 < len(args):
                since = args[i + 1]
                i += 2
            else:
                print("Error: Unknown argument '{}'".format(args[i]))
                return None

        result = show_logs(role=role, since=since)
        return result

    elif cmd == "VALIDATE":
        # Parse arguments for VALIDATE command
        if len(sys.argv) < 3:
            print("Error: VALIDATE requires <logfile>")
            return None

        filepath = sys.argv[2]
        result = validate_log(filepath)
        return result

    elif cmd == "CLEAN":
        # Parse arguments for CLEAN command
        args = sys.argv[2:]

        days = 30  # default retention period

        i = 0
        while i < len(args):
            if args[i] == "--days" and i + 1 < len(args):
                try:
                    days = int(args[i + 1])
                except ValueError:
                    print("Error: --days must be an integer")
                    return None
                i += 2
            else:
                print("Error: Unknown argument '{}'".format(args[i]))
                return None

        result = clean_logs(days=days)
        return result

    else:
        print("Unknown command '{}'. Use LOG, SHOW, VALIDATE, or CLEAN.".format(cmd))
        return None


if __name__ == "__main__":
    main()
