# Specialist Log Formatting Snippet

Standardized format for specialist log entries written to `logs/specialist_logs/<role>_<timestamp>.log`.

## Entry Format

Every log entry must follow this exact format:

```
[TIMESTAMP] - [CURRENT_SUBTASK] - [STATUS: STATUS_LABEL] - [DETAILS]
```

### Field Definitions

- **`TIMESTAMP`**: Current date and time in `YYYY-MM-DD HH:MM:SS` format (project standard, matching `doc_utils.py`).
- **`CURRENT_SUBTASK`**: The name or description of the current subtask being worked on.
- **`STATUS_LABEL`**: One of the valid status labels (see below).
- **`DETAILS`**: A brief description of progress, findings, or error information.

### Valid Status Labels

| Label | Usage |
|---|---|
| `IN_PROGRESS` | Work has started on the subtask |
| `COMPLETE` | The subtask has been finished successfully |
| `FAILED` | The subtask encountered an error or blocker |

## Correct Examples

```
[2026-07-15 14:30:00] - [Implement API endpoint] - [STATUS: IN_PROGRESS] - [Starting implementation of /api/v1/users endpoint]
[2026-07-15 14:45:00] - [Implement API endpoint] - [STATUS: COMPLETE] - [Endpoint implemented and tested successfully]
[2026-07-15 15:00:00] - [Database migration] - [STATUS: FAILED] - [Connection refused to PostgreSQL on port 5432]
```

## Incorrect Examples

```
# WRONG — Missing brackets around fields
2026-07-15 14:30:00 - Implement API endpoint - IN_PROGRESS - Starting work

# WRONG — Wrong timestamp format (slashes instead of dashes)
[2026/07/15 14:30:00] - [Implement API endpoint] - [STATUS: IN_PROGRESS] - [Starting work]

# WRONG — Invalid status label
[2026-07-15 14:30:00] - [Implement API endpoint] - [STATUS: DONE] - [Finished]

# WRONG — Missing STATUS prefix in status field
[2026-07-15 14:30:00] - [Implement API endpoint] - [IN_PROGRESS] - [Starting work]

# WRONG — Missing details field
[2026-07-15 14:30:00] - [Implement API endpoint] - [STATUS: IN_PROGRESS]
```

## Error Report Formatting

When writing a detailed error report due to an environmental blocker, use the `FAILED` status label and include diagnostic information in the details:

```
[2026-07-15 15:00:00] - [Database migration] - [STATUS: FAILED] - [Connection refused to PostgreSQL on port 5432. Diagnostic: pg_isready returned exit code 2. Attempted one retry.]
```

## Logging Frequency

Append status updates to your assigned log file every 2–3 minutes or when a major subtask is completed.
