import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# Repository root and template locations
ROOT_DIR = Path(__file__).resolve().parent.parent
TEMPLATE_DIR = ROOT_DIR / "internal-docs" / "07_templates"

# Mapping of Type IDs to their respective directories
TYPE_MAP = {
    "REQ": "internal-docs/01_requirements",
    "BUG": "internal-docs/01_requirements",
    "RAD": "internal-docs/02_analysis",
    "SPIKE": "internal-docs/02_analysis",
    "DSGN": "internal-docs/03_design",
    "DEC": "internal-docs/03_design",
    "PLAN": "internal-docs/04_planning/04a_master",
    "FEAT": "internal-docs/04_planning/04b_features",
    "BUGFIX": "internal-docs/04_planning/04b_features",
    "REVIEW": "internal-docs/05_review",
    "RETRO": "internal-docs/06_retrospective",
}

# Valid Lifecycle Statuses (for all documents)
LIFECYCLE_STATUSES = {
    "DRAFT",
    "IN_REVIEW",
    "APPROVED",
    "SUPERSEDED",
    "DEPRECATED",
    "ARCHIVED",
}

# Valid Review Verdicts (only for REVIEW documents)
REVIEW_VERDICTS = {"APPROVED", "REQUEST_CHANGES", "REJECTED"}

# Valid Priority Values
PRIORITY_VALUES = {"CRITICAL", "HIGH", "MEDIUM", "LOW", "TRIVIAL"}

# Document types allowed to have a priority field
ALLOWED_PRIORITY_TYPES = {"BUG", "REQ", "BUGFIX", "FEAT"}


def get_next_id(directory, type_prefix):
    """Scans the directory for existing files of a certain type and returns the next ID."""
    if not os.path.exists(directory):
        return f"{type_prefix}-001"

    existing_files = os.listdir(directory)
    pattern = re.compile(rf"^{type_prefix}-(\d{{3}})")

    max_num = 0
    for filename in existing_files:
        match = pattern.match(filename)
        if match:
            num = int(match.group(1))
            if num > max_num:
                max_num = num

    return f"{type_prefix}-{str(max_num + 1).zfill(3)}"


def slugify(text):
    """Converts a string into a URL-friendly slug."""
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def load_template(doc_type):
    """Loads the matching document template, if one exists."""
    template_path = TEMPLATE_DIR / f"{doc_type}.md"
    if not template_path.exists():
        return None
    return template_path.read_text(encoding="utf-8")


def render_template(template_text, replacements):
    """Renders a template by replacing selected YAML preamble fields."""
    preamble_match = re.search(r"^---\s*\n(.*?)\n---\s*\n", template_text, re.DOTALL)
    if not preamble_match:
        return None

    preamble_text = preamble_match.group(1)
    body = template_text[preamble_match.end() :]
    lines = preamble_text.splitlines()
    new_lines = []
    seen = set()

    for line in lines:
        if ":" not in line:
            new_lines.append(line)
            continue

        key, _ = line.split(":", 1)
        key = key.strip()
        if key in replacements:
            new_lines.append(f"{key}: {replacements[key]}")
            seen.add(key)
        else:
            new_lines.append(line)

    for key, value in replacements.items():
        if key not in seen and not any(
            existing.startswith(f"{key}:") for existing in new_lines
        ):
            new_lines.append(f"{key}: {value}")

    return "---\n" + "\n".join(new_lines) + "\n---\n" + body.lstrip("\n")


def create_document(doc_type, title):
    """Creates a new document from the matching template and auto-incremented ID."""
    if doc_type not in TYPE_MAP:
        print(f"Error: Unknown doc_type '{doc_type}'")
        return None

    target_dir = ROOT_DIR / TYPE_MAP[doc_type]
    target_dir.mkdir(parents=True, exist_ok=True)

    new_id = get_next_id(str(target_dir), doc_type)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    slug = slugify(title)
    filename = f"{new_id}-{slug}.md"
    filepath = target_dir / filename

    if filepath.exists():
        print(f"Error: File {filepath} already exists.")
        return None

    template_text = load_template(doc_type)
    replacements = {
        "id": new_id,
        "title": title,
        "status": "DRAFT",
        "created": now,
        "updated": now,
        "related_docs": "[]",
    }

    rendered = None
    if template_text:
        rendered = render_template(template_text, replacements)
        if rendered is None:
            print(
                f"Warning: Template {doc_type}.md is malformed; falling back to generic document skeleton."
            )

    if rendered is None:
        rendered = (
            f"---\n"
            f"id: {new_id}\n"
            f"title: {title}\n"
            f"version: 1.0.0\n"
            f"status: DRAFT\n"
            f"created: {now}\n"
            f"updated: {now}\n"
            f"related_docs: []\n"
            f"---\n"
            f"\n"
            f"# {title}\n"
        )

    filepath.write_text(rendered, encoding="utf-8")
    print(f"Created {doc_type} document: {filepath}")
    return str(filepath)


