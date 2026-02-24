#!/usr/bin/env python3
"""
Console.log checker for Solidity files.

Flags any usage of console.log, console2.log, or similar debug statements
that should not be in production code.
"""
import argparse
import re
from pathlib import Path
from typing import List, Tuple

from sol_utils import iter_sol_files, strip_comments

ROOT = Path(__file__).resolve().parents[1]

# Patterns for console.log variants
CONSOLE_PATTERNS = [
    (re.compile(r"\bconsole\.log\w*\s*\(", re.IGNORECASE), "console.log"),
    (re.compile(r"\bconsole2\.log\w*\s*\(", re.IGNORECASE), "console2.log"),
    (re.compile(r"\bconsole\.debug\w*\s*\(", re.IGNORECASE), "console.debug"),
    (re.compile(r"\bemit\s+log\s*\(", re.IGNORECASE), "emit log"),
    (re.compile(r'\bemit\s+log_named_\w+\s*\(', re.IGNORECASE), "emit log_named_*"),
]

# Import patterns to detect
CONSOLE_IMPORT_RE = re.compile(
    r'^\s*import\s+[^;]*["\'](?:forge-std/)?(?:console2?|Test)\.sol["\']',
    re.MULTILINE,
)


def find_console_logs(text: str) -> List[Tuple[int, str]]:
    """Find all console.log usages and return (line_number, type)."""
    matches: List[Tuple[int, str]] = []
    for pattern, name in CONSOLE_PATTERNS:
        for m in pattern.finditer(text):
            line_no = text.count("\n", 0, m.start()) + 1
            matches.append((line_no, name))
    return sorted(set(matches))


def main() -> int:
    parser = argparse.ArgumentParser(description="Console.log checker for Solidity")
    parser.add_argument(
        "paths",
        nargs="*",
        default=[str(ROOT / "src")],
        help="paths to scan (default: src)",
    )
    parser.add_argument(
        "--check-imports",
        action="store_true",
        help="also flag console/Test imports",
    )
    args = parser.parse_args()

    errors: List[str] = []
    warnings: List[str] = []

    for path in iter_sol_files([Path(p) for p in args.paths]):
        raw = path.read_text()
        stripped = strip_comments(raw.splitlines())

        # Check for console.log calls
        for line_no, kind in find_console_logs(stripped):
            errors.append(f"{path.relative_to(ROOT)}:{line_no} {kind}")

        # Optionally check for imports
        if args.check_imports:
            for m in CONSOLE_IMPORT_RE.finditer(raw):
                line_no = raw.count("\n", 0, m.start()) + 1
                warnings.append(f"{path.relative_to(ROOT)}:{line_no} console import")

    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  - {w}")
        print()

    if errors:
        print("CONSOLE LOG CHECK FAILED")
        print("Found debug statements that should be removed:")
        for e in errors:
            print(f"- {e}")
        return 1

    print("CONSOLE LOG CHECK PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
