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
import {IHook} from "src/interfaces/IERC7579Modules.sol";
import {EntryPointLib} from "../utils/EntryPointLib.sol";
import {ECDSAValidator} from "../mock/ECDSAValidator.sol";
import {MockCallee} from "../mock/MockCallee.sol";

/// @title  RootHookBypass — failing test for the unfixed vType=ROOT hook bypass
///
/// @notice STATUS: this test is EXPECTED TO FAIL on v0.4.0. Once the team makes the
///         vType=ROOT branch invoke `_setValidationHook(userOpHash, $.vInfo[$.root].hook)`,
///         the assertion below (preCalls == 1) will pass.
///
/// @dev    Bug: `src/Kernel.sol:161-174` short-circuits when `vType == VALIDATION_TYPE_ROOT`
///         and never calls `_setValidationHook`. The hook configured on the root
///         validator's vInfo is therefore never invoked during executeUserOp.
///         Reintroduced/inherited by PR #22 reorder for "gas optimization".
///
/// @dev    Severity: MEDIUM (gemini consensus). Defense-in-depth bypass under a
///         compromised-root threat model: any rate limit / target whitelist / emergency
///         pause hook the owner attached to root is silently disabled for vType=ROOT
///         userOps. The owner's mental model "my root hook always runs" is contradicted
///         by the contract.
///
/// @dev    Expected fix: resolve the effective vId (root fallback) first, then ALWAYS
///         call `_setValidationHook(userOpHash, $.vInfo[resolvedVid].hook)` regardless
///         of whether the user typed `vType=ROOT` or `vType=VALIDATOR`.
contract RootHookBypassTest is Test {
    IEntryPoint ep;
    KernelFactory factory;
    ECDSAValidator rootValidator;
    ECDSAValidator secondValidator;
    CountingHook hook;
    Kernel kernel;
    MockCallee callee;

    address owner;
    uint256 ownerKey;
    address payable beneficiary;

    function setUp() external {
        ep = EntryPointLib.deploy();
        KernelUUPS uups = new KernelUUPS(ep);
        KernelImmutableECDSA immutableEcdsa = new KernelImmutableECDSA(ep);
        factory = new KernelFactory(uups, immutableEcdsa);
        (owner, ownerKey) = makeAddrAndKey("Owner");
        beneficiary = payable(makeAddr("Bene"));
        callee = new MockCallee();
        rootValidator = new ECDSAValidator();
        secondValidator = new ECDSAValidator();
        hook = new CountingHook();

        Install[] memory bootPkgs = new Install[](1);
        bootPkgs[0] = Install({
            moduleType: 1,
            module: address(rootValidator),
            moduleData: abi.encodePacked(owner),
            internalData: hex""
        });
        kernel = factory.deploy(bootPkgs, 0);
        vm.deal(address(kernel), 10 ether);

        // Install the hook as a type-4 module so `_hookEnabled(hook)` returns true.
        vm.prank(address(ep));
        kernel.installModule(4, address(hook), abi.encode(hex"", hex""));

        // Install secondValidator as type-1 with the hook attached via internalData[0:20].
        vm.prank(address(ep));
        kernel.installModule(
            1,
            address(secondValidator),
            abi.encode(abi.encodePacked(owner), abi.encodePacked(address(hook)))
        );

        // Promote secondValidator to root. Its vInfo.hook is now the configured hook.
        ValidationId secondVid =
            ValidationId.wrap(bytes21(abi.encodePacked(bytes1(0x01), address(secondValidator))));
        vm.prank(address(ep));
        kernel.setRoot(secondVid);

        assertEq(kernel.validationInfo(secondVid).hook, address(hook), "root hook must be configured");
    }

    /// @notice Asserts the hook fires when a userOp authenticates as vType=ROOT.
    ///         Currently FAILS on v0.4.0 because `_setValidationHook` is never called
    ///         in the vType=ROOT branch, so executeUserOp's _preHook/_postHook are no-ops.
    function test_root_hook_should_fire_on_vType_ROOT_userOp() external {
        bytes memory execData = abi.encodeWithSelector(
            Kernel.execute.selector,
            bytes32(0),
            abi.encodePacked(address(beneficiary), uint256(1 ether), hex"")
        );

        PackedUserOperation memory op;
        op.sender = address(kernel);
        uint192 key = uint192(bytes24(abi.encodePacked(bytes1(0), bytes1(0x00), bytes20(0), bytes2(0))));
        op.nonce = ep.getNonce(address(kernel), key);
        op.callData = execData;
        op.accountGasLimits = bytes32((uint256(1_000_000) << 128) | uint256(1_000_000));
        op.preVerificationGas = 100_000;
        op.gasFees = bytes32((uint256(1 gwei) << 128) | uint256(1 gwei));

        bytes32 opHash = ep.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, opHash);
        op.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        uint256 preBefore = hook.preCalls();
        uint256 postBefore = hook.postCalls();

        vm.prank(beneficiary, beneficiary);
        ep.handleOps(ops, beneficiary);

        // EXPECTED-AFTER-FIX: the hook configured on the root vId MUST fire.
        assertEq(hook.preCalls(), preBefore + 1, "preCheck must fire on root-authorized userOp");
        assertEq(hook.postCalls(), postBefore + 1, "postCheck must fire on root-authorized userOp");
    }
}

/// Minimal hook that counts calls. If the bug is fixed, these counters will increment.
contract CountingHook is IHook {
    uint256 public preCalls;
    uint256 public postCalls;

    function onInstall(bytes calldata) external payable {}
    function onUninstall(bytes calldata) external payable {}
    function isModuleType(uint256 t) external pure returns (bool) {
        return t == 4;
    }
    function isInitialized(address) external pure returns (bool) {
        return true;
    }

    function preCheck(address, uint256, bytes calldata) external payable returns (bytes memory) {
        preCalls++;
        return hex"";
    }

    function postCheck(bytes calldata) external payable {
        postCalls++;
    }
}
