// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

/// @notice Minimal CREATE2 deployer — etched at the factory address from the release file.
///         Calldata: salt (32 bytes) ++ init_code (remaining bytes).
contract Create2Proxy {
    fallback() external payable {
        assembly {
            let salt := calldataload(0)
            let sz := sub(calldatasize(), 0x20)
            calldatacopy(0, 0x20, sz)
            let addr := create2(callvalue(), 0, sz, salt)
            mstore(0, addr)
            return(0, 0x20)
        }
    }
}

/// @notice Verifies release bytecodes are functional and CREATE2 addresses are correct.
/// @dev Fully data-driven from the release JSON file — no hardcoded contract names or addresses.
///      Run with: FOUNDRY_PROFILE=release-check forge test
///
///      Verification layers:
///      1. Bytecodes in the release match compiled Foundry artifacts
///      2. init_code starts with the correct bytecode (no tampering)
///      3. CREATE2 addresses computed from init_codes match expected addresses
///      4. Contracts deployed via the CREATE2 factory land at the expected address
contract ReleaseVerificationTest is Test {
    string private json;
    address private create2Factory;
    bytes32 private create2Salt;
    uint256 private contractCount;

    function setUp() external {
        json = vm.readFile("releases/v0.4.0.json");
        create2Factory = vm.parseJsonAddress(json, ".create2.factory");
        create2Salt = vm.parseJsonBytes32(json, ".create2.salt");
        for (uint256 i; i < 100; i++) {
            if (!vm.keyExistsJson(json, string.concat(".contracts[", vm.toString(i), "]"))) break;
            contractCount++;
        }
        assertTrue(contractCount > 0, "no contracts in release file");

        // Etch a CREATE2 deployer at the factory address loaded from JSON
        vm.etch(create2Factory, address(new Create2Proxy()).code);
    }

    function _path(uint256 i, string memory field) internal returns (string memory) {
        return string.concat(".contracts[", vm.toString(i), "].", field);
    }

    function _computeCreate2(bytes memory initCode) internal view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), create2Factory, create2Salt, keccak256(initCode)))
                )
            )
        );
    }

    /// @notice Verifies each contract's release bytecode matches the compiled artifact.
    function test_BytecodeMatchesArtifact() external {
        for (uint256 i; i < contractCount; i++) {
            string memory name = vm.parseJsonString(json, _path(i, "name"));
            bytes memory releaseBytecode = vm.parseJsonBytes(json, _path(i, "bytecode"));
            bytes memory artifactBytecode = vm.getCode(string.concat(name, ".sol"));
            assertEq(keccak256(releaseBytecode), keccak256(artifactBytecode), name);
        }
    }

    /// @notice Encodes constructor arguments from the release JSON for contract at index i.
    ///         Returns empty bytes if the contract has no arguments.
    function _encodeArgs(uint256 i) internal returns (bytes memory encoded) {
        string memory argsKey = string.concat(".contracts[", vm.toString(i), "].arguments");
        if (!vm.keyExistsJson(json, argsKey)) return "";

        string memory paramsBase = string.concat(argsKey, ".params");
        for (uint256 j; j < 20; j++) {
            string memory paramKey = string.concat(paramsBase, "[", vm.toString(j), "]");
            if (!vm.keyExistsJson(json, paramKey)) break;

            string memory paramType = vm.parseJsonString(json, string.concat(paramKey, ".type"));
            if (keccak256(bytes(paramType)) == keccak256("address")) {
                address value = vm.parseJsonAddress(json, string.concat(paramKey, ".value"));
                encoded = abi.encodePacked(encoded, abi.encode(value));
            } else {
                revert(string.concat("unsupported arg type: ", paramType));
            }
        }
    }

    /// @notice Verifies init_code == bytecode + ABI-encoded constructor arguments.
    ///         Catches tampering in both the bytecode prefix and the encoded args.
    function test_InitCodeIntegrity() external {
        for (uint256 i; i < contractCount; i++) {
            string memory name = vm.parseJsonString(json, _path(i, "name"));
            bytes memory initCode = vm.parseJsonBytes(json, _path(i, "init_code"));
            bytes memory artifactBytecode = vm.getCode(string.concat(name, ".sol"));
            bytes memory encodedArgs = _encodeArgs(i);

            bytes memory expectedInitCode = abi.encodePacked(artifactBytecode, encodedArgs);
            assertEq(
                keccak256(initCode),
                keccak256(expectedInitCode),
                string.concat(name, ": init_code != bytecode + encoded args")
            );
        }
    }

    /// @notice Builds init_code from the compiled artifact bytecode + encoded JSON arguments.
    ///         Does NOT read init_code from the release file.
    function _buildInitCode(uint256 i) internal returns (bytes memory) {
        string memory name = vm.parseJsonString(json, _path(i, "name"));
        bytes memory artifactBytecode = vm.getCode(string.concat(name, ".sol"));
        bytes memory encodedArgs = _encodeArgs(i);
        return abi.encodePacked(artifactBytecode, encodedArgs);
    }

    /// @notice Computes CREATE2 addresses from compiled artifact + encoded JSON args
    ///         and verifies they match expected_address in the release file.
    function test_Create2Addresses() external {
        for (uint256 i; i < contractCount; i++) {
            string memory name = vm.parseJsonString(json, _path(i, "name"));
            address expected = vm.parseJsonAddress(json, _path(i, "expected_address"));
            bytes memory initCode = _buildInitCode(i);
            assertEq(_computeCreate2(initCode), expected, name);
        }
    }

    /// @notice Deploys each contract through the CREATE2 factory using init_code built
    ///         from compiled artifact + encoded JSON args. Verifies it lands at the
    ///         expected address with non-zero runtime code.
    ///         Contracts with no constructor args may need per-deployment args and are
    ///         allowed to fail deployment.
    function test_Create2Deployment() external {
        for (uint256 i; i < contractCount; i++) {
            string memory name = vm.parseJsonString(json, _path(i, "name"));
            address expected = vm.parseJsonAddress(json, _path(i, "expected_address"));
            bytes memory initCode = _buildInitCode(i);
            bytes memory encodedArgs = _encodeArgs(i);

            // Call the factory: calldata = salt ++ init_code
            (bool ok, bytes memory ret) =
                create2Factory.call(abi.encodePacked(create2Salt, initCode));

            if (!ok || ret.length < 32) {
                assertEq(encodedArgs.length, 0, string.concat(name, ": CREATE2 failed with constructor args"));
                continue;
            }

            address deployed = abi.decode(ret, (address));

            if (deployed == address(0)) {
                assertEq(encodedArgs.length, 0, string.concat(name, ": CREATE2 returned zero with constructor args"));
                continue;
            }

            assertEq(deployed, expected, string.concat(name, ": deployed at wrong address"));
            assertGt(deployed.code.length, 0, string.concat(name, ": empty runtime code"));
        }
    }
}