def update_document(filepath, status, verdict=None, priority=None, related_docs=None):
    """
    Updates the 'status', 'verdict', and/or 'priority' in a document's YAML preamble.
    - Verdict is strictly for REVIEW documents.
    - Priority is strictly for BUG, REQ, BUGFIX, and FEAT documents.
    """
    if not os.path.exists(filepath):
        print(f"Error: File {filepath} not found.")
        return None

    filename = os.path.basename(filepath)

    # 1. Validate Lifecycle Status
    status_upper = status.upper()
    if status_upper not in LIFECYCLE_STATUSES:
        print(
            f"Error: Invalid lifecycle status '{status}'. Must be one of: {LIFECYCLE_STATUSES}"
        )
        return None

    # 2. Validate Verdict and Document Type
    verdict_upper = None
    if verdict:
        verdict_upper = verdict.upper()
        if verdict_upper not in REVIEW_VERDICTS:
            print(
                f"Error: Invalid review verdict '{verdict}'. Must be one of: {REVIEW_VERDICTS}"
            )
            return None

        # Check if the file is in a REVIEW directory
        review_dir = ROOT_DIR / TYPE_MAP["REVIEW"]
        if not os.path.abspath(filepath).startswith(os.path.abspath(review_dir)):
            print(
                f"Error: Verdict can only be applied to documents in the '{review_dir}' directory."
            )
            return None

    # 3. Validate Priority and Document Type
    priority_upper = None
    if priority:
        priority_upper = priority.upper()
        if priority_upper not in PRIORITY_VALUES:
            print(
                f"Error: Invalid priority '{priority}'. Must be one of: {PRIORITY_VALUES}"
            )
            return None

        doc_type_match = None
        for t in ALLOWED_PRIORITY_TYPES:
            if filename.startswith(f"{t}-"):
                doc_type_match = t
                break

        if not doc_type_match:
            print(
                f"Error: Priority can only be applied to {sorted(ALLOWED_PRIORITY_TYPES)} documents."
            )
            return None

    # 4. Validate Related Docs (if provided)
    related_docs_list = None
    if related_docs is not None:
        try:
            related_docs_list = json.loads(related_docs)
            if not isinstance(related_docs_list, list):
                raise ValueError("related_docs must be a JSON list")
        except (json.JSONDecodeError, ValueError) as e:
            print(
                f'Error parsing related_docs: {str(e)}. Expected format: \'["ID-001", "ID-002"]\''
            )
            return None

    content = Path(filepath).read_text(encoding="utf-8")

    # Regex to find the YAML preamble block
    preamble_match = re.search(r"^---\s*\n(.*?)\n---\s*\n", content, re.DOTALL)
    if not preamble_match:
        print(f"Error: Could not find YAML preamble in {filepath}")
        return None

    preamble_text = preamble_match.group(1)
    lines = preamble_text.splitlines()
    new_lines = []

    status_updated = False
    verdict_updated = False
    priority_updated = False
    related_docs_updated = False

    for line in lines:
        if line.startswith("status:"):
            new_lines.append(f"status: {status_upper}")
            status_updated = True
        elif line.startswith("verdict:") and verdict_upper:
            new_lines.append(f"verdict: {verdict_upper}")
            verdict_updated = True
        elif line.startswith("priority:") and priority_upper:
            new_lines.append(f"priority: {priority_upper}")
            priority_updated = True
        elif line.startswith("related_docs:"):
            if related_docs_list is not None:
                new_lines.append(f"related_docs: {json.dumps(related_docs_list)}")
                related_docs_updated = True
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)

    if not status_updated:
        new_lines.append(f"status: {status_upper}")
    if verdict and not verdict_updated:
        new_lines.append(f"verdict: {verdict_upper}")
    if priority and not priority_updated:
        new_lines.append(f"priority: {priority_upper}")
    if related_docs_list is not None and not related_docs_updated:
        new_lines.append(f"related_docs: {json.dumps(related_docs_list)}")

    # Update 'updated' timestamp
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    for i, line in enumerate(new_lines):
        if line.startswith("updated:"):
            new_lines[i] = f"updated: {now}"
            break

    # Reconstruct the content
    new_preamble = "\n".join(new_lines)
    parts = content.split("---", 2)
    if len(parts) < 3:
        print("Error: Malformed document structure.")
        return None

    new_content = f"---\n{new_preamble}\n---\n" + parts[2].lstrip("\n")
    Path(filepath).write_text(new_content, encoding="utf-8")

    print(
        f"Updated {filepath}: status={status_upper}, verdict={verdict_upper if verdict else 'N/A'}, priority={priority_upper if priority else 'N/A'}"
    )
    return filepath


