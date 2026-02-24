#!/usr/bin/env python3
"""
Check if Solidity test functions in test/btt/*.t.sol have corresponding
branches in their .tree files.

NOTE: This functionality is now integrated into tool/btt_check.py (RULE 11).
      This standalone script is kept for quick individual checks.

This is the inverse of `bulloak check` - it finds test functions that exist
in the .t.sol file but don't correspond to any tree branch.

Usage:
    python tool/check_orphan_tests.py [--verbose] [--file FILE]
"""
import argparse
import sys
from pathlib import Path
from typing import Dict, List, Tuple

from btt_check import (
    BTT_DIR,
    ROOT,
    SKIP_TEST_NAMES,
    SKIP_TEST_PREFIXES,
    _fuzzy_name_match,
    _resolve_tree_file,
    get_expected_functions_from_bulloak,
    get_sol_test_functions,
)


def check_file(sol_path: Path, verbose: bool = False) -> List[Tuple[str, int]]:
    """Check a single .t.sol file for orphan tests."""
    tree_path = _resolve_tree_file(sol_path)
    if not tree_path:
        if verbose:
            print(f"Warning: No tree file found for {sol_path.name}")
        return []

    expected_functions = get_expected_functions_from_bulloak(tree_path)
    if not expected_functions:
        if verbose:
            print(f"Warning: Could not get expected functions for {tree_path.name}")
        return []

    return [
        (name, line)
        for name, line in get_sol_test_functions(sol_path)
        if name not in SKIP_TEST_NAMES
        and not any(name.startswith(p) for p in SKIP_TEST_PREFIXES)
        and not _fuzzy_name_match(name, expected_functions, check_prefix=True)
    ]


def check_orphan_tests(verbose: bool = False, specific_file: str | None = None) -> int:
    """Check for test functions without corresponding tree leaves. Returns 1 if orphans found."""
    orphans: Dict[Path, List[Tuple[str, int]]] = {}

    if specific_file:
        sol_path = Path(specific_file)
        if not sol_path.is_absolute():
            sol_path = ROOT / sol_path
        file_orphans = check_file(sol_path, verbose)
        if file_orphans:
            orphans[sol_path] = file_orphans
    else:
        for sol_path in sorted(BTT_DIR.glob("*.t.sol")):
            file_orphans = check_file(sol_path, verbose)
            if file_orphans:
                orphans[sol_path] = file_orphans

    if not orphans:
        print("No orphan tests found - all test functions have corresponding tree branches.")
        return 0

    total_orphans = sum(len(funcs) for funcs in orphans.values())
    print("ORPHAN TEST FUNCTIONS FOUND")
    print("=" * 60)
    print("These test functions don't have corresponding tree branches:")
    print()

    for sol_path, funcs in sorted(orphans.items()):
        rel_path = sol_path.relative_to(ROOT)
        print(f"{rel_path}:")
        for func_name, line_num in funcs:
            print(f"  Line {line_num}: {func_name}")
        print()

    print(f"Total: {total_orphans} orphan test(s) in {len(orphans)} file(s)")
    print()
    print("To fix: Either remove these functions or add corresponding branches to the .tree file")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check for test functions without corresponding tree branches"
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="show warnings")
    parser.add_argument("--file", "-f", type=str, help="check a specific .t.sol file")
    args = parser.parse_args()

    return check_orphan_tests(args.verbose, args.file)


if __name__ == "__main__":
    raise SystemExit(main())
