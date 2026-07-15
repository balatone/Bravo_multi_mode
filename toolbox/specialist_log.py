import os
import re
import sys
from datetime import datetime
from pathlib import Path

# Repository root and log directory locations
ROOT_DIR = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT_DIR / "logs" / "specialist_logs"

# Valid status labels for log entries
VALID_STATUS_LABELS = {"IN_PROGRESS", "COMPLETE", "FAILED"}

# Regex pattern for role-based log file naming: <role>_<YYYYMMDD_HHMMSS>.log
LOG_FILE_PATTERN = re.compile(r"^([a-z0-9_-]+)_\d{8}_\d{6}\.log$")

# Regex pattern for validating log entry format
ENTRY_PATTERN = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] - \[([^\]]+)\] - \[STATUS: (IN_PROGRESS|COMPLETE|FAILED)\] - \[([^\]]+)\]$"
)


def get_next_log_path(role):
    """Returns the path for a role's current log file, creating it if needed.

    Checks for existing log files matching the role prefix. If none exist,
    creates a new one with <role>_<YYYYMMDD_HHMMSS>.log naming convention.
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
    new_filename = f"{role}_{timestamp}.log"
    new_path = LOG_DIR / new_filename
    new_path.touch()
    return new_path


def format_entry(subtask, status, details):
    """Formats a log entry in the standardized format.

    Returns a string in the format:
    [TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]
    """
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"[{timestamp}] - [{subtask}] - [STATUS: {status}] - [{details}]"


def validate_entry(line):
    """Validates a log entry against the required format.

    Returns (True, "") if compliant or (False, "issue description") if not.
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
        return (False, f"Invalid timestamp value: {timestamp_str}")

    # Validate subtask is non-empty
    if not subtask.strip():
        return (False, "SUBTASK field is empty")

    # Validate status label
    if status_label not in VALID_STATUS_LABELS:
        return (
            False,
            f"Invalid status label: {status_label}. Must be one of: {VALID_STATUS_LABELS}",
        )

    # Validate details is non-empty
    if not details.strip():
        return (False, "DETAILS field is empty")

    return (True, "")


def create_log(role, subtask, status, details):
    """Creates a log entry by appending to the role's log file.

    Validates inputs, gets the log path, and appends the formatted entry.
    Returns the file path on success, None on failure.
    """
    # Validate status
    status_upper = status.upper() if status else None
    if status_upper not in VALID_STATUS_LABELS:
        print(
            f"Error: Invalid status '{status}'. Must be one of: {VALID_STATUS_LABELS}"
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

    print(f"Log entry created: {log_path}")
    print(f"  {entry}")
    return str(log_path)


def show_logs(role=None, since=None):
    """Lists log files with optional role and date filtering.

    Args:
        role: Optional role prefix to filter by.
        since: Optional date string (YYYY-MM-DD) to filter entries from that date forward.

    Returns 0 on success, None on failure.
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

        # Filter by role if specified
        if role:
            match = LOG_FILE_PATTERN.match(filename)
            if not match or match.group(1) != role:
                continue

        log_files.append(filepath)

    if not log_files:
        if role:
            print(f"No log files found for role '{role}'.")
        else:
            print("No log files found.")
        return 0

    # Parse since date if provided
    since_date = None
    if since:
        try:
            since_date = datetime.strptime(since, "%Y-%m-%d")
        except ValueError:
            print(f"Error: Invalid date format '{since}'. Expected YYYY-MM-DD")
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
            print(f"Warning: Could not read {log_file}: {e}")
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

            print(f"[{log_file.name}] {line}")
            file_entries += 1
            total_entries += 1

        if file_entries > 0:
            print()  # Blank line between files

    if total_entries == 0:
        print("No log entries found matching the specified filters.")
    else:
        print(
            f"Total: {total_entries} entry/entries displayed across {len(log_files)} file(s)."
        )

    return 0


def validate_log(filepath):
    """Validates all entries in a specified log file against the required format.

    Returns 0 if compliant, 1 if violations found.
    Prints a summary report with line numbers and issues for non-compliant entries.
    """
    # Check if file exists
    if not os.path.exists(filepath):
        print(f"Error: File '{filepath}' not found.")
        return 1

    # Read all lines
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except (IOError, OSError) as e:
        print(f"Error: Could not read file '{filepath}': {e}")
        return 1

    # Handle empty file
    if not lines or all(line.strip() == "" for line in lines):
        print(f"Validation complete: {filepath}")
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
    print(f"Validation complete: {filepath}")
    print(f"  Total entries: {total_lines}")
    print(f"  Compliant: {compliant_count}")
    print(f"  Violations: {len(violations)}")

    if violations:
        print("\nViolation details:")
        for line_num, line, issue in violations:
            print(f"  Line {line_num}: {issue}")
            print(f"    Content: {line}")

    if violations:
        print("\n  Status: NON-COMPLIANT")
        return 1
    else:
        print("\n  Status: COMPLIANT")
        return 0


def main():
    """CLI entry point with sys.argv parsing mirroring doc_utils.py pattern."""
    if len(sys.argv) < 2:
        print("Usage:")
        print(
            '  python3 specialist_log.py LOG --role <role> --subtask "<subtask>" --status STATUS --details "DETAILS"'
        )
        print("  python3 specialist_log.py SHOW [--role <role>] [--since YYYY-MM-DD]")
        print("  python3 specialist_log.py VALIDATE <logfile>")
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
                print(f"Error: Unknown argument '{args[i]}'")
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
                print(f"Error: Unknown argument '{args[i]}'")
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

    else:
        print(f"Unknown command '{cmd}'. Use LOG, SHOW, or VALIDATE.")
        return None


if __name__ == "__main__":
    main()
