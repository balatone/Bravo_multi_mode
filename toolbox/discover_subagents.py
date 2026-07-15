import json
import sys
import argparse
import requests
from pathlib import Path


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

    host = env_vars.get("ROLECAST_HOST")
    port = env_vars.get("ROLECAST_PORT")

    if not host or not port:
        raise RuntimeError(
            "Error: ROLECAST_HOST or ROLECAST_PORT not found in .env.rolecast."
        )

    return f"http://{host}:{port}"


def discover(base_url, role=None, model_id=None):
    """Performs the discovery logic."""
    # 1. Verify Role exists via /v1/models
    try:
        models_resp = requests.get(f"{base_url}/v1/models", timeout=5)
        models_resp.raise_for_status()
        models_data = models_resp.json()
    except Exception as e:
        return {"error": f"Failed to connect to Role Discovery API: {str(e)}"}

    # Check if the requested role is in the system (using 'owned_by')
    available_roles = [entry.get("owned_by") for entry in models_data.get("data", [])]

    if role and role not in available_roles:
        return {"error": f"Role '{role}' is not a recognized system role."}

    # 2. If role provided, fetch specialists for that role
    if role:
        try:
            spec_resp = requests.get(f"{base_url}/{role}/specialists", timeout=5)
            spec_resp.raise_for_status()
            specialists = spec_resp.json()
        except Exception as e:
            return {
                "error": f"Failed to connect to Specialist API for role '{role}': {str(e)}"
            }

        # If model_id is also provided, validate it
        if model_id:
            exists = any(s["id"] == model_id for s in specialists)
            if not exists:
                return {"error": f"Model ID '{model_id}' is invalid for role '{role}'."}

            # Find the description for the validated model
            desc = next(
                (s["description"] for s in specialists if s["id"] == model_id),
                "No description available.",
            )
            return {
                "status": "VALIDATED",
                "role": role,
                "model_id": model_id,
                "description": desc,
            }

        # Otherwise return all specialists for the role
        return {"status": "SUCCESS", "role": role, "specialists": specialists}

    return {"error": "Please provide a --role to discover subagents."}


def main():
    parser = argparse.ArgumentParser(
        description="Discover available subagents via Rolecast API."
    )
    parser.add_argument(
        "--role", help="The target role (e.g., worker, analyst, reviewer)"
    )
    parser.add_argument("--model", help="The specific model ID to validate")
    args = parser.parse_args()

    try:
        base_url = load_env()
        result = discover(base_url, args.role, args.model)
        print(json.dumps(result, indent=2))
        if "error" in result:
            sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
