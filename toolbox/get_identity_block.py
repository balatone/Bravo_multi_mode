import argparse
import sys


def generate_identity_block(model_id: str) -> str:
    """
    Generates the [IDENTITY INGESTION] block based on a model ID.
    Expected format: role:<archetype>:<specialist-id>
    """
    parts = model_id.split(":")
    if len(parts) != 3 or parts[0] != "role":
        print(
            f"Error: Invalid model ID format '{model_id}'. Expected 'role:<archetype>:<specialist-id>'",
            file=sys.stderr,
        )
        sys.exit(1)

    archetype = parts[1]
    specialist_id = parts[2]

    block1 = f"""[IDENTITY INGESTION]
Before performing any tasks, you MUST read and internalize your identity by reading both:
1. Your Archetype prompt: `prompts/{archetype}.md`
2. Your Specialist prompt: `prompts/{archetype}/{specialist_id}.md`

These files define your mission, strict constraints, and operational protocols. All subsequent actions and outputs must strictly adhere to these definitions.
   """

    block2 = """
## Standardized Instructions

### Document Management (Tool-First)
When creating documents: `uv run toolbox/doc_utils.py CREATE [TYPE] "[Title]"` — the tool handles IDs, filenames, directories, YAML preambles, and templates automatically. Do NOT write these manually.
When updating metadata: `uv run toolbox/doc_utils.py UPDATE <filepath> <status> "<verdict>" "" '[]'` (positional args; empty strings for unused fields).
To view metadata: `python3 toolbox/doc_utils.py SHOW <filepath>`.
Full reference: `prompts/snippets/doc-management.md`.

### Specialist Log Formatting
Refer to `prompts/snippets/specialist-log-formatting.md` for the exact log entry format, timestamp rules, and valid status labels.

### Board Logging
Refer to `prompts/snippets/board-logging.md` for the `board_utils.py log` command format, required fields, and timing rules.
"""
    if archetype == "worker":
        block2 = """
## Standardized Instructions

### Document Management (Tool-First)
If instructed to create a document: `uv run toolbox/doc_utils.py CREATE [TYPE] "[Title]"`. Do NOT write YAML preambles or filenames manually — the tool handles everything.
Full reference: `prompts/snippets/doc-management.md`.

### Specialist Log Formatting
Refer to `prompts/snippets/specialist-log-formatting.md` for the exact log entry format, timestamp rules, and valid status labels.

### Board Logging
Refer to `prompts/snippets/board-logging.md` for the `board_utils.py log` command format, required fields, and timing rules.
"""

    block = f"""
    {block1}

    {block2}
    """

    return block


def main():
    parser = argparse.ArgumentParser(
        description="Generate the [IDENTITY INGESTION] block for subagent delegation."
    )
    parser.add_argument(
        "--model",
        required=True,
        help="The model ID (e.g., role:analyst:technical-analyst)",
    )
    args = parser.parse_args()

    block = generate_identity_block(args.model)
    print(block)


if __name__ == "__main__":
    main()
