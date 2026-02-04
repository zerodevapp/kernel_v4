#!/usr/bin/env python3
"""
Release configuration checker for Kernel v4.

Validates that each release includes a complete and valid release descriptor containing:
1. Foundry config (solc version, optimizer settings)
2. Module addresses and bytecode hashes
3. Deployment verification data

The release descriptor should be a JSON file (e.g., releases/v0.4.0.json) containing
all information needed to verify a deployment matches the expected state.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
FOUNDRY_TOML = ROOT / "foundry.toml"
RELEASES_DIR = ROOT / "releases"
OUT_DIR = ROOT / "out"

# Required fields in release descriptor
REQUIRED_FIELDS = {
    "version": str,
    "foundry": {
        "solc_version": str,
        "optimizer": bool,
        "optimizer_runs": int,
        "evm_version": str,
    },
    "contracts": list,
}

# Required fields per contract
REQUIRED_CONTRACT_FIELDS = {
    "name": str,
    "bytecode_hash": str,
}

OPTIONAL_CONTRACT_FIELDS = {
    "address": str,  # Optional: deployment address
    "init_code_hash": str,  # Optional: for CREATE2
    "source_hash": str,  # Optional: source code hash
}


def parse_foundry_toml(path: Path) -> Dict[str, Any]:
    """Parse foundry.toml and extract relevant config."""
    if not path.exists():
        return {}

    config = {}
    text = path.read_text()

    # Simple TOML parsing for the fields we care about
    patterns = {
        "solc_version": r"solc_version\s*=\s*['\"]([^'\"]+)['\"]",
        "optimizer": r"optimizer\s*=\s*(true|false)",
        "optimizer_runs": r"optimizer_runs\s*=\s*(\d+)",
        "evm_version": r"evm_version\s*=\s*['\"]([^'\"]+)['\"]",
        "via_ir": r"via_ir\s*=\s*(true|false)",
    }

    for key, pattern in patterns.items():
        m = re.search(pattern, text)
        if m:
            value = m.group(1)
            if value in ("true", "false"):
                value = value == "true"
            elif value.isdigit():
                value = int(value)
            config[key] = value

    return config


def compute_bytecode_hash(contract_name: str) -> Optional[Tuple[str, bool]]:
    """Compute bytecode hash from compiled artifacts.

    Returns:
        Tuple of (hash, has_link_references) or None if not found.
        has_link_references is True if bytecode contains library placeholders.
    """
    # Look for the contract in out/
    for json_file in OUT_DIR.rglob(f"{contract_name}.json"):
        try:
            with open(json_file) as f:
                artifact = json.load(f)

            bytecode = artifact.get("bytecode", {}).get("object", "")
            if bytecode and bytecode != "0x":
                # Check for library link references (format: __$<hash>$__)
                has_link_refs = "__$" in bytecode

                # Replace library placeholders with zeros for consistent hashing
                clean_bytecode = re.sub(r"__\$[a-fA-F0-9]+\$__", "0" * 40, bytecode)

                # Use keccak256 via cast
                result = subprocess.run(
                    ["cast", "keccak", clean_bytecode],
                    capture_output=True,
                    text=True,
                )
                if result.returncode == 0:
                    return (result.stdout.strip(), has_link_refs)
        except (json.JSONDecodeError, KeyError):
            continue

    return None


def compute_init_code_hash(contract_name: str) -> Optional[str]:
    """Compute init code hash (bytecode + constructor args placeholder)."""
    result = compute_bytecode_hash(contract_name)
    if result:
        return result[0]  # Return just the hash
    return None


def validate_release_descriptor(path: Path, errors: List[str], warnings: List[str]) -> Dict:
    """Validate a release descriptor file."""
    try:
        with open(path) as f:
            release = json.load(f)
    except json.JSONDecodeError as e:
        errors.append(f"{path.name}: invalid JSON ({e})")
        return {}

    # Check required top-level fields
    for field, expected_type in REQUIRED_FIELDS.items():
        if field not in release:
            errors.append(f"{path.name}: missing required field '{field}'")
        elif isinstance(expected_type, dict):
            if not isinstance(release[field], dict):
                errors.append(f"{path.name}: '{field}' must be an object")
            else:
                for subfield, subtype in expected_type.items():
                    if subfield not in release[field]:
                        errors.append(f"{path.name}: missing '{field}.{subfield}'")
                    elif not isinstance(release[field][subfield], subtype):
                        errors.append(f"{path.name}: '{field}.{subfield}' has wrong type")
        elif not isinstance(release.get(field), expected_type):
            errors.append(f"{path.name}: '{field}' has wrong type")

    # Validate contracts
    contracts = release.get("contracts", [])
    if not contracts:
        warnings.append(f"{path.name}: no contracts listed")

    for i, contract in enumerate(contracts):
        for field, expected_type in REQUIRED_CONTRACT_FIELDS.items():
            if field not in contract:
                errors.append(f"{path.name}: contract[{i}] missing '{field}'")
            elif not isinstance(contract[field], expected_type):
                errors.append(f"{path.name}: contract[{i}].{field} has wrong type")

        # Validate bytecode hash format (should be 0x + 64 hex chars)
        bytecode_hash = contract.get("bytecode_hash", "")
        if bytecode_hash and not re.match(r"^0x[a-fA-F0-9]{64}$", bytecode_hash):
            errors.append(f"{path.name}: contract[{i}].bytecode_hash invalid format")

        # Validate address format if present
        address = contract.get("address", "")
        if address and not re.match(r"^0x[a-fA-F0-9]{40}$", address):
            errors.append(f"{path.name}: contract[{i}].address invalid format")

    return release


def verify_foundry_config(release: Dict, errors: List[str], warnings: List[str]) -> None:
    """Verify release foundry config matches current foundry.toml."""
    current_config = parse_foundry_toml(FOUNDRY_TOML)
    release_config = release.get("foundry", {})

    checks = [
        ("solc_version", "Solidity version"),
        ("optimizer", "optimizer setting"),
        ("optimizer_runs", "optimizer runs"),
        ("evm_version", "EVM version"),
    ]

    for key, description in checks:
        current = current_config.get(key)
        expected = release_config.get(key)

        if current is None:
            warnings.append(f"foundry.toml missing {description}")
        elif expected is None:
            warnings.append(f"release missing {description}")
        elif current != expected:
            errors.append(
                f"{description} mismatch: foundry.toml has {current}, "
                f"release expects {expected}"
            )


def verify_bytecode_hashes(release: Dict, errors: List[str], warnings: List[str], verbose: bool) -> None:
    """Verify bytecode hashes match compiled artifacts."""
    contracts = release.get("contracts", [])

    for contract in contracts:
        name = contract.get("name", "unknown")
        expected_hash = contract.get("bytecode_hash", "")

        if not expected_hash:
            warnings.append(f"{name}: no bytecode_hash specified")
            continue

        result = compute_bytecode_hash(name)

        if result is None:
            warnings.append(f"{name}: compiled artifact not found (run forge build)")
        else:
            actual_hash, has_link_refs = result
            if actual_hash.lower() != expected_hash.lower():
                errors.append(
                    f"{name}: bytecode hash mismatch\n"
                    f"    expected: {expected_hash}\n"
                    f"    actual:   {actual_hash}"
                )
            elif verbose:
                suffix = " (has library references)" if has_link_refs else ""
                print(f"  {name}: bytecode hash verified{suffix}")


def generate_release_template(version: str, output_path: Path) -> None:
    """Generate a release descriptor template."""
    config = parse_foundry_toml(FOUNDRY_TOML)

    # Find main contracts in src/
    contracts = []
    skipped = []
    linked = []
    src_dir = ROOT / "src"
    for sol_file in src_dir.glob("*.sol"):
        if sol_file.name.startswith("I"):  # Skip interfaces
            continue
        contract_name = sol_file.stem
        result = compute_bytecode_hash(contract_name)

        if result is None:
            skipped.append(contract_name)
            continue

        bytecode_hash, has_link_refs = result
        if has_link_refs:
            linked.append(contract_name)

        contract_entry = {
            "name": contract_name,
            "bytecode_hash": bytecode_hash,
        }
        if has_link_refs:
            contract_entry["has_link_references"] = True
        contracts.append(contract_entry)

    if skipped:
        print(f"Skipped (abstract or no bytecode): {', '.join(skipped)}")
    if linked:
        print(f"Has library references (hash uses zero placeholders): {', '.join(linked)}")

    release = {
        "version": version,
        "foundry": {
            "solc_version": config.get("solc_version", ""),
            "optimizer": config.get("optimizer", True),
            "optimizer_runs": config.get("optimizer_runs", 200),
            "evm_version": config.get("evm_version", "paris"),
            "via_ir": config.get("via_ir", False),
        },
        "contracts": contracts,
        "deployments": {
            "mainnet": {},
            "sepolia": {},
        },
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(release, f, indent=2)
        f.write("\n")

    print(f"Generated release template: {output_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Release configuration checker")
    parser.add_argument(
        "release_file",
        nargs="?",
        help="specific release file to check (default: check all in releases/)",
    )
    parser.add_argument(
        "--generate",
        metavar="VERSION",
        help="generate a release template for VERSION (e.g., v0.4.0)",
    )
    parser.add_argument(
        "--verify-bytecode",
        action="store_true",
        help="verify bytecode hashes match compiled artifacts",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="show detailed output",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="treat warnings as errors",
    )
    args = parser.parse_args()

    # Generate template if requested
    if args.generate:
        version = args.generate
        output_path = RELEASES_DIR / f"{version}.json"
        generate_release_template(version, output_path)
        return 0

    errors: List[str] = []
    warnings: List[str] = []

    # Find release files to check
    if args.release_file:
        release_files = [Path(args.release_file)]
        if not release_files[0].is_absolute():
            release_files = [ROOT / args.release_file]
    elif RELEASES_DIR.exists():
        release_files = list(RELEASES_DIR.glob("*.json"))
    else:
        release_files = []

    if not release_files:
        if RELEASES_DIR.exists():
            warnings.append("no release files found in releases/")
        else:
            warnings.append("releases/ directory does not exist")
            print("RELEASE CHECK SKIPPED")
            print("No releases/ directory found. Use --generate VERSION to create one.")
            return 0

    # Check each release file
    for release_file in release_files:
        if args.verbose:
            print(f"Checking {release_file.name}...")

        release = validate_release_descriptor(release_file, errors, warnings)
        if not release:
            continue

        # Verify foundry config matches
        verify_foundry_config(release, errors, warnings)

        # Optionally verify bytecode hashes
        if args.verify_bytecode:
            verify_bytecode_hashes(release, errors, warnings, args.verbose)

    # Report results
    if args.verbose:
        print()

    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  - {w}")
        print()

    if args.strict:
        errors.extend(warnings)

    if errors:
        print("RELEASE CHECK FAILED")
        for e in errors:
            print(f"- {e}")
        return 1

    print("RELEASE CHECK PASSED")
    if warnings and not args.verbose:
        print(f"({len(warnings)} warnings - use -v to see)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
