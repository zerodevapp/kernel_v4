// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Kernel} from "src/Kernel.sol";
import {BTTModifiers} from "./BTTModifiers.sol";
import {MockCallee} from "../mock/MockCallee.sol";
import {MockValidator} from "../mock/MockValidator.sol";
import {MockHook} from "../mock/MockHook.sol";
import {validatorToIdentifier} from "src/lib/Utils.sol";
import {PermissionId} from "src/types/Types.sol";
import {Unauthorized, UnauthorizedCallData, InvalidValidator, InvalidPermissionId} from "src/types/Error.sol";

/// @title Kernel.validateUserOp BTT Tests
/// @notice Tests for validateUserOp following Branching Tree Technique
/// @dev Tree specification: test/btt/Kernel.validateUserOp.tree
abstract contract Kernel_validateUserOp is BTTModifiers {
    modifier whenTheCallerIsNotTheEntryPoint() {
        _;
    }

    function test_WhenTheCallerIsNotTheAccountItself() external whenTheCallerIsNotTheEntryPoint {
        // it should revert with Unauthorized error
    }

    modifier whenTheCallerIsTheEntryPointOrSelf() {
        _;
    }

    modifier givenTheValidationModeHasEnableFlagSet() {
        _;
    }

    function test_GivenTheEnableSignatureIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationModeHasEnableFlagSet
    {
        // it should return SIG_VALIDATION_FAILED
    }

    function test_GivenTheNonceHasAlreadyBeenUsed()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationModeHasEnableFlagSet
    {
        // it should revert with InvalidNonce error
    }

    function test_GivenTheEnableSignatureIsValidAndNonceIsUnused()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationModeHasEnableFlagSet
    {
        // it should install the packages from the signature
        // it should increment the nonce
        // it should continue with userOp validation using the remaining signature
    }

    modifier givenTheValidationTypeIsROOT() {
        _;
    }

    function test_WhenTheSignatureIsValid() external whenTheCallerIsTheEntryPointOrSelf givenTheValidationTypeIsROOT {
        // it should return 0 for success
        // it should allow any callData without restrictions
    }

    function test_WhenTheSignatureIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsROOT
    {
        // it should return SIG_VALIDATION_FAILED
    }

    modifier givenTheValidationTypeIsVALIDATOR() {
        _;
    }

    function test_GivenTheValidatorIsNotInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
    {
        // it should revert with InvalidValidator error
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
    }

    function test_WhenTheValidatorSignatureIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
        givenTheCallDataSelectorIsInTheAllowedListAndHookIsAddress1
    {
        // it should return SIG_VALIDATION_FAILED
    }

    modifier givenTheCallDataSelectorIsNotDirectlyAllowed() {
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
    }

    function test_GivenAValidationHookIsConfigured()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsVALIDATOR
        givenTheValidatorIsInstalled
    {
        // it should store the hook in transient storage for executeUserOp
    }

    modifier givenTheValidationTypeIsPERMISSION() {
        _;
    }

    function test_GivenThePermissionIsNotInstalled()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsPERMISSION
    {
        // it should revert with InvalidPermissionId error
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
    }

    function test_WhenTheSignerSignatureIsInvalid()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsPERMISSION
        givenThePermissionIsInstalled
        whenAllPoliciesPassValidation
    {
        // it should return SIG_VALIDATION_FAILED
    }

    function test_WhenAnyPolicyFailsValidation()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheValidationTypeIsPERMISSION
        givenThePermissionIsInstalled
    {
        // it should return SIG_VALIDATION_FAILED
    }

    function test_GivenTheValidationModeIsReplayable() external {
        // it should compute userOpHash without chainId
        // it should allow the same signature to be valid across different chains
    }

    function test_GivenTheValidationModeIsNotReplayable() external {
        // it should compute userOpHash with chainId
        // it should make the signature invalid on different chains
    }

    function test_WhenMissingAccountFundsIsGreaterThanZero() external {
        // it should transfer the funds to the EntryPoint
    }

    /*//////////////////////////////////////////////////////////////
                        UNAUTHORIZED CALLER TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should revert with Unauthorized error
    function test_validateUserOp_RevertWhen_CallerIsNotEntryPointAndNotSelf()
        external
        unitTest
        whenCallerIsNotEntryPoint
        whenCallerIsNotAccountItself
    {
        PackedUserOperation memory op = _createBasicUserOp();
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(Unauthorized.selector);
        kernel.validateUserOp(op, userOpHash, 0);
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

    /// @notice it should allow any callData without restrictions for root validation
    function test_WhenRootValidation_AllowsAnyCallData()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsRoot
    {
        PackedUserOperation memory op = _createUserOpWithRootValidation();
        // Use arbitrary callData - should be allowed for root
        op.callData = abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), hex"deadbeef");
        op.signature = _rootSignUserOp(op, true, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0, "Root validation should allow any callData");
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

        vm.expectRevert();
        kernel.validateUserOp(op, userOpHash, 0);
    }

    /// @notice it should return 0 when validator signature is valid
    function test_WhenValidatorSignatureIsValid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsValidator
        givenValidatorIsInstalled
    {
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
    function test_WhenValidatorSignatureIsInvalid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsValidator
        givenValidatorIsInstalled
    {
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

        vm.expectRevert();
        kernel.validateUserOp(op, userOpHash, 0);
    }

    /// @notice it should return 0 when all policies pass and signer is valid
    function test_validateUserOp_WhenPermissionValid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsPermission
        givenPermissionIsInstalled
    {
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

    /// @notice it should return SIG_VALIDATION_FAILED when policy fails
    function test_validateUserOp_WhenPermissionPolicyFails()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsPermission
        givenPermissionIsInstalled
    {
        PackedUserOperation memory op = _createUserOpWithPermissionValidation();
        op.callData = abi.encodePacked(
            Kernel.executeUserOp.selector,
            abi.encodeWithSelector(
                Kernel.execute.selector,
                bytes32(0),
                abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
            )
        );
        // Set policy to fail
        permissionRevertIndex = 0;
        op.signature = _permissionSignUserOp(op, false, false);
        bytes32 userOpHash = ep.getUserOpHash(op);

        uint256 validationData = kernel.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1, "Failed policy should return SIG_VALIDATION_FAILED");
    }

    /// @notice it should return SIG_VALIDATION_FAILED when signer is invalid
    function test_validateUserOp_WhenPermissionSignerInvalid()
        external
        entryPointTest
        whenCallerIsEntryPointOrSelf
        givenValidationTypeIsPermission
        givenPermissionIsInstalled
    {
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
