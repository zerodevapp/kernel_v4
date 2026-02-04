#!/usr/bin/env python3
"""
Definition location checker for Solidity files.

Ensures code organization by validating that:
1. All custom errors are defined in src/types/Error.sol
2. All events are defined in src/types/Events.sol

This helps maintain a clean codebase where errors and events are
centralized for easy discovery and documentation.
"""
import argparse
import re
from pathlib import Path
from typing import Dict, List, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "src"

# Canonical locations for definitions
ERROR_FILE = SRC_DIR / "types" / "Error.sol"
EVENTS_FILE = SRC_DIR / "types" / "Events.sol"

# Pattern to match error definitions with optional preceding comment
# Captures: optional comment, full definition
ERROR_FULL_RE = re.compile(
    r"((?:[ \t]*///[^\n]*\n)*)"  # Optional NatSpec comments
    r"([ \t]*error\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*;[ \t]*\n?)",
    re.MULTILINE
)

# Pattern to match event definitions with optional preceding comment
EVENT_FULL_RE = re.compile(
    r"((?:[ \t]*///[^\n]*\n)*)"  # Optional NatSpec comments
    r"([ \t]*event\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*;[ \t]*\n?)",
    re.MULTILINE
)

# Simple patterns for finding definitions (name and line only)
ERROR_DEF_RE = re.compile(
    r"^\s*error\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*;",
    re.MULTILINE
)
EVENT_DEF_RE = re.compile(
    r"^\s*event\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*;",
    re.MULTILINE
)


def find_definitions(path: Path, pattern: re.Pattern) -> List[Tuple[str, int]]:
    """Find all definitions matching pattern in a file."""
    text = path.read_text()
    results = []
    for m in pattern.finditer(text):
        name = m.group(1)
        line_no = text[:m.start()].count("\n") + 1
        results.append((name, line_no))
    return results


def get_existing_definitions(path: Path, pattern: re.Pattern) -> Set[str]:
    """Get set of definition names in a file."""
    if not path.exists():
        return set()
    return {name for name, _ in find_definitions(path, pattern)}


def extract_and_remove_definitions(
    path: Path,
    full_pattern: re.Pattern,
    existing_names: Set[str],
    verbose: bool,
) -> Tuple[List[str], List[str]]:
    """
    Extract definitions from a file and return them for moving.
    Returns (definitions_to_add, names_moved).
    """
    text = path.read_text()
    definitions_to_add = []
    names_moved = []
    names_removed = []  # Track all names removed (including duplicates)

    def replacer(m):
        comment = m.group(1)
        full_def = m.group(2)
        name = m.group(3)

        names_removed.append(name)

        # Build the definition to add (with comment if present)
        if name not in existing_names:
            def_text = (comment + full_def).strip()
            definitions_to_add.append(def_text)
            names_moved.append(name)
            existing_names.add(name)
            if verbose:
                print(f"  Extracting '{name}' from {path.relative_to(ROOT)}")
        else:
            if verbose:
                print(f"  Skipping '{name}' (already exists in target)")

        # Return empty string to remove the definition
        return ""

    new_text = full_pattern.sub(replacer, text)

    # Clean up multiple consecutive blank lines
    new_text = re.sub(r"\n{3,}", "\n\n", new_text)

    if new_text != text:
        path.write_text(new_text)

    return definitions_to_add, names_removed  # Return all removed names for import


def get_relative_import_path(from_file: Path, to_file: Path) -> str:
    """Calculate relative import path from one file to another."""
    from_dir = from_file.parent
    to_dir = to_file.parent

    # Calculate relative path
    try:
        rel_path = to_file.relative_to(from_dir)
        return "./" + str(rel_path)
    except ValueError:
        # Files are in different directory trees, need to go up
        pass

    # Find common ancestor
    from_parts = from_dir.parts
    to_parts = to_file.parts

    # Find common prefix length
    common_len = 0
    for i in range(min(len(from_parts), len(to_parts))):
        if from_parts[i] == to_parts[i]:
            common_len = i + 1
        else:
            break

    # Calculate how many levels to go up from from_dir
    levels_up = len(from_parts) - common_len

    # Build the relative path
    rel_parts = [".."] * levels_up + list(to_parts[common_len:])
    return "/".join(rel_parts)


