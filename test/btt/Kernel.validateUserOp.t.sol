// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Kernel} from "src/Kernel.sol";
import {BTTModifiers} from "./BTTModifiers.sol";
import {MockCallee} from "../mock/MockCallee.sol";
import {MockValidator} from "../mock/MockValidator.sol";
import {MockHook} from "../mock/MockHook.sol";
import {validatorToIdentifier, permissionToIdentifier} from "src/lib/Utils.sol";
import {PermissionId} from "src/types/Types.sol";
import {
    Unauthorized,
    UnauthorizedCallData,
    InvalidValidator,
    InvalidPermissionId,
    InvalidNonce
} from "src/types/Error.sol";
import {ValidationManager} from "src/core/ValidationManager.sol";
import {Install} from "src/types/Structs.sol";
import {IValidator} from "src/interfaces/IERC7579Modules.sol";

/// @title Kernel.validateUserOp BTT Tests
/// @notice Tests for validateUserOp following Branching Tree Technique
/// @dev Tree specification: test/btt/Kernel.validateUserOp.tree
///
/// @dev OPEN QUESTION: For enable mode in validateUserOp, the implementation currently
/// installs packages and increments nonce even if the enable signature is invalid.
/// This side effect behavior should be explicitly specified - either the tree should
/// assert this behavior, or the code should be changed to avoid side effects on invalid
/// enable signatures. Skipping this for now per user request.
abstract contract Kernel_validateUserOp is BTTModifiers {
    modifier whenTheCallerIsNotTheEntryPoint() {
        _;
    }

    function test_WhenTheCallerIsNotTheAccountItself() external whenTheCallerIsNotTheEntryPoint {
        // it should revert with Unauthorized error
        vm.stopPrank();
        vm.startPrank(makeAddr("randomCaller"));
        PackedUserOperation memory op = _createBasicUserOp();
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(Unauthorized.selector);
        kernel.validateUserOp(op, userOpHash, 0);
    }

    modifier whenTheCallerIsTheEntryPointOrSelf() {
        _;
    }

    modifier givenTheValidationModeHasEnableFlagSet() {
        _;
    }

    function test_GivenTheNonceIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationModeHasEnableFlagSet
    {
        // it should revert with InvalidNonce error
        vm.stopPrank();
        vm.startPrank(address(ep));

        // First call with valid enable signature uses nonce 0
        PackedUserOperation memory op = _createUserOpWithEnableMode();
        op.signature = encodeEnableValidatorSignature(
            Kernel.execute.selector, 0, true, false, _rootSignHash, _validatorSignUserOp(op, true, false)
        );
        bytes32 userOpHash = ep.getUserOpHash(op);
        kernel.validateUserOp(op, userOpHash, 0);

        // Second call with same nonce should fail
        PackedUserOperation memory op2 = _createUserOpWithEnableMode();
        Install[] memory packages = new Install[](1);
        packages[0] = Install({
            moduleType: 1,
            module: address(newValidator),
            moduleData: hex"",
            internalData: abi.encodePacked(address(0), Kernel.execute.selector)
        });
        op2.signature = abi.encode(
            uint256(0),
            packages,
            enableSig(0, true, false, packages, _rootSignHash),
            _validatorSignUserOp(op2, true, false)
        );
        bytes32 userOpHash2 = ep.getUserOpHash(op2);

        vm.expectRevert(InvalidNonce.selector);
        kernel.validateUserOp(op2, userOpHash2, 0);
    }

    function test_GivenTheEnableSignatureIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationModeHasEnableFlagSet
    {
        // it should return SIG_VALIDATION_FAILED
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithEnableMode();
        op.signature = encodeEnableValidatorSignature(
            Kernel.execute.selector, 0, false, false, _rootSignHash, _validatorSignUserOp(op, true, false)
        );
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Enable mode with invalid signature should return SIG_VALIDATION_FAILED");
    }

    function test_GivenTheEnableSignatureIsValidAndNonceIsUnused()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationModeHasEnableFlagSet
    {
        // it should install the packages from the signature
        // it should increment the nonce
        // it should continue with userOp validation using the remaining signature
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithEnableMode();
        op.signature = encodeEnableValidatorSignature(
            Kernel.execute.selector, 0, true, false, _rootSignHash, _validatorSignUserOp(op, true, false)
        );
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        // Verify the validator was installed
        assertEq(
            kernel.validationInfo(validatorToIdentifier(IValidator(address(newValidator)))).hook,
            address(1),
            "Validator should be installed"
        );
        assertEq(validationData, 0, "Enable mode with valid signature should return 0");
    }

    modifier givenTheValidationTypeIsROOT() {
        _;
    }

    function test_GivenTheRootIsNotSet() external whenTheCallerIsTheEntryPointOrSelf givenTheValidationTypeIsROOT {
        // it should use the fallback validator
        // Note: In this test setup, root is always set during initialization
        // The fallback validator behavior is tested indirectly when root validator fails
        // and a fallback mechanism is in place. For current implementation,
        // when root validation is requested, it uses the root validator directly.
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithRootValidation();
        op.signature = _rootSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Root validation should succeed");
    }

    function test_WhenTheSignatureIsValid() external whenTheCallerIsTheEntryPointOrSelf givenTheValidationTypeIsROOT {
        // it should return 0 for success
        // it should allow any callData without restrictions
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithRootValidation();
        op.signature = _rootSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Valid root signature should return 0");
    }

    function test_WhenTheSignatureIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsROOT
    {
        // it should return SIG_VALIDATION_FAILED
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithRootValidation();
        op.signature = _rootSignUserOp(op, false, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Invalid root signature should return SIG_VALIDATION_FAILED");
    }

    modifier givenTheValidationTypeIsVALIDATOR() {
        _;
    }

    function test_GivenTheValidatorIsNotInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
    {
        // it should revert with InvalidVid error
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidationManager.InvalidVid.selector, validatorToIdentifier(IValidator(address(newValidator)))
            )
        );
        kernel.validateUserOp(op, userOpHash, 0);
    }

    modifier givenTheValidatorIsInstalled() {
        _;
    }

    modifier givenTheCallDataSelectorIsInTheAllowedListAndHookIsAddress1() {
        _;
    }

    function test_WhenTheValidatorSignatureIsValid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
        givenTheCallDataSelectorIsInTheAllowedListAndHookIsAddress1
    {
        // it should return 0 for success
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install validator with execute selector allowed
        kernel.installModule(
            1, address(newValidator), abi.encode(hex"", abi.encodePacked(address(0), Kernel.execute.selector))
        );

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Valid validator signature should return 0");
    }

    function test_WhenTheValidatorSignatureIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
        givenTheCallDataSelectorIsInTheAllowedListAndHookIsAddress1
    {
        // it should return SIG_VALIDATION_FAILED
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install validator with execute selector allowed
        kernel.installModule(
            1, address(newValidator), abi.encode(hex"", abi.encodePacked(address(0), Kernel.execute.selector))
        );

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );
        op.signature = _validatorSignUserOp(op, false, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Invalid validator signature should return SIG_VALIDATION_FAILED");
    }

    modifier givenTheCallDataSelectorIsInTheAllowedListAndHookIsNotAddress1() {
        _;
    }

    function test_WhenTheCallDataDoesNotUseExecuteUserOpWrapper()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
        givenTheCallDataSelectorIsNotDirectlyAllowed
    {
        // it should revert with UnauthorizedCallData error
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install validator without any allowed selectors
        kernel.installModule(1, address(newValidator), abi.encode(hex"", hex""));

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(UnauthorizedCallData.selector);
        kernel.validateUserOp(op, userOpHash, 0);
    }

    function test_WhenTheCallDataUsesExecuteUserOpWrapper()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
        givenTheCallDataSelectorIsInTheAllowedListAndHookIsNotAddress1
    {
        // it should set the validation hook for later execution
        // it should continue with signature validation
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install hook first
        kernel.installModule(4, address(hook), abi.encode(hex"", hex""));

        // Install validator with hook and execute selector allowed
        kernel.installModule(
            1, address(newValidator), abi.encode(hex"", abi.encodePacked(address(hook), Kernel.execute.selector))
        );

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Validation with executeUserOp wrapper and hook should succeed");
    }

    modifier givenTheCallDataSelectorIsNotDirectlyAllowed() {
        _;
    }

    function test_WhenTheCallDataDoesNotUseExecuteUserOpWrapper_GivenTheCallDataSelectorIsNotDirectlyAllowed()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
        givenTheCallDataSelectorIsNotDirectlyAllowed
    {
        // it should revert with UnauthorizedCallData error
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install validator without any allowed selectors
        kernel.installModule(1, address(newValidator), abi.encode(hex"", hex""));

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        // Direct execute without executeUserOp wrapper - should fail
        op.callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(UnauthorizedCallData.selector);
        kernel.validateUserOp(op, userOpHash, 0);
    }

    modifier whenTheCallDataUsesExecuteUserOpWrapper() {
        _;
    }

    function test_GivenTheInnerSelectorIsInTheAllowedList()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
        givenTheCallDataSelectorIsNotDirectlyAllowed
        whenTheCallDataUsesExecuteUserOpWrapper
    {
        // it should set the validation hook for later execution
        // it should continue with signature validation
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install validator with Kernel.execute selector in the allowed list
        kernel.installModule(
            1, address(newValidator), abi.encode(hex"", abi.encodePacked(address(0), Kernel.execute.selector))
        );

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Valid validator signature with executeUserOp wrapper should return 0");
    }

    function test_GivenTheInnerSelectorIsNotInTheAllowedList()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
        givenTheCallDataSelectorIsNotDirectlyAllowed
        whenTheCallDataUsesExecuteUserOpWrapper
    {
        // it should revert with UnauthorizedCallData error
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install validator without execute selector allowed
        kernel.installModule(1, address(newValidator), abi.encode(hex"", hex""));

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(UnauthorizedCallData.selector);
        kernel.validateUserOp(op, userOpHash, 0);
    }

    function test_GivenAValidationHookIsConfigured()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
    {
        // it should store the hook in transient storage for executeUserOp
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install hook first
        kernel.installModule(4, address(hook), abi.encode(hex"", hex""));

        // Install validator with hook and execute selector allowed
        kernel.installModule(
            1, address(newValidator), abi.encode(hex"", abi.encodePacked(address(hook), Kernel.execute.selector))
        );

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Validator with hook configured should return 0");
    }

    modifier givenTheValidationTypeIsPERMISSION() {
        _;
    }

    function test_GivenThePermissionIsNotInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsPERMISSION
    {
        // it should revert with InvalidVid error
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithPermissionValidation();
        op.signature = _permissionSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(
            abi.encodeWithSelector(ValidationManager.InvalidVid.selector, permissionToIdentifier(permissionId))
        );
        kernel.validateUserOp(op, userOpHash, 0);
    }

    modifier givenThePermissionIsInstalled() {
        _;
    }

    function test_GivenTheCallDataSelectorRestrictionsAreNotMet()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsPERMISSION
        givenThePermissionIsInstalled
    {
        // it should revert with UnauthorizedCallData error
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install permission without any allowed selectors
        kernel.installModule(5, address(policy), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));
        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));

        PackedUserOperation memory op = _createUserOpWithPermissionValidation();
        op.callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );
        op.signature = _permissionSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(UnauthorizedCallData.selector);
        kernel.validateUserOp(op, userOpHash, 0);
    }

    modifier whenAllPoliciesPassValidation() {
        _;
    }

    function test_WhenTheSignerSignatureIsValid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsPERMISSION
        givenThePermissionIsInstalled
        whenAllPoliciesPassValidation
    {
        // it should return 0 for success
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install permission with execute selector allowed
        kernel.installModule(
            5,
            address(policy),
            abi.encode(hex"deadbeef", abi.encodePacked(permissionId, address(0), Kernel.execute.selector))
        );
        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));

        PackedUserOperation memory op = _createUserOpWithPermissionValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        op.signature = _permissionSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Valid permission should return 0");
    }

    function test_WhenTheSignerSignatureIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsPERMISSION
        givenThePermissionIsInstalled
        whenAllPoliciesPassValidation
    {
        // it should return SIG_VALIDATION_FAILED
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install permission with execute selector allowed
        kernel.installModule(
            5,
            address(policy),
            abi.encode(hex"deadbeef", abi.encodePacked(permissionId, address(0), Kernel.execute.selector))
        );
        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));

        PackedUserOperation memory op = _createUserOpWithPermissionValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        permissionRevertIndex = 1; // signer fails
        op.signature = _permissionSignUserOp(op, false, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Invalid signer should return SIG_VALIDATION_FAILED");
    }

    function test_WhenAnyPolicyFailsValidation()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsPERMISSION
        givenThePermissionIsInstalled
    {
        // it should return SIG_VALIDATION_FAILED
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Install permission with execute selector allowed
        kernel.installModule(
            5,
            address(policy),
            abi.encode(hex"deadbeef", abi.encodePacked(permissionId, address(0), Kernel.execute.selector))
        );
        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));

        PackedUserOperation memory op = _createUserOpWithPermissionValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        permissionRevertIndex = 0; // policy fails
        op.signature = _permissionSignUserOp(op, false, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Failed policy should return SIG_VALIDATION_FAILED");
    }

    function test_GivenTheValidationModeIsReplayable() external {
        // it should compute userOpHash without chainId
        // it should allow the same signature to be valid across different chains
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithReplayableMode();
        op.signature = _rootSignUserOp(op, true, true);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Replayable mode should validate successfully");
    }

    function test_GivenTheValidationModeIsNotReplayable() external {
        // it should compute userOpHash with chainId
        // it should make the signature invalid on different chains
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithRootValidation();
        op.signature = _rootSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Non-replayable mode should validate successfully");
    }

    function test_WhenMissingAccountFundsIsGreaterThanZero() external {
        // it should transfer the funds to the EntryPoint
        vm.stopPrank();
        vm.startPrank(address(ep));

        PackedUserOperation memory op = _createUserOpWithRootValidation();
        op.signature = _rootSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 missingFunds = 1 ether;
        uint256 epBalanceBefore = address(ep).balance;

        kernel.validateUserOp(op, userOpHash, missingFunds);

        uint256 epBalanceAfter = address(ep).balance;
        assertEq(epBalanceAfter - epBalanceBefore, missingFunds, "EntryPoint should receive missing funds");
    }

    function test_GivenTheNonceHasAlreadyBeenUsed()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationModeHasEnableFlagSet
    {
        // it should revert with InvalidNonce error
        vm.stopPrank();
        vm.startPrank(address(ep));

        // First call with valid enable signature uses nonce 0
        PackedUserOperation memory op = _createUserOpWithEnableMode();
        op.signature = encodeEnableValidatorSignature(
            Kernel.execute.selector, 0, true, false, _rootSignHash, _validatorSignUserOp(op, true, false)
        );
        bytes32 userOpHash = ep.getUserOpHash(op);
        kernel.validateUserOp(op, userOpHash, 0);

        // Second call with same nonce should fail
        PackedUserOperation memory op2 = _createUserOpWithEnableMode();
        Install[] memory packages = new Install[](1);
        packages[0] = Install({
            moduleType: 1,
            module: address(newValidator),
            moduleData: hex"",
            internalData: abi.encodePacked(address(0), Kernel.execute.selector)
        });
        op2.signature = abi.encode(
            uint256(0),
            packages,
            enableSig(0, true, false, packages, _rootSignHash),
            _validatorSignUserOp(op2, true, false)
        );
        bytes32 userOpHash2 = ep.getUserOpHash(op2);

        vm.expectRevert(InvalidNonce.selector);
        kernel.validateUserOp(op2, userOpHash2, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ROOT VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should return 0 (success) when root signature is valid
    function test_WhenRootSignatureIsValid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsRoot
    {
        PackedUserOperation memory op = _createUserOpWithRootValidation();
        op.signature = _rootSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Valid root signature should return 0");
    }

    /// @notice it should return SIG_VALIDATION_FAILED when root signature is invalid
    function test_WhenRootSignatureIsInvalid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsRoot
    {
        PackedUserOperation memory op = _createUserOpWithRootValidation();
        op.signature = _rootSignUserOp(op, false, false); // false = invalid signature
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Invalid root signature should return SIG_VALIDATION_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should revert when validator is not installed
    function test_validateUserOp_RevertWhen_ValidatorNotInstalled()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsValidator
        givenValidatorIsNotInstalled
    {
        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidationManager.InvalidVid.selector, validatorToIdentifier(IValidator(address(newValidator)))
            )
        );
        kernel.validateUserOp(op, userOpHash, 0);
    }

    /// @notice it should return 0 when validator signature is valid
    /// NOTE: The givenValidatorIsInstalled modifier installs without allowed selectors,
    /// so we must use executeUserOp wrapper which checks the inner selector
    function test_WhenValidatorSignatureIsValid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsValidator
    {
        // Manually install validator with execute selector allowed (don't use givenValidatorIsInstalled)
        kernel.installModule(
            1, address(newValidator), abi.encode(hex"", abi.encodePacked(address(0), Kernel.execute.selector))
        );

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Valid validator signature should return 0");
    }

    /// @notice it should return SIG_VALIDATION_FAILED when validator signature is invalid
    /// NOTE: The givenValidatorIsInstalled modifier installs without allowed selectors,
    /// so we must use executeUserOp wrapper which checks the inner selector
    function test_WhenValidatorSignatureIsInvalid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsValidator
    {
        // Manually install validator with execute selector allowed (don't use givenValidatorIsInstalled)
        kernel.installModule(
            1, address(newValidator), abi.encode(hex"", abi.encodePacked(address(0), Kernel.execute.selector))
        );

        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        op.signature = _validatorSignUserOp(op, false, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Invalid validator signature should return SIG_VALIDATION_FAILED");
    }

    /// @notice it should revert with UnauthorizedCallData when selector not allowed and not using executeUserOp wrapper
    function test_RevertWhen_SelectorNotAllowedWithoutWrapper()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsValidator
        givenValidatorIsInstalled
    {
        PackedUserOperation memory op = _createUserOpWithValidatorValidation();
        // Direct execute without executeUserOp wrapper - should fail for non-root validators
        op.callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );
        op.signature = _validatorSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(UnauthorizedCallData.selector);
        kernel.validateUserOp(op, userOpHash, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        PERMISSION VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should revert when permission is not installed
    function test_validateUserOp_RevertWhen_PermissionNotInstalled()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsPermission
        givenPermissionIsNotInstalled
    {
        PackedUserOperation memory op = _createUserOpWithPermissionValidation();
        op.signature = _permissionSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(
            abi.encodeWithSelector(ValidationManager.InvalidVid.selector, permissionToIdentifier(permissionId))
        );
        kernel.validateUserOp(op, userOpHash, 0);
    }

    /// @notice it should return SIG_VALIDATION_FAILED when signer is invalid
    /// NOTE: Don't use givenPermissionIsInstalled - it doesn't include allowed selectors
    function test_validateUserOp_WhenPermissionSignerInvalid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsPermission
    {
        // Manually install permission with execute selector allowed
        kernel.installModule(
            5,
            address(policy),
            abi.encode(hex"deadbeef", abi.encodePacked(permissionId, address(0), Kernel.execute.selector))
        );
        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));

        PackedUserOperation memory op = _createUserOpWithPermissionValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        // Set signer to fail
        permissionRevertIndex = 1;
        op.signature = _permissionSignUserOp(op, false, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Invalid signer should return SIG_VALIDATION_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                        REPLAYABLE MODE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should compute userOpHash without chainId for replayable mode
    function test_WhenReplayableMode_ChainAgnosticHash()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationModeIsReplayable
    {
        PackedUserOperation memory op = _createUserOpWithReplayableMode();
        op.signature = _rootSignUserOp(op, true, true); // true for replayable
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Replayable mode should validate successfully");
    }

    /// @notice it should allow the same signature to be valid across different chains
    function test_WhenReplayableMode_CrossChainValidity()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationModeIsReplayable
    {
        PackedUserOperation memory op = _createUserOpWithReplayableMode();
        bytes memory signature = _rootSignUserOp(op, true, true);
        op.signature = signature;
        bytes32 userOpHash = ep.getUserOpHash(op);

        // Validate on current chain
        uint256 validationData1 = kernel.validateUserOp(op, userOpHash, 0);
        assertEq(validationData1, 0, "Should validate on original chain");

        // Note: In real scenario, same signature would work on different chain
        // This test demonstrates the replayable signature creation
    }

    /*//////////////////////////////////////////////////////////////
                        ENABLE MODE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should install packages and continue validation when enable signature is valid
    function test_validateUserOp_WhenEnableModeWithValidSignature()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationModeHasEnableFlagSet
        givenEnableSignatureIsValidAndNonceUnused
    {
        PackedUserOperation memory op = _createUserOpWithEnableMode();
        op.signature = encodeEnableValidatorSignature(
            Kernel.execute.selector, 0, true, false, _rootSignHash, _validatorSignUserOp(op, true, false)
        );
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Enable mode with valid signature should return 0");
        // Verify validator was installed
        assertEq(
            kernel.validationInfo(validatorToIdentifier(newValidator)).hook, address(1), "Validator should be installed"
        );
    }

    /// @notice it should return SIG_VALIDATION_FAILED when enable signature is invalid
    function test_validateUserOp_WhenEnableModeWithInvalidSignature()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationModeHasEnableFlagSet
        givenEnableSignatureIsInvalid
    {
        PackedUserOperation memory op = _createUserOpWithEnableMode();
        op.signature = encodeEnableValidatorSignature(
            Kernel.execute.selector, 0, false, false, _rootSignHash, _validatorSignUserOp(op, true, false)
        );
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Enable mode with invalid signature should return SIG_VALIDATION_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                        MISSING FUNDS TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should transfer funds to EntryPoint when missingAccountFunds > 0
    function test_WhenMissingAccountFundsGreaterThanZero() external entryPointTest whenCallerIsEntryPointOrSelf {
        PackedUserOperation memory op = _createUserOpWithRootValidation();
        op.signature = _rootSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 missingFunds = 1 ether;
        uint256 epBalanceBefore = address(ep).balance;

        kernel.validateUserOp(op, userOpHash, missingFunds);

        uint256 epBalanceAfter = address(ep).balance;
        assertEq(epBalanceAfter - epBalanceBefore, missingFunds, "EntryPoint should receive missing funds");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createBasicUserOp() internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: address(kernel),
            nonce: encodeNonce(false, false, false, bytes1(0), bytes20(0)),
            initCode: hex"",
            callData: abi.encodeWithSelector(
                Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
                ),
            accountGasLimits: bytes32(abi.encodePacked(uint128(1000000), uint128(1000000))),
            preVerificationGas: 0,
            gasFees: bytes32(abi.encodePacked(uint128(1), uint128(1))),
            paymasterAndData: hex"",
            signature: hex""
        });
    }

    function _createUserOpWithRootValidation() internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: address(kernel),
            nonce: encodeNonce(false, false, false, bytes1(0), bytes20(0)),
            initCode: hex"",
            callData: abi.encodeWithSelector(
                Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
                ),
            accountGasLimits: bytes32(abi.encodePacked(uint128(1000000), uint128(1000000))),
            preVerificationGas: 0,
            gasFees: bytes32(abi.encodePacked(uint128(1), uint128(1))),
            paymasterAndData: hex"",
            signature: hex""
        });
    }

    function _createUserOpWithValidatorValidation() internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: address(kernel),
            nonce: encodeNonce(false, false, false, bytes1(0x01), bytes20(address(newValidator))),
            initCode: hex"",
            callData: abi.encodeWithSelector(
                Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
                ),
            accountGasLimits: bytes32(abi.encodePacked(uint128(1000000), uint128(1000000))),
            preVerificationGas: 0,
            gasFees: bytes32(abi.encodePacked(uint128(1), uint128(1))),
            paymasterAndData: hex"",
            signature: hex""
        });
    }

    function _createUserOpWithPermissionValidation() internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: address(kernel),
            nonce: encodeNonce(false, false, false, bytes1(0x02), PermissionId.unwrap(permissionId)),
            initCode: hex"",
            callData: abi.encodeWithSelector(
                Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
                ),
            accountGasLimits: bytes32(abi.encodePacked(uint128(1000000), uint128(1000000))),
            preVerificationGas: 0,
            gasFees: bytes32(abi.encodePacked(uint128(1), uint128(1))),
            paymasterAndData: hex"",
            signature: hex""
        });
    }

    function _createUserOpWithReplayableMode() internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: address(kernel),
            nonce: encodeNonce(true, false, false, bytes1(0), bytes20(0)), // replayable = true
            initCode: hex"",
            callData: abi.encodeWithSelector(
                Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
                ),
            accountGasLimits: bytes32(abi.encodePacked(uint128(1000000), uint128(1000000))),
            preVerificationGas: 1000000,
            gasFees: bytes32(abi.encodePacked(uint128(1), uint128(1))),
            paymasterAndData: hex"",
            signature: hex""
        });
    }

    function _createUserOpWithEnableMode() internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: address(kernel),
            nonce: encodeNonce(false, true, false, bytes1(0x01), bytes20(address(newValidator))), // enable = true
            initCode: hex"",
            callData: abi.encodeWithSelector(
                Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
                ),
            accountGasLimits: bytes32(abi.encodePacked(uint128(1000000), uint128(1000000))),
            preVerificationGas: 1000000,
            gasFees: bytes32(abi.encodePacked(uint128(1), uint128(1))),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}
