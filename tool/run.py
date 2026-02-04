#!/usr/bin/env python3
"""Run all code-quality tools in sequence.

Usage:
    python3 tool/run.py           # run all checks
    python3 tool/run.py --strict  # treat warnings as errors (CI mode)
    python3 tool/run.py --fix     # run fixable tools in fix mode
"""
import argparse
import subprocess
import sys
import time
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent


def build_commands(strict: bool = False, fix: bool = False) -> list[tuple[str, list[str]]]:
    """Return (label, argv) pairs for each tool invocation."""
    py = [sys.executable]
    cmds: list[tuple[str, list[str]]] = []

    # BTT check
    cmds.append(("btt_check", [*py, str(TOOL_DIR / "btt_check.py")]))

    # ERC-7201 storage slot check
    argv = [*py, str(TOOL_DIR / "erc7201_check.py")]
    if fix:
        argv.append("--fix")
    cmds.append(("erc7201_check", argv))

    # EIP-712 struct hash check
    argv = [*py, str(TOOL_DIR / "struct_hash_check.py")]
    if strict:
        argv.append("--strict")
    if fix:
        argv.append("--fix")
    cmds.append(("struct_hash_check", argv))

    # Definition location check (errors, events, constants)
    argv = [*py, str(TOOL_DIR / "definition_location_check.py"), "--skip-interfaces"]
    if fix:
        argv.append("--fix")
    cmds.append(("definition_location_check", argv))

    # String error check
    cmds.append(("string_error_check", [*py, str(TOOL_DIR / "string_error_check.py")]))

    # Console log check
    cmds.append(("console_log_check", [*py, str(TOOL_DIR / "console_log_check.py")]))

    # TODO/FIXME check
    argv = [*py, str(TOOL_DIR / "todo_check.py")]
    if not strict:
        argv.append("--warn-only")
    cmds.append(("todo_check", argv))

    # Dependency integrity check
    argv = [*py, str(TOOL_DIR / "dependency_check.py")]
    if strict:
        argv.append("--strict")
    cmds.append(("dependency_check", argv))

    # Release configuration check
    argv = [*py, str(TOOL_DIR / "release_check.py"), "--verify-bytecode"]
    if strict:
        argv.append("--strict")
    cmds.append(("release_check", argv))

    return cmds


def main() -> int:
    parser = argparse.ArgumentParser(description="Run all code-quality tools")
    parser.add_argument("--strict", action="store_true", help="Treat warnings as errors (CI mode)")
    parser.add_argument("--fix", action="store_true", help="Run fixable tools in fix mode")
    args = parser.parse_args()

    commands = build_commands(strict=args.strict, fix=args.fix)
    failed: list[str] = []
    total_start = time.time()

    for label, argv in commands:
        print(f"\n{'=' * 60}")
        print(f"  {label}")
        print(f"{'=' * 60}")
        start = time.time()
        result = subprocess.run(argv)
        elapsed = time.time() - start

        if result.returncode != 0:
            failed.append(label)
            print(f"  FAIL  ({elapsed:.1f}s)")
        else:
            print(f"  OK  ({elapsed:.1f}s)")

    total_elapsed = time.time() - total_start
    print(f"\n{'=' * 60}")
    if failed:
        print(f"  {len(failed)}/{len(commands)} checks failed ({total_elapsed:.1f}s):")
        for name in failed:
            print(f"    - {name}")
    else:
        print(f"  All {len(commands)} checks passed ({total_elapsed:.1f}s)")
    print(f"{'=' * 60}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
