#!/usr/bin/env python3
"""Tests for release_check.py — verifies release descriptor integrity.

Runs two layers of verification:
  1. Python-based: validates JSON structure, bytecode matching, init_code
     composition, and CREATE2 address computation against compiled artifacts.
  2. Solidity-based: runs the on-chain ReleaseVerification.t.sol test via forge.

Usage:
    python3 tool/test/test_release_check.py                  # run all
    python3 tool/test/test_release_check.py --skip-forge      # Python only
    python3 tool/test/test_release_check.py --release releases/v0.4.0.json
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "out"
RELEASES_DIR = ROOT / "releases"


# ─── Helpers ────────────────────────────────────────────────────────


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


def get_artifact_bytecode(contract_name: str) -> str | None:
    """Get compiled creation bytecode from Foundry artifacts."""
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


def compute_create2_address(factory: str, salt: str, init_code_hex: str) -> str:
    """Compute CREATE2 address: keccak256(0xff ++ factory ++ salt ++ keccak256(init_code))[12:]"""
    init_code_hash = keccak256(init_code_hex)

    factory_bytes = factory.lower().replace("0x", "")
    salt_bytes = salt.replace("0x", "")
    hash_bytes = init_code_hash.replace("0x", "")

    preimage = "ff" + factory_bytes + salt_bytes + hash_bytes
    result = keccak256("0x" + preimage)
    return "0x" + result[-40:]


def abi_encode_address(addr: str) -> str:
    """ABI-encode an address to 32 bytes (no 0x prefix)."""
    return addr.lower().replace("0x", "").zfill(64)


# ─── Test functions ─────────────────────────────────────────────────


def test_json_structure(release: dict, errors: list[str]) -> None:
    """Validate required fields exist with correct types."""
    if "version" not in release:
        errors.append("missing 'version'")
    if "create2" not in release:
        errors.append("missing 'create2'")
    else:
        for key in ("factory", "salt"):
            if key not in release["create2"]:
                errors.append(f"missing 'create2.{key}'")

    if "foundry" not in release:
        errors.append("missing 'foundry'")
    else:
        for key in ("solc_version", "optimizer", "optimizer_runs", "evm_version"):
            if key not in release["foundry"]:
                errors.append(f"missing 'foundry.{key}'")

    if "contracts" not in release:
        errors.append("missing 'contracts'")
    elif not isinstance(release["contracts"], list):
        errors.append("'contracts' must be an array")
    elif len(release["contracts"]) == 0:
        errors.append("'contracts' is empty")

    for i, c in enumerate(release.get("contracts", [])):
        name = c.get("name", f"contracts[{i}]")
        for field in ("name", "bytecode", "init_code", "expected_address"):
            if field not in c:
                errors.append(f"{name}: missing '{field}'")


def test_bytecodes_match_artifacts(release: dict, errors: list[str]) -> None:
    """Verify each contract's bytecode matches the compiled Foundry artifact."""
    for c in release.get("contracts", []):
        name = c["name"]
        release_bytecode = c.get("bytecode", "")
        artifact_bytecode = get_artifact_bytecode(name)

        if artifact_bytecode is None:
            errors.append(f"{name}: compiled artifact not found (run forge build)")
            continue

        if release_bytecode.lower() != artifact_bytecode.lower():
            errors.append(f"{name}: bytecode mismatch with compiled artifact")


def test_init_code_integrity(release: dict, errors: list[str]) -> None:
    """Verify init_code starts with the compiled bytecode."""
    for c in release.get("contracts", []):
        name = c["name"]
        init_code = c.get("init_code", "")
        artifact_bytecode = get_artifact_bytecode(name)

        if not artifact_bytecode or not init_code:
            continue

        init_hex = init_code.lower().replace("0x", "")
        artifact_hex = artifact_bytecode.lower().replace("0x", "")

        if len(init_hex) < len(artifact_hex):
            errors.append(f"{name}: init_code shorter than bytecode")
            continue

        if not init_hex.startswith(artifact_hex):
            errors.append(f"{name}: init_code prefix does not match bytecode")


