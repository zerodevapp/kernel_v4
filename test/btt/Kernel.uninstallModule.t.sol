// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";
import {MockValidator} from "../mock/MockValidator.sol";
import {MockExecutor} from "../mock/MockExecutor.sol";
import {MockHook} from "../mock/MockHook.sol";
import {MockFallback} from "../mock/MockFallback.sol";
import {MockPolicy} from "../mock/MockPolicy.sol";
import {MockSigner} from "../mock/MockSigner.sol";
import {IValidator} from "src/interfaces/IERC7579Modules.sol";
import {validatorToIdentifier, permissionToIdentifier} from "src/lib/Utils.sol";
import {PermissionId} from "src/types/Types.sol";
import {Unauthorized, NotImplemented} from "src/types/Error.sol";

/// @title Kernel.uninstallModule BTT Tests
/// @notice Tests for uninstallModule following Branching Tree Technique
/// @dev Tree specification: test/btt/Kernel.uninstallModule.tree
abstract contract Kernel_uninstallModule is BTTModifiers {
    /*//////////////////////////////////////////////////////////////
                        UNAUTHORIZED CALLER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WhenTheCallerIsNotTheEntryPointUninstall() external whenTheCallerIsNotTheEntryPointUninstall {
        vm.expectRevert(Unauthorized.selector);
        kernel.uninstallModule(1, address(newValidator), abi.encode(hex"", hex""));
    }

    modifier whenTheCallerIsTheEntryPointOrSelfUninstall() {
        vm.stopPrank();
        vm.startPrank(address(ep));
        _;
    }

    modifier givenModuleTypeIsValidatorUninstall() {
        _;
    }

    function test_GivenModuleTypeIsValidatorUninstall()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsValidatorUninstall
    {
        MockValidator mockValidator = new MockValidator();
        kernel.installModule(1, address(mockValidator), abi.encode(hex"", hex""));

        kernel.uninstallModule(1, address(mockValidator), abi.encode(hex"", hex""));

        // Verify the validator is no longer installed (hook is cleared)
        assertEq(
            kernel.validationInfo(validatorToIdentifier(IValidator(address(mockValidator)))).hook,
            address(0),
            "Validator hook should be cleared"
        );
    }

    function test_GivenTheValidatorIsNotTheRoot()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsValidatorUninstall
    {
        // Install a non-root validator
        MockValidator mockValidator = new MockValidator();
        kernel.installModule(1, address(mockValidator), abi.encode(hex"", hex""));

        // Verify it's installed
        assertTrue(kernel.isModuleInstalled(1, address(mockValidator), ""), "Validator should be installed");

        // Uninstall it
        kernel.uninstallModule(1, address(mockValidator), abi.encode(hex"", hex""));

        // Verify it's uninstalled
        assertFalse(kernel.isModuleInstalled(1, address(mockValidator), ""), "Validator should be uninstalled");
    }

    modifier givenModuleTypeIsExecutorUninstall() {
        _;
    }

    function test_GivenModuleTypeIsExecutorUninstall()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsExecutorUninstall
    {
        MockExecutor mockExecutor = new MockExecutor();
        kernel.installModule(2, address(mockExecutor), abi.encode(hex"", hex""));

        kernel.uninstallModule(2, address(mockExecutor), abi.encode(hex"", hex""));

        // Verify the executor is no longer installed
        assertFalse(kernel.isModuleInstalled(2, address(mockExecutor), ""), "Executor should be uninstalled");
    }

    function test_GivenUninstallingAnInstalledExecutor()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsExecutorUninstall
    {
        MockExecutor mockExecutor = new MockExecutor();
        kernel.installModule(2, address(mockExecutor), abi.encode(hex"", hex""));

        assertTrue(kernel.isModuleInstalled(2, address(mockExecutor), ""), "Executor should be installed");

        kernel.uninstallModule(2, address(mockExecutor), abi.encode(hex"", hex""));

        assertFalse(kernel.isModuleInstalled(2, address(mockExecutor), ""), "Executor should be uninstalled");
    }

    modifier givenModuleTypeIsFallbackUninstall() {
        _;
    }

    function test_GivenTheSelectorIsRegistered()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsFallbackUninstall
    {
        MockFallback mockFallback = new MockFallback();
        bytes4 selector = bytes4(keccak256("customFunction()"));
        bytes memory internalData = abi.encodePacked(selector, bytes1(0x00), address(1));

        kernel.installModule(3, address(mockFallback), abi.encode(hex"", internalData));

        assertTrue(
            kernel.isModuleInstalled(3, address(mockFallback), abi.encodePacked(selector)),
            "Fallback should be installed"
        );

        // Uninstall with selector in internalData
        kernel.uninstallModule(3, address(mockFallback), abi.encode(hex"", abi.encodePacked(selector)));

        assertFalse(
            kernel.isModuleInstalled(3, address(mockFallback), abi.encodePacked(selector)),
            "Fallback should be uninstalled"
        );
    }

    modifier givenModuleTypeIsHookUninstall() {
        _;
    }

    function test_GivenModuleTypeIsHookUninstall()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsHookUninstall
    {
        MockHook mockHook = new MockHook();
        kernel.installModule(4, address(mockHook), abi.encode(hex"", ""));

        kernel.uninstallModule(4, address(mockHook), abi.encode(hex"", ""));

        // Verify the hook is no longer enabled
        assertFalse(kernel.isModuleInstalled(4, address(mockHook), ""), "Hook should be disabled");
    }

    function test_GivenUninstallingAnEnabledHook()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsHookUninstall
    {
        MockHook mockHook = new MockHook();
        kernel.installModule(4, address(mockHook), abi.encode(hex"", ""));

        assertTrue(kernel.isModuleInstalled(4, address(mockHook), ""), "Hook should be enabled");

        kernel.uninstallModule(4, address(mockHook), abi.encode(hex"", ""));

        assertFalse(kernel.isModuleInstalled(4, address(mockHook), ""), "Hook should be disabled");
    }

    modifier givenModuleTypeIsPolicyUninstall() {
        _;
    }

    function test_GivenThePolicyIsInstalledForThisPermissionId()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsPolicyUninstall
    {
        MockPolicy mockPolicy = new MockPolicy();
        PermissionId testPermId = PermissionId.wrap(bytes4(keccak256("uninstallPolicyTest")));
        bytes memory internalData = abi.encodePacked(testPermId);

        kernel.installModule(5, address(mockPolicy), abi.encode(hex"", internalData));

        assertTrue(
            kernel.isModuleInstalled(5, address(mockPolicy), abi.encodePacked(testPermId)), "Policy should be installed"
        );

        kernel.uninstallModule(5, address(mockPolicy), abi.encode(hex"", internalData));

        assertFalse(
            kernel.isModuleInstalled(5, address(mockPolicy), abi.encodePacked(testPermId)),
            "Policy should be uninstalled"
        );
    }

    modifier givenModuleTypeIsSignerUninstall() {
        _;
    }

    function test_GivenASignerIsInstalledForThisPermissionId()
        external
        whenTheCallerIsTheEntryPointOrSelfUninstall
        givenModuleTypeIsSignerUninstall
    {
        MockPolicy mockPolicy = new MockPolicy();
        MockSigner mockSigner = new MockSigner();
        PermissionId testPermId = PermissionId.wrap(bytes4(keccak256("uninstallSignerTest")));
        bytes memory internalData = abi.encodePacked(testPermId);

        // Install policy first
        kernel.installModule(5, address(mockPolicy), abi.encode(hex"", internalData));
        // Install signer
        kernel.installModule(6, address(mockSigner), abi.encode(hex"", internalData));

        assertTrue(
            kernel.isModuleInstalled(6, address(mockSigner), abi.encodePacked(testPermId)), "Signer should be installed"
        );

        // Uninstall policy first (policies must be uninstalled before signer)
        kernel.uninstallModule(5, address(mockPolicy), abi.encode(hex"", internalData));

        // Now uninstall signer
        kernel.uninstallModule(6, address(mockSigner), abi.encode(hex"", internalData));

        assertFalse(
            kernel.isModuleInstalled(6, address(mockSigner), abi.encodePacked(testPermId)),
            "Signer should be uninstalled"
        );
    }

    function test_GivenModuleTypeIsUnsupported() external whenTheCallerIsTheEntryPointOrSelfUninstall {
        vm.expectRevert(NotImplemented.selector);
        kernel.uninstallModule(7, address(0x123), abi.encode(hex"", hex""));
    }

    // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    // ==================== BULLOAK AUTOGENERATED SEPARATOR ====================
    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    //    Code below this section could not be automatically moved by bulloak
    // =========================================================================

    // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    // ==================== BULLOAK AUTOGENERATED SEPARATOR ====================
    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    //    Code below this section could not be automatically moved by bulloak
    // =========================================================================
    modifier whenTheCallerIsNotTheEntryPointUninstall() {
        vm.stopPrank();
        vm.startPrank(makeAddr("randomCaller"));
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR UNINSTALL TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                        EXECUTOR UNINSTALL TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                        FALLBACK UNINSTALL TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                        HOOK UNINSTALL TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                        POLICY UNINSTALL TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                        SIGNER UNINSTALL TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                    UNSUPPORTED MODULE TYPE TESTS
    //////////////////////////////////////////////////////////////*/
}
