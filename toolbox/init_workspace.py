import os


def initialize_workspace():
    # Define the directory structure
    internal_structure = [
        "internal-docs/01_requirements",
        "internal-docs/02_analysis",
        "internal-docs/03_design",
        "internal-docs/04_planning/04a_master",
        "internal-docs/04_planning/04b_features",
        "internal-docs/05_review",
        "internal-docs/06_retrospective",
        "internal-docs/07_templates",
    ]

    execution_structure = [
        ".board/to-do",
        ".board/in-progress",
        ".board/done",
    ]

    log_structure = ["logs/specialist_logs"]

    doc_structure = ["docs"]

    # Define the templates content
    # Using the "Atomic Preamble" we agreed upon
    preamble = "---\nid: {id}\ntitle: {title}\nversion: {version}\nstatus: {status}\ncreated: {created}\nupdated: {updated}\nrelated_docs: []\n---\n\n"

    templates = {
        "REQ.md": preamble.format(
            id="REQ-000",
            title="Requirement",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "BUG.md": preamble.format(
            id="BUG-000",
            title="Bug report",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "SPIKE.md": preamble.format(
            id="SPIKE-000",
            title="Research Spike",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "DEC.md": preamble.format(
            id="DEC-000",
            title="Decision",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "RAD.md": preamble.format(
            id="RAD-000",
            title="Requirement Analysis",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "DSGN.md": preamble.format(
            id="DSGN-000",
            title="Design Document",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "PLAN.md": preamble.format(
            id="PLAN-000",
            title="Master Project Plan",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "FEAT.md": preamble.format(
            id="FEAT-000",
            title="Feature Plan",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "BUGFIX.md": preamble.format(
            id="BUGFIX-000",
            title="Bugfix solution",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
        "REVIEW.md": preamble.format(
            id="REVIEW-000",
            title="Feature review",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        )
        + "verdict: null\n",
        "RETRO.md": preamble.format(
            id="RETRO-000",
            title="Retrospective",
            version="1.0.0",
            status="draft",
            created="YYYY-MM-DD HH:MM:SS",
            updated="YYYY-MM-DD HH:MM:SS",
        ),
    }

    print("🚀 Starting workspace initialization...")

    # 1. Create Directories
    for folder in internal_structure:
        os.makedirs(folder, exist_ok=True)
        print(f"  [DIR] Created/Verified: {folder}")

    for folder in log_structure:
        os.makedirs(folder, exist_ok=True)
        print(f"  [DIR] Created/Verified: {folder}")

    for folder in execution_structure:
        os.makedirs(folder, exist_ok=True)
        print(f"  [DIR] Created/Verified: {folder}")

    for folder in doc_structure:
        os.makedirs(folder, exist_ok=True)
        print(f"  [DIR] Created/Verified: {folder}")

    # 2. Create Templates
    template_dir = "internal-docs/07_templates"
    for filename, content in templates.items():
        filepath = os.path.join(template_dir, filename)
        if not os.path.exists(filepath):
            with open(filepath, "w") as f:
                f.write(content)
            print(f"  [TPL] Created: {filepath}")
        else:
            print(f"  [SKIP] Template exists: {filepath}")

    # 3. Create Tech Stack SSoT placeholder
    tech_stack_path = "docs/tech-stack.md"
    if not os.path.exists(tech_stack_path):
        with open(tech_stack_path, "w") as f:
            f.write(
                "---\nid: TECH-001\ntitle: Project Technology Stack\nversion: 1.0.0\nstatus: active\ncreated: YYYY-MM-DD HH:MM:SS\nupdated: YYYY-MM-DD HH:MM:SS\nrelated_docs: []\n---\n\n# Project Tech Stack (SSoT)\n\n## Languages\n- \n\n## Frameworks\n- \n\n## Databases\n- \n"
            )
        print(f"  [DOC] Created: {tech_stack_path}")

    # 4. Create Root README if not exists
    readme_path = "README.md"
    if not os.path.exists(readme_path):
        with open(readme_path, "w") as f:
            f.write(
                "# Project Name\n\n## Executive Summary\n[Summary goes here]\n\n## Documentation Map\n\n"
                "### 01_requirements - Raw stakeholder inputs\n"
                "### 02_analysis - Formalized RADs\n"
                "### 03_design - Architectural blueprints\n"
                "### 04_planning - Master and Feature plans\n"
                "### 05_execution - Active work (Kanban & Logs)\n"
                "### 06_documentation - Final system/user docs\n"
                "### 07_retrospective - Post-mortems\n"
            )
        print(f"  [README] Created: {readme_path}")
    else:
        print("  [SKIP] README already exists.")

    print("✅ Workspace initialization complete!")


if __name__ == "__main__":
    initialize_workspace()
