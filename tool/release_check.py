#!/usr/bin/env python3
"""
Release configuration checker for Kernel v4.

Validates that each release includes a complete and valid release descriptor containing:
1. Foundry config (solc version, optimizer settings)
2. Contract bytecodes with encoded constructor arguments
3. Expected CREATE2 deployment addresses
4. Deployment verification data

The release descriptor should be a JSON file (e.g., releases/v0.4.0.json) containing
all information needed to verify a deployment matches the expected state.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
FOUNDRY_TOML = ROOT / "foundry.toml"
RELEASES_DIR = ROOT / "releases"
OUT_DIR = ROOT / "out"

# Deterministic CREATE2 factory (nick's factory)
CREATE2_FACTORY = "0x4e59b44847b379578588920cA78FbF26c0B4956C"
CREATE2_SALT = "0x" + "00" * 32

# EntryPoint v0.9.0 canonical address
ENTRYPOINT_V09 = "0x433709009B8330FDa32311DF1C2AFA402eD8D009"

# Contract deployment order and constructor argument definitions.
# Arguments reference either a constant or another contract's computed address.
# Contracts are listed in deploy order (dependencies first).
DEPLOY_ORDER = [
    {
        "name": "Staker",
        "args": [],  # owner is per-deployment, not encoded
    },
    {
        "name": "KernelUUPS",
        "args": [("address", ENTRYPOINT_V09)],
    },
    {
        "name": "KernelImmutableECDSA",
        "args": [("address", ENTRYPOINT_V09)],
    },
    {
        "name": "KernelFactory",
        "args": [("address", "@KernelUUPS"), ("address", "@KernelImmutableECDSA")],
    },
    {
        "name": "Kernel7702",
        "args": [("address", ENTRYPOINT_V09)],
    },
]

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


def parse_foundry_toml(path: Path) -> Dict[str, Any]:
    """Parse foundry.toml and extract relevant config."""
    if not path.exists():
        return {}

    config = {}
    text = path.read_text()

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


def get_bytecode(contract_name: str) -> Optional[str]:
    """Get compiled bytecode from artifacts.

    Returns:
        The bytecode hex string (with 0x prefix) or None if not found.
    """
    for json_file in OUT_DIR.rglob(f"{contract_name}.json"):
        try:
            with open(json_file) as f:
                artifact = json.load(f)

            bytecode = artifact.get("bytecode", {}).get("object", "")
            if bytecode and bytecode != "0x":
                return bytecode
        except (json.JSONDecodeError, KeyError):
            continue

    return None


def keccak256(hex_data: str) -> str:
    """Compute keccak256 hash using cast."""
    result = subprocess.run(
        ["cast", "keccak", hex_data],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"cast keccak failed: {result.stderr}")
    return result.stdout.strip()


def abi_encode_args(arg_types: list[tuple[str, str]]) -> str:
    """ABI-encode constructor arguments.

    Returns hex string without 0x prefix, or empty string if no args.
    """
    if not arg_types:
        return ""

    parts = []
    for typ, value in arg_types:
        if typ == "address":
            # Pad address to 32 bytes
            addr = value.lower().replace("0x", "")
            parts.append(addr.zfill(64))
        else:
            raise ValueError(f"Unsupported ABI type: {typ}")

    return "".join(parts)


def compute_create2_address(factory: str, salt: str, init_code_hex: str) -> str:
    """Compute CREATE2 address.

    address = keccak256(0xff ++ factory ++ salt ++ keccak256(init_code))[12:]
    """
    init_code_hash = keccak256(init_code_hex)

    factory_bytes = factory.lower().replace("0x", "")
    salt_bytes = salt.replace("0x", "")
    hash_bytes = init_code_hash.replace("0x", "")

    preimage = "ff" + factory_bytes + salt_bytes + hash_bytes
    result = keccak256("0x" + preimage)
    # Take last 20 bytes (40 hex chars)
    addr = "0x" + result[-40:]
    return addr


def resolve_args(
    arg_defs: list[tuple[str, str]],
    addresses: dict[str, str],
) -> list[tuple[str, str]]:
    """Resolve argument definitions, replacing @ContractName references with computed addresses."""
    resolved = []
    for typ, value in arg_defs:
        if value.startswith("@"):
            contract_ref = value[1:]
            if contract_ref not in addresses:
                raise ValueError(f"Contract {contract_ref} not yet deployed (check DEPLOY_ORDER)")
            value = addresses[contract_ref]
        resolved.append((typ, value))
    return resolved


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
        name = contract.get("name", f"contract[{i}]")
        if "name" not in contract:
            errors.append(f"{path.name}: {name} missing 'name'")
        if "bytecode" not in contract:
            errors.append(f"{path.name}: {name} missing 'bytecode'")

        # Validate hex formats
        for field in ("bytecode", "init_code"):
            val = contract.get(field, "")
            if val and not re.match(r"^0x[a-fA-F0-9]+$", val):
                errors.append(f"{path.name}: {name}.{field} invalid hex format")

        for field in ("expected_address",):
            val = contract.get(field, "")
            if val and not re.match(r"^0x[a-fA-F0-9]{40}$", val):
                errors.append(f"{path.name}: {name}.{field} invalid address format")

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


def verify_bytecodes(release: Dict, errors: List[str], warnings: List[str], verbose: bool) -> None:
    """Verify bytecodes and init_codes match compiled artifacts and computed addresses."""
    contracts = release.get("contracts", [])
    addresses: dict[str, str] = {}

    for contract in contracts:
        name = contract.get("name", "unknown")

        # Verify raw bytecode matches artifact
        expected_bytecode = contract.get("bytecode", "")
        if not expected_bytecode:
            warnings.append(f"{name}: no bytecode specified")
            continue

        actual_bytecode = get_bytecode(name)
        if actual_bytecode is None:
            warnings.append(f"{name}: compiled artifact not found (run forge build)")
            continue

        if actual_bytecode.lower() != expected_bytecode.lower():
            errors.append(f"{name}: bytecode mismatch")
            continue

        # Verify init_code = bytecode + encoded args
        init_code = contract.get("init_code", "")
        args = contract.get("arguments", {})
        if args:
            arg_hex = abi_encode_args([(a["type"], a["value"]) for a in args.get("params", [])])
            expected_init = actual_bytecode + arg_hex
            if init_code and init_code.lower() != ("0x" + expected_init.replace("0x", "")).lower():
                errors.append(f"{name}: init_code does not match bytecode + encoded arguments")
                continue

        # Verify expected_address via CREATE2
        expected_addr = contract.get("expected_address", "")
        if expected_addr and init_code:
            computed = compute_create2_address(CREATE2_FACTORY, CREATE2_SALT, init_code)
            if computed.lower() != expected_addr.lower():
                errors.append(
                    f"{name}: expected_address mismatch\n"
                    f"    release:  {expected_addr}\n"
                    f"    computed: {computed}"
                )
                continue

        if expected_addr:
            addresses[name] = expected_addr

        if verbose:
            suffix = f" @ {expected_addr}" if expected_addr else ""
            print(f"  {name}: verified{suffix}")


def generate_release_template(version: str, output_path: Path) -> None:
    """Generate a release descriptor template with constructor args and CREATE2 addresses."""
    config = parse_foundry_toml(FOUNDRY_TOML)
    contracts = []
    skipped = []
    addresses: dict[str, str] = {}

    for spec in DEPLOY_ORDER:
        name = spec["name"]
        arg_defs = spec["args"]

        bytecode = get_bytecode(name)
        if bytecode is None:
            skipped.append(name)
            continue

        # Resolve constructor arguments (replace @ContractName with computed addresses)
        resolved_args = resolve_args(arg_defs, addresses)
        encoded_args = abi_encode_args(resolved_args)

        # init_code = bytecode + encoded constructor args
        bytecode_hex = bytecode.replace("0x", "")
        init_code = "0x" + bytecode_hex + encoded_args

        # Compute CREATE2 address
        expected_address = compute_create2_address(CREATE2_FACTORY, CREATE2_SALT, init_code)
        addresses[name] = expected_address

        # Build contract entry
        entry: dict[str, Any] = {
            "name": name,
            "bytecode": bytecode,
        }

        if resolved_args:
            entry["arguments"] = {
                "constructor": " | ".join(t for t, _ in resolved_args),
                "params": [{"type": t, "value": v} for t, v in resolved_args],
            }

        entry["init_code"] = init_code
        entry["expected_address"] = expected_address

        contracts.append(entry)
        print(f"  {name} -> {expected_address}")

    if skipped:
        print(f"Skipped (abstract or no bytecode): {', '.join(skipped)}")

    release = {
        "version": version,
        "create2": {
            "factory": CREATE2_FACTORY,
            "salt": CREATE2_SALT,
        },
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
        help="verify bytecodes, init_codes, and addresses match",
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

        # Optionally verify bytecodes
        if args.verify_bytecode:
            verify_bytecodes(release, errors, warnings, args.verbose)

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
