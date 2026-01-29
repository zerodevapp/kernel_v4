// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Kernel} from "src/Kernel.sol";
import {BTTModifiers} from "./BTTModifiers.sol";
import {MockValidator} from "../mock/MockValidator.sol";
import {MockExecutor} from "../mock/MockExecutor.sol";
import {MockHook} from "../mock/MockHook.sol";
import {MockFallback} from "../mock/MockFallback.sol";
import {MockPolicy} from "../mock/MockPolicy.sol";
import {MockSigner} from "../mock/MockSigner.sol";
import {IValidator, IExecutor, IHook} from "src/interfaces/IERC7579Modules.sol";
import {validatorToIdentifier, permissionToIdentifier} from "src/lib/Utils.sol";
import {PermissionId} from "src/types/Types.sol";
import {Unauthorized, NotImplemented} from "src/types/Error.sol";

/// @title Kernel.installModule BTT Tests
/// @notice Tests for installModule following Branching Tree Technique
/// @dev Tree specification: test/btt/Kernel.installModule.tree
abstract contract Kernel_installModule is BTTModifiers {
    modifier whenTheCallerIsNotTheEntryPoint() {
        _;
    }

    function test_WhenTheCallerIsNotTheAccountItself() external whenTheCallerIsNotTheEntryPoint {
        // it should revert with Unauthorized error
    }

    modifier whenTheCallerIsTheEntryPointOrSelf() {
        _;
    }

    modifier givenModuleTypeIsValidator() override {
        _;
    }

    function test_GivenTheValidatorIsAlreadyInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsValidator
    {
        // it should revert with ValidatorAlreadyInstalled error
    }

    modifier givenTheValidatorIsNotInstalled() {
        _;
    }

    function test_GivenTheValidatorIsNotInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsValidator
        givenTheValidatorIsNotInstalled
    {
        // it should call onInstall on the validator with moduleData
    }

    function test_GivenOnInstallReverts()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsValidator
        givenTheValidatorIsNotInstalled
    {
        // it should propagate the revert
    }

    function test_GivenOnInstallSucceeds()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsValidator
        givenTheValidatorIsNotInstalled
    {
        // it should mark the validator as installed
        // it should set the hook from internalData or address1 if empty
        // it should parse allowed selectors from internalData
        // it should emit ModuleInstalled event
    }

    function test_GivenInternalDataContainsAHookAddress()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsValidator
        givenTheValidatorIsNotInstalled
    {
        // it should install the hook if not already installed
        // it should associate the hook with this validator
    }

    modifier givenModuleTypeIsExecutor() override {
        _;
    }

    function test_GivenTheExecutorIsAlreadyInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsExecutor
    {
        // it should revert with ExecutorAlreadyInstalled error
    }

    modifier givenTheExecutorIsNotInstalled() {
        _;
    }

    function test_GivenTheExecutorIsNotInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsExecutor
        givenTheExecutorIsNotInstalled
    {
        // it should call onInstall on the executor with moduleData
    }

    function test_GivenOnInstallReverts_GivenTheExecutorIsNotInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsExecutor
        givenTheExecutorIsNotInstalled
    {
        // it should propagate the revert
    }

    function test_GivenOnInstallSucceeds_GivenTheExecutorIsNotInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsExecutor
        givenTheExecutorIsNotInstalled
    {
        // it should mark the executor as installed
        // it should set the hook from internalData or address1 if empty
        // it should emit ModuleInstalled event
    }

    modifier givenModuleTypeIsFallback() override {
        _;
    }

    function test_GivenTheSelectorIsAlreadyRegistered()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsFallback
    {
        // it should revert with FallbackAlreadyInstalled error
    }

    modifier givenTheSelectorIsNotRegistered() {
        _;
    }

    function test_GivenTheSelectorIsNotRegistered()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsFallback
        givenTheSelectorIsNotRegistered
    {
        // it should call onInstall on the fallback handler with moduleData
    }

    function test_GivenOnInstallSucceeds_GivenTheSelectorIsNotRegistered()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsFallback
        givenTheSelectorIsNotRegistered
    {
        // it should register the selector to the fallback handler
        // it should set the callType from internalData
        // it should set the hook from internalData or address0 if not specified
        // it should emit ModuleInstalled event
    }

    modifier givenModuleTypeIsHook() override {
        _;
    }

    function test_GivenTheHookIsAlreadyEnabled() external whenTheCallerIsTheEntryPointOrSelf givenModuleTypeIsHook {
        // it should revert with HookAlreadyInstalled error
    }

    modifier givenTheHookIsNotEnabled() {
        _;
    }

    function test_GivenTheHookIsNotEnabled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsHook
        givenTheHookIsNotEnabled
    {
        // it should call onInstall on the hook with moduleData
    }

    function test_GivenOnInstallSucceeds_GivenTheHookIsNotEnabled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsHook
        givenTheHookIsNotEnabled
    {
        // it should mark the hook as enabled
        // it should emit ModuleInstalled event
    }

    modifier givenModuleTypeIsPolicy() override {
        _;
    }

    function test_GivenModuleTypeIsPolicy() external whenTheCallerIsTheEntryPointOrSelf givenModuleTypeIsPolicy {
        // it should parse the permissionId from internalData
    }

    function test_GivenThePolicyIsAlreadyInstalledForThisPermissionId()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsPolicy
    {
        // it should revert with PolicyAlreadyInstalled error
    }

    modifier givenThePolicyIsNotInstalledForThisPermissionId() {
        _;
    }

    function test_GivenThePolicyIsNotInstalledForThisPermissionId()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsPolicy
        givenThePolicyIsNotInstalledForThisPermissionId
    {
        // it should call onInstall on the policy with moduleData
    }

    function test_GivenOnInstallSucceeds_GivenThePolicyIsNotInstalledForThisPermissionId()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsPolicy
        givenThePolicyIsNotInstalledForThisPermissionId
    {
        // it should add the policy to the permissionId policy list
        // it should emit ModuleInstalled event
    }

    modifier givenModuleTypeIsSigner() override {
        _;
    }

    function test_GivenModuleTypeIsSigner() external whenTheCallerIsTheEntryPointOrSelf givenModuleTypeIsSigner {
        // it should parse the permissionId from internalData
    }

    function test_GivenASignerIsAlreadyInstalledForThisPermissionId()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsSigner
    {
        // it should revert with SignerAlreadyInstalled error
    }

    modifier givenNoSignerIsInstalledForThisPermissionId() {
        _;
    }

    function test_GivenNoSignerIsInstalledForThisPermissionId()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsSigner
        givenNoSignerIsInstalledForThisPermissionId
    {
        // it should call onInstall on the signer with moduleData
    }

    function test_GivenOnInstallSucceeds_GivenNoSignerIsInstalledForThisPermissionId()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenModuleTypeIsSigner
        givenNoSignerIsInstalledForThisPermissionId
    {
        // it should set the signer for the permissionId
        // it should mark the permission hook as address1 if policies exist
        // it should emit ModuleInstalled event
    }

    function test_GivenModuleTypeIsUnsupported() external whenTheCallerIsTheEntryPointOrSelf {
        // it should revert with NotImplemented error
    }

    /*//////////////////////////////////////////////////////////////
                        UNAUTHORIZED CALLER TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should revert with Unauthorized error when caller is not EntryPoint or self
    function test_installModule_RevertWhen_CallerIsNotEntryPointAndNotSelf()
        external
        unitTest
        whenCallerIsNotEntryPoint
        whenCallerIsNotAccountItself
    {
        vm.expectRevert(Unauthorized.selector);
        kernel.installModule(1, address(newValidator), abi.encode(hex"", hex""));
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR INSTALLATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should install validator and mark as installed
    function test_WhenInstallingValidator() external unitTest whenCallerIsEntryPointOrSelf givenModuleTypeIsValidator {
        address validatorAddr = address(newValidator);

        kernel.installModule(1, validatorAddr, abi.encode(hex"", hex""));

        // Verify validator is installed (hook != address(0))
        assertEq(
            kernel.validationInfo(validatorToIdentifier(IValidator(validatorAddr))).hook,
            address(1),
            "Validator should be installed with hook=address(1)"
        );
    }

    /// @notice it should call onInstall on the validator
    function test_WhenInstallingValidator_CallsOnInstall()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsValidator
    {
        MockValidator mockValidator = new MockValidator();
        bytes memory moduleData = hex"cafebabe";

        kernel.installModule(1, address(mockValidator), abi.encode(moduleData, hex""));

        assertTrue(mockValidator.installCalled(), "onInstall should be called");
    }

    /// @notice it should set hook from internalData if provided
    function test_WhenInstallingValidator_WithHook()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsValidator
    {
        MockValidator mockValidator = new MockValidator();
        MockHook mockHook = new MockHook();

        // Install hook first
        kernel.installModule(4, address(mockHook), abi.encode(hex"", ""));

        // Internal data format: hook address + allowed selectors
        bytes memory internalData = abi.encodePacked(address(mockHook));

        kernel.installModule(1, address(mockValidator), abi.encode(hex"", internalData));

        assertEq(
            kernel.validationInfo(validatorToIdentifier(IValidator(address(mockValidator)))).hook,
            address(mockHook),
            "Validator should have custom hook"
        );
    }

    /// @notice it should revert when validator already installed
    function test_RevertWhen_ValidatorAlreadyInstalled()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsValidator
    {
        kernel.installModule(1, address(newValidator), abi.encode(hex"", hex""));

        vm.expectRevert();
        kernel.installModule(1, address(newValidator), abi.encode(hex"", hex""));
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTOR INSTALLATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should install executor and mark as installed
    function test_WhenInstallingExecutor() external unitTest whenCallerIsEntryPointOrSelf givenModuleTypeIsExecutor {
        kernel.installModule(2, address(executor), abi.encode(hex"", hex""));

        assertTrue(kernel.isModuleInstalled(2, address(executor), ""), "Executor should be installed");
    }

    /// @notice it should call onInstall on the executor
    function test_WhenInstallingExecutor_CallsOnInstall()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsExecutor
    {
        MockExecutor mockExecutor = new MockExecutor();
        bytes memory moduleData = hex"cafebabe";

        kernel.installModule(2, address(mockExecutor), abi.encode(moduleData, hex""));

        assertTrue(mockExecutor.installCalled(), "onInstall should be called");
    }

    /// @notice it should set hook from internalData if provided for executor
    function test_WhenInstallingExecutor_WithHook()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsExecutor
    {
        MockExecutor mockExecutor = new MockExecutor();
        MockHook mockHook = new MockHook();

        // Install hook first
        kernel.installModule(4, address(mockHook), abi.encode(hex"", ""));

        bytes memory internalData = abi.encodePacked(address(mockHook));

        kernel.installModule(2, address(mockExecutor), abi.encode(hex"", internalData));

        assertTrue(kernel.isModuleInstalled(2, address(mockExecutor), ""), "Executor should be installed with hook");
    }

    /*//////////////////////////////////////////////////////////////
                        FALLBACK INSTALLATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should install fallback handler for a selector
    function test_WhenInstallingFallback() external unitTest whenCallerIsEntryPointOrSelf givenModuleTypeIsFallback {
        MockFallback mockFallback = new MockFallback();
        bytes4 selector = bytes4(keccak256("customFunction()"));

        // internalData: selector + callType + hook
        bytes memory internalData = abi.encodePacked(selector, bytes1(0x00), address(1));

        kernel.installModule(3, address(mockFallback), abi.encode(hex"", internalData));

        assertTrue(
            kernel.isModuleInstalled(3, address(mockFallback), abi.encodePacked(selector)),
            "Fallback should be installed for selector"
        );
    }

    /// @notice it should set callType from internalData
    function test_WhenInstallingFallback_WithCallType()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsFallback
    {
        MockFallback mockFallback = new MockFallback();
        bytes4 selector = bytes4(keccak256("customFunction()"));

        // DELEGATECALL type = 0xff
        bytes memory internalData = abi.encodePacked(selector, bytes1(0xff), address(1));

        kernel.installModule(3, address(mockFallback), abi.encode(hex"", internalData));

        assertTrue(
            kernel.isModuleInstalled(3, address(mockFallback), abi.encodePacked(selector)),
            "Fallback should be installed with delegatecall type"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        HOOK INSTALLATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should install and enable hook
    function test_WhenInstallingHook() external unitTest whenCallerIsEntryPointOrSelf givenModuleTypeIsHook {
        MockHook mockHook = new MockHook();

        kernel.installModule(4, address(mockHook), abi.encode(hex"", ""));

        assertTrue(kernel.isModuleInstalled(4, address(mockHook), ""), "Hook should be enabled");
    }

    /// @notice it should call onInstall on the hook
    function test_WhenInstallingHook_CallsOnInstall()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsHook
    {
        MockHook mockHook = new MockHook();
        bytes memory moduleData = hex"cafebabe";

        kernel.installModule(4, address(mockHook), abi.encode(moduleData, ""));

        assertTrue(mockHook.installCalled(), "onInstall should be called");
    }

    /*//////////////////////////////////////////////////////////////
                        POLICY INSTALLATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should install policy for a permissionId
    function test_WhenInstallingPolicy() external unitTest whenCallerIsEntryPointOrSelf givenModuleTypeIsPolicy {
        bytes memory internalData = abi.encodePacked(permissionId);

        kernel.installModule(5, address(policy), abi.encode(hex"deadbeef", internalData));

        assertTrue(
            kernel.isModuleInstalled(5, address(policy), abi.encodePacked(permissionId)),
            "Policy should be installed for permissionId"
        );
    }

    /// @notice it should add policy to permissionId's policy list
    function test_WhenInstallingMultiplePolicies()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsPolicy
    {
        MockPolicy policy2 = new MockPolicy();
        bytes memory internalData = abi.encodePacked(permissionId);

        kernel.installModule(5, address(policy), abi.encode(hex"deadbeef", internalData));
        kernel.installModule(5, address(policy2), abi.encode(hex"deadbeef", internalData));

        assertTrue(
            kernel.isModuleInstalled(5, address(policy), abi.encodePacked(permissionId)),
            "First policy should be installed"
        );
        assertTrue(
            kernel.isModuleInstalled(5, address(policy2), abi.encodePacked(permissionId)),
            "Second policy should be installed"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        SIGNER INSTALLATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should install signer for a permissionId
    function test_WhenInstallingSigner() external unitTest whenCallerIsEntryPointOrSelf givenModuleTypeIsSigner {
        // First install policy
        kernel.installModule(5, address(policy), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));

        bytes memory internalData = abi.encodePacked(permissionId);

        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", internalData));

        assertTrue(
            kernel.isModuleInstalled(6, address(signer), abi.encodePacked(permissionId)),
            "Signer should be installed for permissionId"
        );
    }

    /// @notice it should set permission hook to address(1) when signer installed
    function test_WhenInstallingSigner_SetsPermissionHook()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenModuleTypeIsSigner
    {
        // Install policy first
        kernel.installModule(5, address(policy), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));

        // Install signer
        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));

        // Permission should now be usable (hook set)
        assertEq(
            kernel.validationInfo(permissionToIdentifier(permissionId)).hook,
            address(1),
            "Permission hook should be set to address(1)"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    UNSUPPORTED MODULE TYPE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should revert with NotImplemented for moduleType 0
    function test_RevertWhen_ModuleTypeIsZero() external unitTest whenCallerIsEntryPointOrSelf {
        vm.expectRevert(NotImplemented.selector);
        kernel.installModule(0, address(newValidator), abi.encode(hex"", hex""));
    }

    /// @notice it should revert with NotImplemented for moduleType >= 7
    function test_RevertWhen_ModuleTypeIsTooHigh() external unitTest whenCallerIsEntryPointOrSelf {
        vm.expectRevert(NotImplemented.selector);
        kernel.installModule(7, address(newValidator), abi.encode(hex"", hex""));
    }
}
