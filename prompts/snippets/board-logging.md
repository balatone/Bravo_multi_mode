# Board Logging Snippet

Standardized instructions for recording events on the project status board via `toolbox/board_utils.py`.

## Command Format

To log an event for a task, use the following command:

```bash
uv run toolbox/board_utils.py log <TASK-ID> --actor "<role>" --message "<msg>"
```

### Required Fields

- **`<TASK-ID>`**: The ID of the task (e.g., `TASK-001`). The task must exist in `.board/`.
- **`--actor`**: The role name of the agent performing the action (e.g., `"backend-engineer"`, `"reviewer"`, `"analyst"`).
- **`--message`**: A concise description of the event or progress update.

### Example

```bash
uv run toolbox/board_utils.py log TASK-0003 --actor "backend-engineer" --message "Completed FEAT-004 snippet library implementation"
```

## Timing Rules

Log events at the following points in the task lifecycle:

- **Task Transition**: When moving a task between statuses (e.g., `IMPLEMENTING` → `TESTING`).
- **Completion**: When a task or significant subtask is completed.
- **Error Conditions**: When encountering a blocker or failure that requires attention.

## Git Persistence

Each log entry is automatically committed to git with a message in the format: `chore: log event for <TASK-ID>`. The board is staged before committing.

## Log Entry Format

Entries are appended to the task body in the following format:

```
[YYYY-MM-DD HH:MM:SS] - [<actor>] - <message>
```
