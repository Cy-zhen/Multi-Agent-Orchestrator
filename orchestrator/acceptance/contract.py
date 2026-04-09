"""
Acceptance contract helpers.

The acceptance contract is the durable source of truth for what must be
verified after implementation, even when agent context is lost.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any
import json
import sys


REQUIRED_TOP_LEVEL_KEYS = [
    "feature_name",
    "revision",
    "owners",
    "scope",
    "critical_user_flows",
    "required_ui_states",
    "non_regression_guards",
    "evidence",
    "exit_criteria",
]


def load_contract(path: str | Path) -> dict[str, Any]:
    raw = Path(path).read_text(encoding="utf-8")
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("acceptance contract must be a JSON object")
    return data


def validate_contract(data: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    for key in REQUIRED_TOP_LEVEL_KEYS:
        if key not in data:
            errors.append(f"missing top-level key: {key}")

    if not isinstance(data.get("critical_user_flows"), list) or not data.get("critical_user_flows"):
        errors.append("critical_user_flows must be a non-empty array")

    if not isinstance(data.get("required_ui_states"), list) or not data.get("required_ui_states"):
        errors.append("required_ui_states must be a non-empty array")

    if not isinstance(data.get("non_regression_guards"), list) or not data.get("non_regression_guards"):
        errors.append("non_regression_guards must be a non-empty array")

    evidence = data.get("evidence")
    if not isinstance(evidence, dict):
        errors.append("evidence must be an object")
    else:
        required_evidence_keys = ["screenshots", "test_report", "role_outputs", "notes"]
        for key in required_evidence_keys:
            if key not in evidence:
                errors.append(f"evidence missing key: {key}")
        screenshots = evidence.get("screenshots")
        if not isinstance(screenshots, list) or not screenshots:
            errors.append("evidence.screenshots must be a non-empty array")
        role_outputs = evidence.get("role_outputs")
        if not isinstance(role_outputs, dict):
            errors.append("evidence.role_outputs must be an object")
        else:
            for key in ["fe_self_check", "be_self_check", "qa_report", "screenshot_manifest"]:
                if key not in role_outputs:
                    errors.append(f"evidence.role_outputs missing key: {key}")

    exit_criteria = data.get("exit_criteria")
    if not isinstance(exit_criteria, list) or not exit_criteria:
        errors.append("exit_criteria must be a non-empty array")

    return errors


def validate_contract_file(path: str | Path) -> list[str]:
    return validate_contract(load_contract(path))


def _main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: python3 contract.py <acceptance-contract.json>", file=sys.stderr)
        return 2

    path = Path(argv[1])
    if not path.exists():
        print(f"missing file: {path}", file=sys.stderr)
        return 1

    try:
        errors = validate_contract_file(path)
    except Exception as exc:
        print(f"invalid contract: {exc}", file=sys.stderr)
        return 1

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"acceptance contract valid: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv))
