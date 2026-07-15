import json
import sys
import argparse
from pathlib import Path

# ──────────────────────────────────────────────────────────────
# Delegation Parameter Configuration (Based on delegate-protocol.md)
# ──────────────────────────────────────────────────────────────

EXTENSION_MAPPING = {
    "lead": ["summon", "todo", "extensionmanager", "analyze", "developer"],
    "worker": ["developer", "analyze"],
    "reviewer": ["developer", "analyze"],
    "analyst": ["fetch", "analyze", "developer", "extensionmanager"],
}

MAX_TURNS_CONFIG = {"low": 20, "medium": 40, "high": 60}


def load_env():
    """Loads ROLECAST environment variables from .env.rolecast."""
    env_path = Path(".env.rolecast")
    if not env_path.exists():
        raise RuntimeError("Error: .env.rolecast file not found.")

    env_vars = {}
    with open(env_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, value = line.split("=", 1)
                env_vars[key] = value

    provider = env_vars.get("ROLECAST_PROVIDER")
    if not provider:
        raise RuntimeError("Error: ROLECAST_PROVIDER not found in .env.rolecast.")

    return provider


def parse_specialist_id(specialist_id):
    """Parses 'role:<role>:<specialist>' into components."""
    parts = specialist_id.split(":")
    if len(parts) != 3 or parts[0] != "role":
        raise ValueError(
            "Invalid specialist ID format. Expected: role:<role>:<specialist>"
        )
    return {"role": parts[1], "specialist": parts[2]}


def get_delegation_params(specialist_id, complexity="medium"):
    """Returns the mandatory delegation parameters for a given specialist."""
    try:
        provider = load_env()
    except RuntimeError as e:
        return {"error": str(e)}

    parsed = parse_specialist_id(specialist_id)
    role = parsed["role"]

    if role not in EXTENSION_MAPPING:
        return {
            "error": f"Role '{role}' is not recognized. Available roles: {list(EXTENSION_MAPPING.keys())}"
        }

    max_turns = MAX_TURNS_CONFIG.get(complexity.lower(), 40)

    params = {
        "provider": provider,
        "model": specialist_id,
        "extensions": EXTENSION_MAPPING[role],
        "async": False,
        "max_turns": max_turns,
    }

    return params


def main():
    parser = argparse.ArgumentParser(
        description="Get mandatory delegation parameters for a specialist."
    )
    parser.add_argument(
        "--id", required=True, help="Specialist ID (e.g., role:worker:backend-engineer)"
    )
    parser.add_argument(
        "--complexity",
        default="medium",
        choices=["low", "medium", "high"],
        help="Task complexity to determine max_turns (default: medium)",
    )
    args = parser.parse_args()

    try:
        result = get_delegation_params(args.id, args.complexity)
        print(json.dumps(result, indent=2))
        if "error" in result:
            sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
