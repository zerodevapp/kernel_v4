#!/usr/bin/env python3
"""
TODO/FIXME checker for Solidity production code.

Flags TODO, FIXME, XXX, and HACK comments in src/ that should be
resolved before deployment.
"""
import argparse
import re
from pathlib import Path
from typing import Iterable, List, Tuple

ROOT = Path(__file__).resolve().parents[1]

TODO_RE = re.compile(r"\b(TODO|FIXME|XXX|HACK)\b\s*:?\s*(.*)", re.IGNORECASE)


def iter_sol_files(paths: Iterable[Path]) -> Iterable[Path]:
    for path in paths:
        if path.is_file() and path.suffix == ".sol":
            yield path
        elif path.is_dir():
            yield from path.rglob("*.sol")


def find_todos(text: str) -> List[Tuple[int, str, str]]:
    """Find TODO/FIXME comments and return (line_number, type, message)."""
    matches: List[Tuple[int, str, str]] = []
    lines = text.splitlines()
    for idx, line in enumerate(lines):
        m = TODO_RE.search(line)
        if m:
            todo_type = m.group(1).upper()
            message = m.group(2).strip()[:60]  # Truncate long messages
            if message:
                message = f": {message}"
            matches.append((idx + 1, todo_type, message))
    return matches


def main() -> int:
    parser = argparse.ArgumentParser(description="TODO/FIXME checker for Solidity")
    parser.add_argument(
        "paths",
        nargs="*",
        default=[str(ROOT / "src")],
        help="paths to scan (default: src)",
    )
    parser.add_argument(
        "--warn-only",
        action="store_true",
        help="exit 0 even if TODOs found (just report)",
    )
    parser.add_argument(
        "--include-fixme-only",
        action="store_true",
        help="only flag FIXME (not TODO)",
    )
    args = parser.parse_args()

    findings: List[Tuple[Path, int, str, str]] = []

    for path in iter_sol_files([Path(p) for p in args.paths]):
        text = path.read_text()
        for line_no, todo_type, message in find_todos(text):
            if args.include_fixme_only and todo_type not in ("FIXME", "XXX", "HACK"):
                continue
            findings.append((path, line_no, todo_type, message))

    if findings:
        print("TODO/FIXME CHECK: Found unresolved items")
        print("=" * 60)
        for path, line_no, todo_type, message in findings:
            print(f"- {path.relative_to(ROOT)}:{line_no} {todo_type}{message}")
        print()
        print(f"Total: {len(findings)} item(s) found")

        if args.warn_only:
            return 0
        return 1

    print("TODO CHECK PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