def show_preamble(filepath):
    """
    Extracts and displays the YAML preamble metadata from a documentation file.
    Uses regex-based parsing to avoid adding new dependencies.
    Returns a dict of key-value pairs, or None if no valid preamble is found.
    """
    if not os.path.exists(filepath):
        print(f"Error: File {filepath} not found.")
        return None

    content = Path(filepath).read_text(encoding="utf-8")

    # Regex to find the YAML preamble block between the first two --- delimiters
    preamble_match = re.search(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if not preamble_match:
        print("Error: No YAML preamble detected.")
        return None

    preamble_text = preamble_match.group(1)
    metadata = {}

    for line in preamble_text.splitlines():
        line = line.strip()
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        # Remove surrounding quotes if present
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        metadata[key] = value

    if not metadata:
        print("Error: No YAML preamble detected.")
        return None

    return metadata


def display_preamble(metadata):
    """
    Displays the metadata in a clean, human-readable key-value format.
    """
    if not metadata:
        return

    # Determine the longest key for alignment
    max_key_len = max(len(k) for k in metadata.keys()) if metadata else 0

    print("Document Metadata:")
    print("-" * (max_key_len + 3 + 20))
    for key, value in metadata.items():
        print(f"  {key:<{max_key_len}}: {value}")
    print("-" * (max_key_len + 3 + 20))


if __name__ == "__main__":
    # Usage:
    # python3 doc_utils.py CREATE [TYPE] "[Title]"
    # python3 doc_utils.py UPDATE <filepath> <status> [verdict] [priority] [related_docs]
    # python3 doc_utils.py SHOW <filepath>
    if len(sys.argv) >= 3:
        cmd = sys.argv[1].upper()
        if cmd == "CREATE":
            if len(sys.argv) >= 4:
                create_document(sys.argv[2].upper(), " ".join(sys.argv[3:]))
            else:
                print("Error: CREATE requires [TYPE] and [Title]")
        elif cmd == "UPDATE":
            if len(sys.argv) >= 4:
                path = sys.argv[2]
                stat = sys.argv[3]
                ver = sys.argv[4] if len(sys.argv) > 4 else None
                pri = sys.argv[5] if len(sys.argv) > 5 else None
                rel = sys.argv[6] if len(sys.argv) > 6 else None
                update_document(path, stat, ver, pri, rel)
            else:
                print("Error: UPDATE requires <filepath> and <status>")
        elif cmd == "SHOW":
            filepath = sys.argv[2]
            metadata = show_preamble(filepath)
            if metadata is not None:
                display_preamble(metadata)
        else:
            print(f"Unknown command '{cmd}'. Use CREATE, UPDATE, or SHOW.")
    else:
        print("Usage:")
        print('  python3 doc_utils.py CREATE [TYPE] "[Title]"')
        print(
            "  python3 doc_utils.py UPDATE <filepath> <status> [verdict] [priority] [related_docs]"
        )
        print("  python3 doc_utils.py SHOW <filepath>")
