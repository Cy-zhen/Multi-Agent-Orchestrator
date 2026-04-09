"""
Consistency checks across acceptance artifacts.

This guards against a common failure mode: the acceptance contract exists,
but the test report or screenshot manifest still reflects an older revision.
"""

from __future__ import annotations

from pathlib import Path
import json
import re
import sys

try:
    from .contract import load_contract
except ImportError:  # pragma: no cover - package-relative import unavailable
    try:
        from acceptance.contract import load_contract
    except ModuleNotFoundError:  # pragma: no cover - direct script execution fallback
        from contract import load_contract


def _load_json(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} must be a JSON object")
    return data


def check_consistency(project_dir: str | Path) -> list[str]:
    root = Path(project_dir)
    doc_dir = root / "doc"
    contract_path = doc_dir / "acceptance-contract.json"
    manifest_path = doc_dir / "acceptance-screenshots" / "manifest.json"
    fe_self_check_path = doc_dir / "fe-self-check.md"
    be_self_check_path = doc_dir / "be-self-check.md"
    test_report_path = doc_dir / "test-report.md"

    errors: list[str] = []

    if not contract_path.exists():
        return ["missing doc/acceptance-contract.json"]

    contract = load_contract(contract_path)
    contract_revision = contract.get("revision")

    if not isinstance(contract_revision, int):
        errors.append("contract revision must be an integer")
        return errors

    if manifest_path.exists():
        manifest = _load_json(manifest_path)
        manifest_revision = manifest.get("revision")
        if manifest_revision != contract_revision:
            errors.append(
                f"manifest revision {manifest_revision} does not match contract revision {contract_revision}"
            )
    else:
        errors.append("missing doc/acceptance-screenshots/manifest.json")

    for name, path in [
        ("FE self-check", fe_self_check_path),
        ("BE self-check", be_self_check_path),
    ]:
        if not path.exists():
            errors.append(f"missing {path}")
            continue
        content = path.read_text(encoding="utf-8")
        match = re.search(r"Contract Revision:\s*(\d+)", content)
        if not match:
            errors.append(f"{path.name} missing 'Contract Revision: N' line")
            continue
        report_revision = int(match.group(1))
        if report_revision != contract_revision:
            errors.append(
                f"{name} revision {report_revision} does not match contract revision {contract_revision}"
            )

    if test_report_path.exists():
        content = test_report_path.read_text(encoding="utf-8")
        match = re.search(r"Contract Revision:\s*(\d+)", content)
        if not match:
            errors.append("doc/test-report.md missing 'Contract Revision: N' line")
        else:
            report_revision = int(match.group(1))
            if report_revision != contract_revision:
                errors.append(
                    f"test report revision {report_revision} does not match contract revision {contract_revision}"
                )
    else:
        errors.append("missing doc/test-report.md")

    return errors


def _main(argv: list[str]) -> int:
    project_dir = Path(argv[1]) if len(argv) > 1 else Path(".")
    errors = check_consistency(project_dir)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"acceptance artifacts consistent: {project_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv))
