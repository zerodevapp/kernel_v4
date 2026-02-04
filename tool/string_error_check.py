#!/usr/bin/env python3
"""
String error checker for Solidity files.

Flags any usage of string literals in revert(...) or require(..., "...").
"""
import argparse
import re
from pathlib import Path
from typing import Iterable, List, Tuple

ROOT = Path(__file__).resolve().parents[1]

REVERT_STRING_RE = re.compile(
    r"\brevert\s*\(\s*(\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')\s*\)",
    re.DOTALL,
)
REQUIRE_STRING_RE = re.compile(
    r"\brequire\s*\(\s*[^,]+,\s*(\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')",
    re.DOTALL,
)


def iter_sol_files(paths: Iterable[Path]) -> Iterable[Path]:
    for path in paths:
        if path.is_file() and path.suffix == ".sol":
            yield path
        elif path.is_dir():
            yield from path.rglob("*.sol")


def strip_comments(lines: List[str]) -> str:
    out_lines: List[str] = []
    in_block = False
    for line in lines:
        i = 0
        res = ""
        while i < len(line):
            if in_block:
                end = line.find("*/", i)
                if end == -1:
                    res += " " * (len(line) - i)
                    i = len(line)
                else:
                    res += " " * (end + 2 - i)
                    i = end + 2
                    in_block = False
            else:
                start_block = line.find("/*", i)
                start_line = line.find("//", i)
                if start_line != -1 and (start_block == -1 or start_line < start_block):
                    res += line[i:start_line]
                    res += " " * (len(line) - start_line)
                    i = len(line)
                elif start_block != -1:
                    res += line[i:start_block]
                    res += "  "
                    i = start_block + 2
                    in_block = True
                else:
                    res += line[i:]
                    i = len(line)
        out_lines.append(res)
    return "\n".join(out_lines)


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
