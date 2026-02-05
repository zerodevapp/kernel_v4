"""Shared utilities for Solidity code-quality tools.

Common helpers used across multiple checker scripts to avoid duplication.
"""
import re
from pathlib import Path
from typing import Iterable, List


def iter_sol_files(paths: Iterable[Path]) -> Iterable[Path]:
    """Yield .sol files from a mix of file and directory paths."""
    for path in paths:
        if path.is_file() and path.suffix == ".sol":
            yield path
        elif path.is_dir():
            yield from path.rglob("*.sol")


def strip_comments(lines: List[str]) -> str:
    """Strip single-line and multi-line comments while preserving line numbers.

    Each comment is replaced with spaces so that line offsets remain stable
    for downstream regex matching.
    """
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


def colorize(text: str, color: str) -> str:
    """Wrap text in ANSI color escape codes.

    Supported colors: red, green, yellow.
    Returns unchanged text for unsupported colors.
    """
    codes = {"red": "31", "green": "32", "yellow": "33"}
    code = codes.get(color)
    if not code:
        return text
    return f"\x1b[{code}m{text}\x1b[0m"
