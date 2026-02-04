#!/usr/bin/env python3
"""
EIP-712 struct hash checker for Solidity files.

Validates struct type hashes by:
1. Finding @custom:struct-hash NatSpec tags or type string comments
2. Parsing the EIP-712 type string
3. Computing keccak256(typeString)
4. Comparing with the bytes32 constant value

Also flags any _STRUCT_HASH or _TYPEHASH constants without proper documentation.

Supported comment formats:
  /// @custom:struct-hash StructName(type1 name1,type2 name2)
  /// @dev `keccak256("StructName(type1 name1,type2 name2)")`.
  //keccak256("StructName(type1 name1,type2 name2)")
  //StructName(type1 name1,type2 name2)
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable, List, Tuple, Dict

ROOT = Path(__file__).resolve().parents[1]

# Pattern to match @custom:struct-hash tag
CUSTOM_TAG_RE = re.compile(
    r"@custom:struct-hash\s+(.+?)(?:\s*\*/|\s*$)",
    re.MULTILINE
)

# Pattern to match @custom:storage-location (to exclude from struct hash checks)
STORAGE_LOCATION_RE = re.compile(r"@custom:storage-location")

# Pattern to match keccak256("TypeString") in comments - must be a struct type string
# Struct type strings look like: StructName(type1 name1,type2 name2)
KECCAK_COMMENT_RE = re.compile(
    r'keccak256\s*\(\s*["\']([A-Z][A-Za-z0-9]*\([^"\']+\))["\']\s*\)',
)

# Pattern to match bare type string comment like //StructName(type1 name1,...)
# Must start with capital letter (struct name) and have parentheses with typed fields
BARE_TYPE_RE = re.compile(
    r"^//\s*([A-Z][A-Za-z0-9]*\([^)]+\)(?:[A-Z][A-Za-z0-9]*\([^)]+\))*)\s*$",
    re.MULTILINE
)

# Pattern to match bytes32 constant declarations (may span multiple lines)
BYTES32_CONST_RE = re.compile(
    r"\bbytes32\s+(?:internal\s+|private\s+|public\s+)?(?:constant\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+);",
    re.DOTALL,
)

# Pattern to identify struct hash constants by name (contains these patterns)
STRUCT_HASH_NAME_RE = re.compile(
    r"(STRUCT_HASH|TYPEHASH)",
    re.IGNORECASE
)

# Pattern to extract hex value
HEX_RE = re.compile(r"0x[0-9a-fA-F]{1,64}")


def cast_keccak(data: str) -> str:
    """Compute keccak256 hash using cast."""
    try:
        # Convert string to hex
        data_hex = "0x" + data.encode("utf-8").hex()
        out = subprocess.check_output(
            ["cast", "keccak", data_hex],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return out.lower()
    except FileNotFoundError:
        raise RuntimeError("cast not found in PATH (install Foundry)")
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"cast keccak failed: {exc}")


def normalize_type_string(type_str: str) -> str:
    """Normalize a type string by removing extra whitespace."""
    # Remove newlines and extra spaces
    type_str = re.sub(r"\s+", " ", type_str.strip())
    # Remove spaces after ( and before )
    type_str = re.sub(r"\(\s+", "(", type_str)
    type_str = re.sub(r"\s+\)", ")", type_str)
    # Remove spaces around commas
    type_str = re.sub(r"\s*,\s*", ",", type_str)
    return type_str


def extract_hex_value(assignment: str) -> str | None:
    """Extract hex value from a constant assignment."""
    m = HEX_RE.search(assignment)
    if not m:
        return None
    value = m.group(0).lower()
    # Pad to 64 hex chars
    return f"0x{int(value, 16):064x}"


def iter_sol_files(paths: Iterable[Path]) -> Iterable[Path]:
    for path in paths:
        if path.is_file() and path.suffix == ".sol":
            yield path
        elif path.is_dir():
            yield from path.rglob("*.sol")


def find_type_string_before_line(lines: List[str], const_line_idx: int) -> Tuple[str | None, int | None]:
    """
    Search backwards from a constant declaration to find a type string comment.
    Returns (type_string, comment_line_number) or (None, None).
    """
    # Search up to 5 lines back
    for i in range(const_line_idx - 1, max(const_line_idx - 6, -1), -1):
        if i < 0:
            break
        line = lines[i]

        # Skip if this is a storage-location tag (handled by erc7201_check.py)
        if STORAGE_LOCATION_RE.search(line):
            return None, None

        # Check for @custom:struct-hash
        m = CUSTOM_TAG_RE.search(line)
        if m:
            return normalize_type_string(m.group(1)), i + 1

        # Check for keccak256("...") comment with struct type string
        m = KECCAK_COMMENT_RE.search(line)
        if m:
            return normalize_type_string(m.group(1)), i + 1

        # Check for bare type string comment
        m = BARE_TYPE_RE.match(line)
        if m:
            return normalize_type_string(m.group(1)), i + 1

        # Check for @dev `keccak256("...")` pattern with struct type string
        if "@dev" in line and "keccak256" in line:
            m = KECCAK_COMMENT_RE.search(line)
            if m:
                return normalize_type_string(m.group(1)), i + 1

        # Stop if we hit another constant or function
        if re.search(r"\b(bytes32|function|contract|struct)\b", line):
            break

    return None, None


def check_file(
    path: Path,
    errors: List[str],
    warnings: List[str],
    records: List[Tuple[bool, str, int, str, str, str, str]],
    fixes: List[Tuple[Path, int, str]],
) -> None:
    """Check a single file for struct hash issues."""
    text = path.read_text()
    lines = text.splitlines()

    # Track which constants have been validated
    validated_consts: set[int] = set()

    # Find all bytes32 constants that look like struct hashes
    for m in BYTES32_CONST_RE.finditer(text):
        const_name = m.group(1)
        const_value = m.group(2)
        const_line_idx = text[:m.start()].count("\n")
        const_line = const_line_idx + 1

        # Check if this looks like a struct hash constant
        is_struct_hash_name = STRUCT_HASH_NAME_RE.search(const_name) is not None

        # Try to find a type string comment above
        type_string, comment_line = find_type_string_before_line(lines, const_line_idx)

        if type_string:
            validated_consts.add(const_line)

            # Compute expected hash
            try:
                expected_hash = cast_keccak(type_string)
            except RuntimeError as e:
                errors.append(f"{path.relative_to(ROOT)}:{const_line} {e}")
                continue

            # Extract actual hash
            actual_hash = extract_hex_value(const_value)
            if not actual_hash:
                errors.append(
                    f"{path.relative_to(ROOT)}:{const_line} "
                    f"could not parse hex value for {const_name}"
                )
                continue

            passed = expected_hash == actual_hash
            records.append((
                passed,
                str(path.relative_to(ROOT)),
                const_line,
                const_name,
                type_string,
                expected_hash,
                actual_hash,
            ))

            if not passed:
                fixes.append((path, const_line, expected_hash))
                errors.append(
                    f"{path.relative_to(ROOT)}:{const_line} "
                    f"struct hash mismatch for {const_name}\n"
                    f"  type: {type_string}\n"
                    f"  expected: {expected_hash}\n"
                    f"  actual:   {actual_hash}"
                )

        elif is_struct_hash_name:
            # This is a struct hash constant without documentation
            records.append((
                False,
                str(path.relative_to(ROOT)),
                const_line,
                const_name,
                "<missing type string comment>",
                "-",
                extract_hex_value(const_value) or "-",
            ))
            warnings.append(
                f"{path.relative_to(ROOT)}:{const_line} "
                f"{const_name} missing type string comment "
                f"(use @custom:struct-hash or //TypeString(...))"
            )


def apply_fixes(fixes: List[Tuple[Path, int, str]], errors: List[str]) -> None:
    """Apply fixes to mismatched struct hashes."""
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


def main() -> int:
    parser = argparse.ArgumentParser(description="EIP-712 struct hash checker")
    parser.add_argument(
        "paths",
        nargs="*",
        default=[str(ROOT / "src")],
        help="paths to scan (default: src)",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="show detailed output")
    parser.add_argument("--fix", action="store_true", help="fix mismatched hash constants")
    parser.add_argument("--strict", action="store_true", help="treat warnings as errors")
    args = parser.parse_args()

    errors: List[str] = []
    warnings: List[str] = []
    records: List[Tuple[bool, str, int, str, str, str, str]] = []
    fixes: List[Tuple[Path, int, str]] = []

    for path in iter_sol_files([Path(p) for p in args.paths]):
        check_file(path, errors, warnings, records, fixes)

    # Apply fixes if requested
    if args.fix and fixes:
        apply_fixes(fixes, errors)
        # Re-check after fixes
        errors.clear()
        warnings.clear()
        records.clear()
        for path in iter_sol_files([Path(p) for p in args.paths]):
            check_file(path, errors, warnings, records, [])

    # Colorize output
    def colorize(text: str, color: str) -> str:
        codes = {"red": "31", "green": "32", "yellow": "33"}
        code = codes.get(color)
        if not code:
            return text
        return f"\x1b[{code}m{text}\x1b[0m"

    # Show results
    if args.verbose and records:
        print("STRUCT HASH VERIFICATION:")
        for passed, file_path, line, name, type_str, expected, actual in records:
            status = "PASS" if passed else "FAIL"
            color = "green" if passed else "red"
            print(f"{colorize(status, color)}:{file_path}#{line} {name}")
            print(f"  type: {type_str}")
            if expected != "-":
                print(f"    expected: {expected}")
                print(f"    actual:   {actual}")
        print()

    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  - {w}")
        print()

    if args.strict:
        errors.extend(warnings)

    if errors:
        if not args.verbose:
            # Show failed records
            for passed, file_path, line, name, type_str, expected, actual in records:
                if passed:
                    continue
                print(f"{colorize('FAIL', 'red')}:{file_path}#{line} {name}")
                print(f"  type: {type_str}")
                if expected != "-":
                    print(f"    expected: {expected}")
                    print(f"    actual:   {actual}")
        print("STRUCT HASH CHECK FAILED")
        return 1

    print("STRUCT HASH CHECK PASSED")
    if warnings and not args.verbose:
        print(f"({len(warnings)} warnings - use -v to see)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
