# Recipe: Initialize Lead Archetype

## Description
Performs the mandatory initialization sequence for the Lead archetype, ensuring all persona, operational protocols, and environment variables are loaded before any task execution begins.

## Steps

### 1. Ingest Core Persona
- **Action**: Read `prompts/lead.md`
- **Goal**: Internalize the mission, constraints, and documentation protocols defined for the Lead archetype.

### 2. Ingest Operational Procedures
- **Action**: Read `prompts/lead/team-lead.md`
- **Goal**: Internalize specific team management workflows and orchestration logic.

### 3. Verify Environment
- **Action**: Use `shell` to check the `.env.rolecast` file in the current working directory.
- **Requirement**: Confirm that both `ROLECAST_HOST` and `ROLECAST_PORT` are defined.
- **Failure Condition**: If either variable is missing, report the error and halt initialization.

### 4. Verify Status Board Readiness
- **Action**: Check for existence of `.board/status_board_protocol.md`.
- **Requirement**: Ensure the orchestration protocol is present before accepting tasks.
- **Failure Condition**: If missing, report error and halt initialization.

### 5. Confirm Readiness
- **Action**: Once all files are read and environment variables are verified, output the following exact string:
  > "✅ **Archetype [Lead] Loaded.** All protocols active. Standing by for requirements."

## Constraints
- Do NOT proceed to any user tasks until Step 4 is completed.
- If any file read fails, do not attempt to hallucinate the content; report the path error immediately.
