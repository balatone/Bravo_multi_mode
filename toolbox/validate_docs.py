import os
import re
import json
import sys

# Distinct status lifecycles for different document types
DOC_STATUSES = {
    "DRAFT",
    "IN_REVIEW",
    "APPROVED",
    "SUPERSEDED",
    "DEPRECATED",
    "ARCHIVED",
}
TASK_STATUSES = {
    "TO-DO",
    "ANALYSING",
    "DESIGNING",
    "PLANNING",
    "IMPLEMENTING",
    "TESTING",
    "REVIEWING",
    "DONE",
}

REVIEW_VERDICTS = {"APPROVED", "REQUEST_CHANGES", "REJECTED"}
PRIORITY_VALUES = {"CRITICAL", "HIGH", "MEDIUM", "LOW", "TRIVIAL"}
ALLOWED_PRIORITY_TYPES = {"BUG", "REQ", "BUGFIX", "FEAT"}

# Mapping of prefixes to their allowed priority types (for validation)
PREFIX_TO_PRIORITY_TYPE = {
    "BUG": "BUG",
    "REQ": "REQ",
    "BUGFIX": "BUGFIX",
    "FEAT": "FEAT",
}

MANDATORY_FIELDS = {"id", "title", "version", "status", "created", "updated"}


def validate_file(filepath):
    errors = []
    try:
        with open(filepath, "r") as f:
            content = f.read()
    except Exception as e:
        return [f"Could not read file: {str(e)}"]

    # 1. Check for preamble existence
    preamble_match = re.search(r"^---\s*\n(.*?)\n---\s*\n", content, re.DOTALL)
    if not preamble_match:
        return [
            "Missing or malformed YAML preamble (must start with --- and end with ---)"
        ]

    preamble_text = preamble_match.group(1)
    lines = preamble_text.split("\n")

    # Parse lines into a dictionary for general metadata validation
    metadata = {}
    for line in lines:
        if ":" in line:
            key, val = line.split(":", 1)
            metadata[key.strip()] = val.strip()

    # 2. Check mandatory fields
    missing_fields = MANDATORY_FIELDS - set(metadata.keys())
    if missing_fields:
        errors.append(f"Missing mandatory fields: {', '.join(missing_fields)}")

    # 3. Validate field values (Status, Verdict, Priority)
    if "status" in metadata:
        # Determine context based on directory to enforce correct lifecycle
        is_task = ".board" in filepath
        allowed_statuses = TASK_STATUSES if is_task else DOC_STATUSES
        context_name = "task" if is_task else "document"

        if metadata["status"] not in allowed_statuses:
            errors.append(
                f"Invalid status '{metadata['status']}' for {context_name}. Must be one of {allowed_statuses}"
            )

    # 3b. Validate TASK ID format (must have exactly 4 digits)
    if is_task and "id" in metadata:
        task_id = str(metadata["id"])
        if task_id.startswith("TASK-") and not re.fullmatch(r"TASK-\d{4}", task_id):
            errors.append(
                f"Invalid task ID '{task_id}'. Must match TASK-XXXX with exactly 4 digits (e.g. TASK-0001)."
            )

    filename = os.path.basename(filepath)
    is_review_file = filename.startswith("REVIEW-") or filename == "REVIEW.md"
    is_review_template = is_review_file and filepath.endswith(
        os.path.join("07_templates", "REVIEW.md")
    )

    if "verdict" in metadata:
        # Review documents (and the REVIEW template) record the formal decision in the YAML preamble.
        if not is_review_file:
            errors.append("Verdict found in non-review document")
        else:
            verdict_value = metadata["verdict"]
            if verdict_value in REVIEW_VERDICTS:
                pass
            elif verdict_value.lower() in {"null", "none", "~", ""}:
                if not is_review_template and metadata.get("status") not in {
                    "DRAFT",
                    "IN_REVIEW",
                }:
                    errors.append(
                        "Review verdict may only be null while the document is DRAFT or IN_REVIEW"
                    )
            else:
                errors.append(
                    f"Invalid verdict '{metadata['verdict']}'. Must be one of {REVIEW_VERDICTS} or null while draft/in review"
                )
    elif is_review_file:
        errors.append("Missing verdict in review YAML preamble")

    if "priority" in metadata:
        filename = os.path.basename(filepath)
        found_type = None
        for prefix, p_type in PREFIX_TO_PRIORITY_TYPE.items():
            if filename.startswith(f"{prefix}-"):
                found_type = p_type
                break
        if not found_type:
            errors.append("Priority found in non-priority document type")
        elif metadata["priority"] not in PRIORITY_VALUES:
            errors.append(
                f"Invalid priority '{metadata['priority']}'. Must be one of {PRIORITY_VALUES}"
            )

    # 4. Related Docs Integrity & Format Enforcement
    rel_pattern = r"related_docs:\s*(\[.*?\])"
    rel_match = re.search(rel_pattern, preamble_text)

    if "related_docs" in metadata:
        if not rel_match:
            errors.append(
                'Error: related_docs must be a single-line bracketed list (e.g., ["ID-001"]).'
            )
        else:
            try:
                rel_docs = json.loads(rel_match.group(1))
                if not isinstance(rel_docs, list):
                    errors.append("related_docs must be a JSON list")
                else:
                    # Search in both internal-docs and .board
                    search_dirs = ["internal-docs", ".board"]
                    for doc_id in rel_docs:
                        found = False
                        for search_dir in search_dirs:
                            if not os.path.exists(search_dir):
                                continue
                            for root, _, files in os.walk(search_dir):
                                if any(
                                    (
                                        f.startswith(f"{doc_id}-")
                                        or f.startswith(f"{doc_id}_")
                                    )
                                    and f.endswith(".md")
                                    for f in files
                                ):
                                    found = True
                                    break
                            if found:
                                break
                        if not found:
                            errors.append(
                                f"Broken reference: related_docs contains non-existent ID '{doc_id}'"
                            )
            except Exception as e:
                errors.append(f"Malformed related_docs list: {str(e)}")

    return errors


def main():
    # Directories to validate
    target_dirs = ["internal-docs", ".board"]
    valid_dirs = []
    for d in target_dirs:
        if os.path.exists(d):
            valid_dirs.append(d)

    if not valid_dirs:
        print(f"Error: None of the target directories {target_dirs} found.")
        sys.exit(1)

    all_errors = {}
    found_files = False

    for target_dir in valid_dirs:
        for root, _, files in os.walk(target_dir):
            for file in files:
                if file.endswith(".md"):
                    found_files = True
                    filepath = os.path.join(root, file)
                    file_errors = validate_file(filepath)
                    if file_errors:
                        all_errors[filepath] = file_errors

    if not found_files:
        print("No documentation files found to validate.")
        sys.exit(0)

    if all_errors:
        print("\n❌ Documentation Validation Failed!\n")
        for path, errors in all_errors.items():
            print(f"File: {path}")
            for err in errors:
                print(f"  - {err}")
        print(f"\nTotal files with errors: {len(all_errors)}")
        sys.exit(1)
    else:
        print(
            "✅ All documentation preambles are well-formed and references are valid."
        )
        sys.exit(0)


if __name__ == "__main__":
    main()
