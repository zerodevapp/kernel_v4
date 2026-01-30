#!/usr/bin/env python3
"""
Check if Solidity test functions in test/btt/*.t.sol have corresponding
branches in their .tree files.

NOTE: This functionality is now integrated into tool/btt_check.py (RULE 11).
      This standalone script is kept for quick individual checks.

This is the inverse of `bulloak check` - it finds test functions that exist
in the .t.sol file but don't correspond to any tree branch.

The script parses tree files using bulloak's naming convention:
- Each leaf's immediate parent (when/given/etc.) becomes a test function
- Multiple "it should..." siblings under the same parent share one function

Usage:
    python tool/check_orphan_tests.py [--verbose] [--file FILE]
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
BTT_DIR = ROOT / "test" / "btt"


def normalize_name(name: str) -> str:
    """Normalize a name for comparison (lowercase, remove underscores)."""
    return name.lower().replace("_", "")


def extract_key_words(name: str) -> Set[str]:
    """Extract significant words from a function name."""
    # Remove common prefixes
    name = re.sub(r'^test_?', '', name, flags=re.I)
    # Split on underscores and camelCase
    words = re.findall(r'[A-Z][a-z]*|[a-z]+|\d+', name)
    # Filter out common words and short words
    stopwords = {'the', 'is', 'a', 'an', 'and', 'or', 'for', 'to', 'in', 'of', 'when', 'given', 'then'}
    return {w.lower() for w in words if len(w) > 2 and w.lower() not in stopwords}


def get_expected_functions_from_bulloak(tree_path: Path) -> Set[str]:
    """
    Run bulloak scaffold and extract expected function names.
    Returns a set of normalized function names.
    """
    try:
        result = subprocess.run(
            ["bulloak", "scaffold", str(tree_path), "--solidity-version", "^0.8.0"],
            capture_output=True,
            text=True,
            cwd=ROOT
        )
        output = result.stdout

        # Extract function names from scaffolded code
        function_names = set()
        for m in re.finditer(r"\bfunction\s+(test_[A-Za-z0-9_]+)\s*\(", output):
            function_names.add(m.group(1))

        return function_names
    except Exception as e:
        print(f"Error running bulloak: {e}", file=sys.stderr)
        return set()


def get_sol_test_functions(sol_path: Path) -> List[Tuple[str, int]]:
    """
    Extract test function names from a .t.sol file.
    Returns list of (function_name, line_number).
    """
    text = sol_path.read_text()
    functions = []

    # Match test functions
    pattern = r"\bfunction\s+(test_[A-Za-z0-9_]+)\s*\("
    for m in re.finditer(pattern, text):
        name = m.group(1)
        line = text[:m.start()].count("\n") + 1
        functions.append((name, line))

    return functions


def find_matching_tree_file(sol_path: Path) -> Path | None:
    """Find the .tree file that corresponds to a .t.sol file."""
    stem = sol_path.stem
    if stem.endswith(".t"):
        tree_stem = stem[:-2]
        tree_path = sol_path.parent / f"{tree_stem}.tree"
        if tree_path.exists():
            return tree_path
    return None


def extract_abstract_contract_name(sol_path: Path) -> str | None:
    """Extract the abstract contract name from a .t.sol file."""
    text = sol_path.read_text()
    m = re.search(r"abstract\s+contract\s+([A-Za-z0-9_]+)\s+is", text)
    if m:
        return m.group(1)
    return None


def find_tree_by_contract_name(contract_name: str) -> Path | None:
    """Find a .tree file by its contract name (first line)."""
    for tree_path in BTT_DIR.glob("*.tree"):
        first_line = tree_path.read_text().splitlines()[0].strip()
        if first_line == contract_name:
            return tree_path
    return None


def is_function_in_tree(func_name: str, expected_functions: Set[str]) -> bool:
    """
    Check if a function name matches any expected function from the tree.
    Handles shortened names like test_Foo_Bar vs test_Foo_GivenSomething_Bar.
    """
    normalized = normalize_name(func_name)

    # Direct match (normalized)
    if any(normalize_name(exp) == normalized for exp in expected_functions):
        return True

    # Extract key words from actual function
    actual_words = extract_key_words(func_name)
    if not actual_words:
        return False

    for expected in expected_functions:
        expected_words = extract_key_words(expected)

        # Check if actual words are a substantial subset of expected words
        common = actual_words & expected_words
        if len(common) >= len(actual_words) * 0.6:  # 60% of actual words match
            return True

        # Check if expected words are a substantial subset of actual words
        if len(common) >= len(expected_words) * 0.6:  # 60% of expected words match
            return True

        # Check normalized string containment
        norm_actual = normalize_name(func_name)
        norm_expected = normalize_name(expected)

        # Check if one contains the other (for shortened names)
        if norm_actual in norm_expected or norm_expected in norm_actual:
            return True

        # Check prefix match with some tolerance
        # e.g., "testgiventhepermissionidchangesduringmultipackageinstallpolicy"
        # should match "testgiventhepermissionidchangesduringamultipackageinstall"
        min_len = min(len(norm_actual), len(norm_expected))
        if min_len > 20:
            # Compare without the suffix (last few words might be context)
            if norm_actual[:min_len-10] == norm_expected[:min_len-10]:
                return True

    return False


def check_file(sol_path: Path, verbose: bool = False) -> List[Tuple[str, int]]:
    """
    Check a single .t.sol file for orphan tests.
    Returns list of (function_name, line_number) for orphan tests.
    """
    # Find matching tree file
    tree_path = find_matching_tree_file(sol_path)
    if not tree_path:
        contract_name = extract_abstract_contract_name(sol_path)
        if contract_name:
            tree_path = find_tree_by_contract_name(contract_name)

    if not tree_path:
        if verbose:
            print(f"Warning: No tree file found for {sol_path.name}")
        return []

    # Get expected function names from bulloak scaffold
    expected_functions = get_expected_functions_from_bulloak(tree_path)
    if not expected_functions:
        if verbose:
            print(f"Warning: Could not get expected functions for {tree_path.name}")
        return []

    # Get actual test functions from .t.sol
    actual_functions = get_sol_test_functions(sol_path)

    # Find orphans
    orphans = []
    for func_name, line_num in actual_functions:
        # Skip standard non-tree functions
        if func_name.startswith("test_receive_"):
            continue
        if func_name in ("test_setUp",):
            continue

        if not is_function_in_tree(func_name, expected_functions):
            orphans.append((func_name, line_num))

    return orphans


def check_orphan_tests(verbose: bool = False, specific_file: str | None = None) -> int:
    """
    Check for test functions that don't have corresponding tree leaves.
    Returns 1 if orphans found, 0 otherwise.
    """
    orphans: Dict[Path, List[Tuple[str, int]]] = {}
    total_orphans = 0

    if specific_file:
        sol_path = Path(specific_file)
        if not sol_path.is_absolute():
            sol_path = ROOT / sol_path
        file_orphans = check_file(sol_path, verbose)
        if file_orphans:
            orphans[sol_path] = file_orphans
            total_orphans = len(file_orphans)
    else:
        # Process each .t.sol file
        for sol_path in sorted(BTT_DIR.glob("*.t.sol")):
            file_orphans = check_file(sol_path, verbose)
            if file_orphans:
                orphans[sol_path] = file_orphans
                total_orphans += len(file_orphans)

    # Report results
    if orphans:
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

    print("No orphan tests found - all test functions have corresponding tree branches.")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Check for test functions without corresponding tree branches"
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="show warnings")
    parser.add_argument("--file", "-f", type=str, help="check a specific .t.sol file")
    args = parser.parse_args()

    sys.exit(check_orphan_tests(args.verbose, args.file))


if __name__ == "__main__":
    main()