def add_import_to_file(path: Path, target_file: Path, names: List[str]) -> None:
    """Add import statement to a file if not already present."""
    if not names:
        return

    text = path.read_text()
    import_path = get_relative_import_path(path, target_file)

    # Escape the path for regex
    escaped_path = re.escape(import_path)

    # Check if import from this path already exists
    import_pattern = re.compile(
        rf'import\s*\{{[^}}]*\}}\s*from\s*["\']' + escaped_path + r'["\'];'
    )

    existing_match = import_pattern.search(text)
    if existing_match:
        # Update existing import to add new names
        existing_import = existing_match.group(0)
        # Extract existing names
        names_match = re.search(r'\{([^}]+)\}', existing_import)
        if names_match:
            existing_names = [n.strip() for n in names_match.group(1).split(',')]
            all_names = sorted(set(existing_names + names))
            new_import = f'import {{{", ".join(all_names)}}} from "{import_path}";'
            text = text.replace(existing_import, new_import)
    else:
        # Add new import after the last import statement
        import_statement = f'import {{{", ".join(sorted(names))}}} from "{import_path}";\n'

        # Find the last import statement
        last_import = None
        for m in re.finditer(r'^import\s+[^;]+;[ \t]*\n', text, re.MULTILINE):
            last_import = m

        if last_import:
            insert_pos = last_import.end()
            text = text[:insert_pos] + import_statement + text[insert_pos:]
        else:
            # No imports found, add after pragma
            pragma_match = re.search(r'^pragma\s+[^;]+;[ \t]*\n', text, re.MULTILINE)
            if pragma_match:
                insert_pos = pragma_match.end()
                text = text[:insert_pos] + "\n" + import_statement + text[insert_pos:]

    path.write_text(text)


def append_definitions_to_file(path: Path, definitions: List[str]) -> None:
    """Append definitions to a canonical file."""
    if not path.exists():
        # Create the file with SPDX header
        content = "// SPDX-License-Identifier: MIT\npragma solidity ^0.8.0;\n\n"
        path.write_text(content)

    text = path.read_text()

    # Ensure proper spacing
    if not text.endswith("\n"):
        text += "\n"

    # Add each definition
    for definition in definitions:
        text += "\n" + definition + "\n"

    path.write_text(text)


def collect_misplaced_files(
    skip_interfaces: bool,
    check_errors: bool,
    check_events: bool,
) -> Tuple[Dict[Path, List[Tuple[str, int]]], Dict[Path, List[Tuple[str, int]]]]:
    """
    Collect all files with misplaced definitions.
    Returns (error_files, event_files) dicts mapping file -> list of (name, line).
    """
    error_files: Dict[Path, List[Tuple[str, int]]] = {}
    event_files: Dict[Path, List[Tuple[str, int]]] = {}

    for sol_file in SRC_DIR.rglob("*.sol"):
        # Skip canonical files
        if sol_file == ERROR_FILE or sol_file == EVENTS_FILE:
            continue

        # Skip interface files if requested
        if skip_interfaces and sol_file.name.startswith("I"):
            continue

        if check_errors:
            error_defs = find_definitions(sol_file, ERROR_DEF_RE)
            if error_defs:
                error_files[sol_file] = error_defs

        if check_events:
            event_defs = find_definitions(sol_file, EVENT_DEF_RE)
            if event_defs:
                event_files[sol_file] = event_defs

    return error_files, event_files


