"""
Shared log format constants and validation functions.

Used by both specialist_log.py and compliance_audit.py to ensure
consistent validation of the standardized log entry format:
[TIMESTAMP] - [SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]
"""

import re
from datetime import datetime

# Regex pattern for validating log entry format
ENTRY_PATTERN = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] - \[([^\]]+)\] - \[STATUS: (IN_PROGRESS|COMPLETE|FAILED)\] - \[([^\]]+)\]$"
)

# Valid status labels for log entries
VALID_STATUS_LABELS = {"IN_PROGRESS", "COMPLETE", "FAILED"}


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