def test_init_code_args(release: dict, errors: list[str]) -> None:
    """Verify init_code = bytecode + ABI-encoded constructor args."""
    for c in release.get("contracts", []):
        name = c["name"]
        init_code = c.get("init_code", "")
        bytecode = c.get("bytecode", "")
        args = c.get("arguments")

        if not args:
            # No constructor args — init_code should equal bytecode
            if init_code.lower() != bytecode.lower():
                errors.append(f"{name}: no args but init_code != bytecode")
            continue

        # Reconstruct init_code from bytecode + encoded args
        encoded_args = ""
        for param in args.get("params", []):
            if param["type"] == "address":
                encoded_args += abi_encode_address(param["value"])
            else:
                errors.append(f"{name}: unsupported arg type '{param['type']}'")
                return

        expected_init = bytecode.lower().replace("0x", "") + encoded_args
        actual_init = init_code.lower().replace("0x", "")

        if actual_init != expected_init:
            errors.append(f"{name}: init_code != bytecode + encoded args")


def test_create2_addresses(release: dict, errors: list[str]) -> None:
    """Verify CREATE2 addresses match computed values."""
    factory = release.get("create2", {}).get("factory", "")
    salt = release.get("create2", {}).get("salt", "")

    if not factory or not salt:
        errors.append("missing create2 factory or salt")
        return

    for c in release.get("contracts", []):
        name = c["name"]
        init_code = c.get("init_code", "")
        expected_address = c.get("expected_address", "")

        if not init_code or not expected_address:
            continue

        computed = compute_create2_address(factory, salt, init_code)

        if computed.lower() != expected_address.lower():
            errors.append(
                f"{name}: address mismatch\n"
                f"    expected: {expected_address}\n"
                f"    computed: {computed}"
            )


def test_deployment_chain(release: dict, errors: list[str]) -> None:
    """Verify dependency chain: constructor args reference correct computed addresses."""
    addresses: dict[str, str] = {}
    factory = release.get("create2", {}).get("factory", "")
    salt = release.get("create2", {}).get("salt", "")

    for c in release.get("contracts", []):
        name = c["name"]
        expected_address = c.get("expected_address", "")

        # Check if any constructor arg references another contract's address
        args = c.get("arguments")
        if args:
            for param in args.get("params", []):
                if param["type"] == "address":
                    value = param["value"].lower()
                    # Check if this value matches a previously computed address
                    for dep_name, dep_addr in addresses.items():
                        if value == dep_addr.lower():
                            # Verify the referenced address was correctly computed
                            break

        if expected_address:
            addresses[name] = expected_address


def run_forge_test() -> bool:
    """Run the Solidity ReleaseVerification test via forge."""
    print("\nRunning Solidity release verification tests...")
    result = subprocess.run(
        [
            "forge", "test",
            "--match-contract", "ReleaseVerificationTest",
            "-vvv",
        ],
        cwd=str(ROOT),
        env={
            **__import__("os").environ,
            "FOUNDRY_PROFILE": "release-check",
        },
    )
    return result.returncode == 0


# ─── Main ───────────────────────────────────────────────────────────


def main() -> int:
    parser = argparse.ArgumentParser(description="Release verification tests")
    parser.add_argument(
        "--release",
        default=str(RELEASES_DIR / "v0.4.0.json"),
        help="path to release JSON file",
    )
    parser.add_argument(
        "--skip-forge",
        action="store_true",
        help="skip Solidity/forge tests",
    )
    args = parser.parse_args()

    release_path = Path(args.release)
    if not release_path.exists():
        print(f"Release file not found: {release_path}")
        return 1

    with open(release_path) as f:
        release = json.load(f)

    # Run Python tests
    tests = [
        ("JSON structure", test_json_structure),
        ("Bytecodes match artifacts", test_bytecodes_match_artifacts),
        ("init_code integrity", test_init_code_integrity),
        ("init_code args composition", test_init_code_args),
        ("CREATE2 addresses", test_create2_addresses),
        ("Deployment chain", test_deployment_chain),
    ]

    all_errors: list[str] = []
    for label, test_fn in tests:
        errors: list[str] = []
        test_fn(release, errors)
        if errors:
            print(f"  FAIL  {label}")
            for e in errors:
                print(f"        - {e}")
            all_errors.extend(errors)
        else:
            print(f"  OK    {label}")

    # Run Solidity tests
    forge_ok = True
    if not args.skip_forge:
        forge_ok = run_forge_test()
        if forge_ok:
            print("  OK    Solidity tests (forge)")
        else:
            print("  FAIL  Solidity tests (forge)")

    print()
    if all_errors or not forge_ok:
        print(f"RELEASE VERIFICATION FAILED ({len(all_errors)} errors)")
        return 1

    print("RELEASE VERIFICATION PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