def fix_definitions(
    skip_interfaces: bool,
    check_errors: bool,
    check_events: bool,
    verbose: bool,
) -> int:
    """Move misplaced definitions to their canonical locations."""
    error_files, event_files = collect_misplaced_files(
        skip_interfaces, check_errors, check_events
    )

    total_moved = 0

    # Fix errors
    if error_files:
        existing_errors = get_existing_definitions(ERROR_FILE, ERROR_DEF_RE)
        all_error_defs = []

        if verbose:
            print("Processing errors...")

        for sol_file in sorted(error_files.keys()):
            defs_to_add, names_removed = extract_and_remove_definitions(
                sol_file, ERROR_FULL_RE, existing_errors, verbose
            )
            all_error_defs.extend(defs_to_add)
            total_moved += len(defs_to_add)

            # Add import for removed errors
            if names_removed:
                add_import_to_file(sol_file, ERROR_FILE, names_removed)

        if all_error_defs:
            append_definitions_to_file(ERROR_FILE, all_error_defs)

    # Fix events
    if event_files:
        existing_events = get_existing_definitions(EVENTS_FILE, EVENT_DEF_RE)
        all_event_defs = []

        if verbose:
            print("Processing events...")

        for sol_file in sorted(event_files.keys()):
            defs_to_add, names_removed = extract_and_remove_definitions(
                sol_file, EVENT_FULL_RE, existing_events, verbose
            )
            all_event_defs.extend(defs_to_add)
            total_moved += len(defs_to_add)

            # Add import for removed events
            if names_removed:
                add_import_to_file(sol_file, EVENTS_FILE, names_removed)

        if all_event_defs:
            append_definitions_to_file(EVENTS_FILE, all_event_defs)

    return total_moved


def check_all(
    errors_list: List[str],
    skip_interfaces: bool,
    check_errors: bool,
    check_events: bool,
) -> None:
    """Check all files for misplaced definitions."""
    error_files, event_files = collect_misplaced_files(
        skip_interfaces, check_errors, check_events
    )

    for sol_file, defs in sorted(error_files.items()):
        for name, line_no in defs:
            rel_path = sol_file.relative_to(ROOT)
            errors_list.append(
                f"{rel_path}:{line_no} error '{name}' should be defined in src/types/Error.sol"
            )

    for sol_file, defs in sorted(event_files.items()):
        for name, line_no in defs:
            rel_path = sol_file.relative_to(ROOT)
            errors_list.append(
                f"{rel_path}:{line_no} event '{name}' should be defined in src/types/Events.sol"
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check that errors and events are in canonical locations"
    )
    parser.add_argument(
        "--check-errors",
        action="store_true",
        dest="check_errors_only",
        help="only check error definitions",
    )
    parser.add_argument(
        "--check-events",
        action="store_true",
        dest="check_events_only",
        help="only check event definitions",
    )
    parser.add_argument(
        "--skip-interfaces",
        action="store_true",
        help="skip interface files (I*.sol) which may define errors/events per ERC standards",
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="automatically move definitions to canonical locations",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="show detailed output",
    )
    args = parser.parse_args()

    # Determine what to check
    check_both = not args.check_errors_only and not args.check_events_only
    do_check_errors = check_both or args.check_errors_only
    do_check_events = check_both or args.check_events_only

    if args.verbose and not args.fix:
        if do_check_errors and ERROR_FILE.exists():
            defs = find_definitions(ERROR_FILE, ERROR_DEF_RE)
            print(f"Errors in {ERROR_FILE.relative_to(ROOT)}: {len(defs)}")
            for name, line in defs:
                print(f"  {line}: {name}")
            print()

        if do_check_events and EVENTS_FILE.exists():
            defs = find_definitions(EVENTS_FILE, EVENT_DEF_RE)
            print(f"Events in {EVENTS_FILE.relative_to(ROOT)}: {len(defs)}")
            for name, line in defs:
                print(f"  {line}: {name}")
            print()

    if args.fix:
        moved = fix_definitions(
            args.skip_interfaces,
            do_check_errors,
            do_check_events,
            args.verbose,
        )
        if moved > 0:
            print(f"\nMoved {moved} definition(s) to canonical locations")
            print("Run 'forge fmt' to format the modified files")
        else:
            print("No definitions to move")
        return 0

    errors: List[str] = []
    check_all(errors, args.skip_interfaces, do_check_errors, do_check_events)

    if errors:
        print("DEFINITION LOCATION CHECK FAILED")
        print("The following definitions should be moved to their canonical locations:")
        print()
        for e in errors:
            print(f"- {e}")
        print()
        print("Move errors to: src/types/Error.sol")
        print("Move events to: src/types/Events.sol")
        print()
        print("Use --fix to automatically move definitions")
        return 1

    print("DEFINITION LOCATION CHECK PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
