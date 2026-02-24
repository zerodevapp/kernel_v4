#!/usr/bin/env python3
"""
Link reference checker for Kernel v4.

Ensures production contracts have no unresolved library link references
(__$hash$__ placeholders) in their compiled bytecode. Link references mean the
contract depends on a separately deployed library (DELEGATECALL), which
increases deployment complexity and gas costs. All library functions should be
internal so they get inlined.

Usage:
    python3 tool/link_reference_check.py
    python3 tool/link_reference_check.py --verbose
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "src"
OUT_DIR = ROOT / "out"

LINK_REF_RE = re.compile(r"__\$[a-fA-F0-9]+\$__")


def check_link_references(verbose: bool = False) -> list[str]:
    """Check all src/ contracts for library link references in compiled bytecode."""
    errors: list[str] = []

    for sol_file in sorted(SRC_DIR.rglob("*.sol")):
        if sol_file.name.startswith("I"):
            continue
        contract_name = sol_file.stem
        json_path = OUT_DIR / f"{contract_name}.sol" / f"{contract_name}.json"
        if not json_path.exists():
            continue

        try:
            with open(json_path) as f:
                artifact = json.load(f)
        except (json.JSONDecodeError, KeyError):
            continue

        bytecode = artifact.get("bytecode", {}).get("object", "")
        if not bytecode or bytecode == "0x":
            continue

        refs = LINK_REF_RE.findall(bytecode)
        if refs:
            unique_refs = sorted(set(refs))
            errors.append(f"- {contract_name}: {len(unique_refs)} link reference(s): {', '.join(unique_refs)}")
        elif verbose:
            print(f"  ok: {contract_name}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Check for library link references in contract bytecode")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show all checked contracts")
    args = parser.parse_args()

    errors = check_link_references(verbose=args.verbose)

    if errors:
        print("LINK REFERENCE CHECK FAILED")
        for err in errors:
            print(err)
        return 1

    print("LINK REFERENCE CHECK PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
