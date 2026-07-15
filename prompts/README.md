# Prompt Library Standards

This directory contains the prompt templates used to define agent roles and specific model implementations.

**IMPORTANT: Do not use general project documentation standards for these files. These files use a specialized YAML preamble for machine-readability and orchestration.**

## Directory Structure

- `prompts/`: Contains **Role** files (base role definitions).
- `prompts/{archetype}/`: Contains **Specialist** files (specific model implementations for that archetype).

---

## 1. Role Files
**Location:** Directly under the `prompts/` directory.
**Purpose:** Defines a base role (e.g., lead, worker, analyst, reviewer).

### Schema
```yaml
---
mode: [append|replace]
version: [SemVer]
name: [lead|worker|analyst|reviewer]
type: archetype
---
```

---

## 2. Specialist Files
**Location:** Inside an archetype subdirectory (e.g., `prompts/worker/`).
**Purpose:** Defines a specific model implementation for a role.

### Schema
```yaml
---
version: [SemVer]
archetype: [lead|worker|analyst|reviewer]
name: [model_id_from_manifest]
type: specialist
---
```

### Field Requirements
- **`archetype`**: Must match the name of the parent directory.
- **`name`**:
    - For existing roles: Must match the `id` specified in `models_manifest.yaml`.
    - For new/unlisted roles (e.g., analyst, reviewer): Use a descriptive placeholder name.

---

## Maintenance & Verification

### Spelling
Always use the American spelling **`specialty`** for all metadata and content within this directory.

### Validation
Before committing changes to this directory, run the verification script from the project root:
```bash
python3 toolbox/verify_prompts.py
```
