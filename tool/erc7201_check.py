#!/usr/bin/env python3
"""
ERC-7201 storage slot checker.

Scans Solidity files for NatSpec tags like:
  @custom:storage-location erc7201:<NAMESPACE_ID>

For each tag found, it computes the expected slot per ERC-7201 and compares it
to the next bytes32 constant value defined below the tag.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple

from sol_utils import colorize, iter_sol_files

ROOT = Path(__file__).resolve().parents[1]

TAG_RE = re.compile(r"@custom:storage-location\s+(.+)$")
BYTES32_CONST_RE = re.compile(r"\bbytes32\b[^=]*=\s*([^;]+);")
BYTES32_CONST_NAME_RE = re.compile(r"\bbytes32\b[^=]*\b([A-Za-z_][A-Za-z0-9_]*)\b\s*=")
HEX_RE = re.compile(r"0x[0-9a-fA-F]{1,64}")
RAW_FORMULA_RE = re.compile(
    r"^bytes32\s*\(\s*uint256\s*\(\s*keccak256\s*\(\s*'([^']+)'\s*\)\s*\)\s*-\s*1\s*\)\s*$"
)


def fail(msg: str, errors: List[str]) -> None:
    errors.append(msg)


def warn(msg: str, warnings: List[str]) -> None:
    warnings.append(msg)


def cast_keccak_hex(data_hex: str) -> str:
    try:
        out = subprocess.check_output(["cast", "keccak", data_hex], text=True).strip()
        return out
    except FileNotFoundError:
        raise RuntimeError("cast not found in PATH (install Foundry)")
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"cast keccak failed: {exc}")


def erc7201_slot(namespace_id: str) -> str:
    data_hex = "0x" + namespace_id.encode("utf-8").hex()
    h1 = cast_keccak_hex(data_hex)
    h1_int = int(h1, 16)
    h1_minus_1 = (h1_int - 1) % (1 << 256)
    h1_minus_1_hex = f"0x{h1_minus_1:064x}"
    h2 = cast_keccak_hex(h1_minus_1_hex)
    slot = int(h2, 16) & (~0xFF)
    return f"0x{slot:064x}"


def raw_formula_slot(expr: str) -> str | None:
    m = RAW_FORMULA_RE.match(expr.replace('"', "'"))
    if not m:
        return None
    namespace = m.group(1)
    data_hex = "0x" + namespace.encode("utf-8").hex()
    h1 = cast_keccak_hex(data_hex)
    h1_int = int(h1, 16)
    h1_minus_1 = (h1_int - 1) % (1 << 256)
    return f"0x{h1_minus_1:064x}"


def clean_tag_value(value: str) -> str:
    value = value.strip()
    value = re.sub(r"[*/]+$", "", value)
    return value


def parse_tag(line: str) -> Tuple[str, str] | None:
    m = TAG_RE.search(line)
    if not m:
        return None
    value = clean_tag_value(m.group(1))
    if value.startswith("bytes32("):
        return ("raw", value)
    if ":" not in value:
        return (value, "")
    formula_id, namespace_id = value.split(":", 1)
    return (formula_id, namespace_id)


def extract_hex_from_assignment(assignment: str) -> str | None:
    m = HEX_RE.search(assignment)
    if not m:
        return None
    value = m.group(0).lower()
    return f"0x{int(value, 16):064x}"


def find_next_bytes32_constant(lines: List[str], start_idx: int) -> Tuple[int, str, str] | None:
    for i in range(start_idx + 1, len(lines)):
        line = lines[i]
        if "@custom:storage-location" in line:
            break
        m = BYTES32_CONST_RE.search(line)
        if not m:
            continue
        name_match = BYTES32_CONST_NAME_RE.search(line)
        name = name_match.group(1) if name_match else "unknown"
        hex_value = extract_hex_from_assignment(m.group(1))
        if hex_value:
            return (i + 1, name, hex_value)
    return None


def check_file(
    path: Path,
    errors: List[str],
    warnings: List[str],
    found: List[str],
    records: List[Tuple[bool, str, int, str, str, str, str]],
    fixes: List[Tuple[Path, int, str]],
) -> None:
    lines = path.read_text().splitlines()
    matched_storage_consts: set[int] = set()
    for idx, line in enumerate(lines):
        parsed = parse_tag(line)
        if not parsed:
            continue
        formula_id, namespace_id = parsed
        try:
            if formula_id == "erc7201":
                if not namespace_id:
                    fail(
                        f"missing namespace id in {path.relative_to(ROOT)}:{idx + 1}",
                        errors,
                    )
                    continue
                expected = erc7201_slot(namespace_id)
                label = namespace_id
            elif formula_id == "raw":
                expected = raw_formula_slot(namespace_id)
                if expected is None:
                    fail(
                        f"unsupported raw formula in {path.relative_to(ROOT)}:{idx + 1}",
                        errors,
                    )
                    continue
                label = namespace_id
            else:
                warn(
                    f"unsupported formula '{formula_id}' in {path.relative_to(ROOT)}:{idx + 1}",
                    warnings,
                )
                continue
        except RuntimeError as exc:
            fail(
                f"{path.relative_to(ROOT)}:{idx + 1} {exc}",
                errors,
            )
            continue

        next_const = find_next_bytes32_constant(lines, idx)
        if not next_const:
            fail(
                f"no bytes32 constant below storage-location tag in {path.relative_to(ROOT)}:{idx + 1}",
                errors,
            )
            continue

        const_line, const_name, actual = next_const
        passed = expected == actual
        matched_storage_consts.add(const_line)
        if not passed:
            fixes.append((path, const_line, expected))
        records.append(
            (passed, str(path.relative_to(ROOT)), const_line, const_name, label, expected, actual)
        )
        if const_name not in found:
            found.append(const_name)
        if not passed:
            fail(
                f"erc7201 slot mismatch in {path.relative_to(ROOT)}:{const_line} "
                f"(expected {expected}, found {actual})",
                errors,
            )

    for idx, line in enumerate(lines):
        name_match = BYTES32_CONST_NAME_RE.search(line)
        if not name_match:
            continue
        name = name_match.group(1)
        if not (name.endswith("_STORAGE_SLOT") or name.endswith("_SLOT")):
            continue
        line_no = idx + 1
        if line_no in matched_storage_consts:
            continue
        records.append(
            (
                False,
                str(path.relative_to(ROOT)),
                line_no,
                name,
                "<missing @custom:storage-location>",
                "-",
                "-",
            )
        )
        fail(
            f"missing @custom:storage-location tag for {name} in {path.relative_to(ROOT)}:{line_no}",
            errors,
        )


def apply_fixes(fixes: List[Tuple[Path, int, str]], errors: List[str]) -> None:
    if not fixes:
        return
    by_file: Dict[Path, List[Tuple[int, str]]] = {}
    for path, line_no, expected in fixes:
        by_file.setdefault(path, []).append((line_no, expected))

    for path, items in by_file.items():
        lines = path.read_text().splitlines()
        for line_no, expected in items:
            idx = line_no - 1
            if idx < 0 or idx >= len(lines):
                errors.append(f"cannot fix {path.relative_to(ROOT)}:{line_no} (line out of range)")
                continue
            line = lines[idx]
            if not HEX_RE.search(line):
                errors.append(f"cannot fix {path.relative_to(ROOT)}:{line_no} (no hex literal)")
                continue
            lines[idx] = HEX_RE.sub(expected, line, count=1)
        path.write_text("\n".join(lines) + "\n")


def run_checks(paths: List[Path]) -> Tuple[List[str], List[str], List[str], List[Tuple[bool, str, int, str, str, str, str]], List[Tuple[Path, int, str]]]:
    errors: List[str] = []
    warnings: List[str] = []
    found: List[str] = []
    records: List[Tuple[bool, str, int, str, str, str, str]] = []
    fixes: List[Tuple[Path, int, str]] = []
    for path in iter_sol_files(paths):
        check_file(path, errors, warnings, found, records, fixes)
    return errors, warnings, found, records, fixes


def main() -> int:
    parser = argparse.ArgumentParser(description="ERC-7201 storage slot checker")
    parser.add_argument(
        "paths",
        nargs="*",
        default=[str(ROOT / "src")],
        help="paths to scan (default: src)",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="show warnings")
    parser.add_argument("--fix", action="store_true", help="fix mismatched slot constants")
    args = parser.parse_args()

    paths = [Path(p) for p in args.paths]
    errors, warnings, found, records, fixes = run_checks(paths)
    if args.fix and fixes:
        apply_fixes(fixes, errors)
        errors, warnings, found, records, _ = run_checks(paths)

    if args.verbose and found:
        print("FOUND CONSTANTS:")
        for item in found:
            print(f"- {item}")
        print()

    if args.verbose and records:
        print("RESULTS:")
        for passed, file_path, line, name, label, expected, actual in records:
            status = "PASS" if passed else "FAIL"
            colored_status = colorize(status, "green" if passed else "red")
            print(f"{colored_status}:{file_path}#{line} {name}")
            print(f"  {label}")
            print(f"    expected : {expected}")
            print(f"    actual   : {actual}")
        print()

    if args.verbose and warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  - {w}")
        print()

    if errors:
        if not args.verbose:
            for passed, file_path, line, name, label, expected, actual in records:
                if passed:
                    continue
                status = "FAIL"
                colored_status = colorize(status, "red")
                print(f"{colored_status}:{file_path}#{line} {name}")
                print(f"  {label}")
                print(f"    expected : {expected}")
                print(f"    actual   : {actual}")
        return 1

    print("ERC7201 CHECK PASSED")
    if warnings and not args.verbose:
        print(f"({len(warnings)} warnings - use -v to see)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
