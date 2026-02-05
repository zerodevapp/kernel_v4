#!/usr/bin/env python3
"""
String error checker for Solidity files.

Flags any usage of string literals in revert(...) or require(..., "...").
"""
import argparse
import re
from pathlib import Path
from typing import List, Tuple

from sol_utils import iter_sol_files, strip_comments

ROOT = Path(__file__).resolve().parents[1]

REVERT_STRING_RE = re.compile(
    r"\brevert\s*\(\s*(\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')\s*\)",
    re.DOTALL,
)
REQUIRE_STRING_RE = re.compile(
    r"\brequire\s*\(\s*[^,]+,\s*(\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')",
    re.DOTALL,
)


def find_matches(text: str) -> List[Tuple[int, str]]:
    matches: List[Tuple[int, str]] = []
    for m in REVERT_STRING_RE.finditer(text):
        line_no = text.count("\n", 0, m.start()) + 1
        matches.append((line_no, "revert(string)"))
    for m in REQUIRE_STRING_RE.finditer(text):
        line_no = text.count("\n", 0, m.start()) + 1
        matches.append((line_no, "require(string)"))
    return matches


def main() -> int:
    parser = argparse.ArgumentParser(description="String error checker for Solidity")
    parser.add_argument(
        "paths",
        nargs="*",
        default=[str(ROOT / "src")],
        help="paths to scan (default: src)",
    )
    args = parser.parse_args()

    errors: List[str] = []

    for path in iter_sol_files([Path(p) for p in args.paths]):
        raw = path.read_text()
        stripped = strip_comments(raw.splitlines())
        for line_no, kind in find_matches(stripped):
            errors.append(f"{path.relative_to(ROOT)}:{line_no} {kind}")

    if errors:
        print("STRING ERROR CHECK FAILED")
        for e in errors:
            print(f"- {e}")
        return 1

    print("STRING ERROR CHECK PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
