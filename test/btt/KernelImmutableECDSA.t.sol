// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Kernel} from "src/Kernel.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {KernelImmutableECDSA} from "src/KernelImmutableECDSA.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {Install} from "src/types/Structs.sol";
import {MockValidator} from "../mock/MockValidator.sol";
import {MockExecutor} from "../mock/MockExecutor.sol";
import {ERC1271_MAGICVALUE, ERC1271_INVALID} from "src/types/Constants.sol";
import {InvalidInitialization} from "src/types/Error.sol";
import {EntryPointLib} from "../utils/EntryPointLib.sol";
import {IValidator} from "src/interfaces/IERC7579Modules.sol";
import {validatorToIdentifier} from "src/lib/Utils.sol";

/// @title KernelImmutableECDSA BTT Tests
/// @notice Tests for KernelImmutableECDSA variant following Branching Tree Technique
/// @dev Tree specification: test/btt/KernelImmutableECDSA.tree
contract KernelImmutableECDSA_Test is Test {
    IEntryPoint ep;
    KernelFactory factory;
    KernelUUPS uups;
    KernelImmutableECDSA immutableEcdsaImpl;

    address ecdsaSigner;
    uint256 ecdsaSignerKey;

    MockValidator mockValidator;
    MockExecutor mockExecutor;

    function setUp() public {
        ep = EntryPointLib.deploy();

        uups = new KernelUUPS(ep);
        immutableEcdsaImpl = new KernelImmutableECDSA(ep);
        factory = new KernelFactory(uups, immutableEcdsaImpl);

        (ecdsaSigner, ecdsaSignerKey) = makeAddrAndKey("ECDSASigner");
        mockValidator = new MockValidator();
        mockValidator.sudoSetSuccess(true);
        mockExecutor = new MockExecutor();
    }

    /*//////////////////////////////////////////////////////////////
                    _verifyFallbackSignature TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WhenVerifyFallbackSignatureReceivesAValidSignatureFromTheImmutableSigner() external {
        // it should return validation success
        // Deploy a KernelImmutableECDSA with ecdsaSigner as the immutable arg
        Kernel kernel = _deployECDSAKernel(ecdsaSigner);

        // The fallback signature path: validateUserOp with root = bytes21(0)
        PackedUserOperation memory op = _buildUserOp(address(kernel));
        bytes32 opHash = ep.getUserOpHash(op);
        op.signature = _signHash(ecdsaSignerKey, opHash);

        vm.prank(address(ep));
        uint256 validationData = kernel.validateUserOp(op, opHash, 0);
        assertEq(validationData, 0, "Valid immutable signer should return success");
    }

    function test_WhenVerifyFallbackSignatureReceivesASignatureFromADifferentSigner() external {
        // it should return validation failed
        Kernel kernel = _deployECDSAKernel(ecdsaSigner);

        PackedUserOperation memory op = _buildUserOp(address(kernel));
        bytes32 opHash = ep.getUserOpHash(op);

        (, uint256 wrongKey) = makeAddrAndKey("WrongSigner");
        op.signature = _signHash(wrongKey, opHash);

        vm.prank(address(ep));
        uint256 validationData = kernel.validateUserOp(op, opHash, 0);
        assertEq(validationData, 1, "Wrong signer should return failure");
    }

    function test_WhenVerifyFallbackSignatureReceivesAMalformedSignature() external {
        // it should return validation failed
        Kernel kernel = _deployECDSAKernel(ecdsaSigner);

        PackedUserOperation memory op = _buildUserOp(address(kernel));
        bytes32 opHash = ep.getUserOpHash(op);
        op.signature = hex"deadbeef";

        vm.prank(address(ep));
        uint256 validationData = kernel.validateUserOp(op, opHash, 0);
        assertEq(validationData, 1, "Malformed signature should return failure");
    }

    /*//////////////////////////////////////////////////////////////
                    _fallbackValidatorAvailable TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WhenFallbackValidatorAvailableIsChecked() external {
        // it should return true
        // We prove _fallbackValidatorAvailable returns true by showing that
        // setRoot(ValidationId.wrap(bytes21(0))) does NOT revert.
        // If _fallbackValidatorAvailable were false, setRoot with zero vId would revert
        // with InvalidRootValidation.
        Kernel kernel = _deployECDSAKernel(ecdsaSigner);

        // The fact that validateUserOp works with root=bytes21(0) proves the function returns true
        PackedUserOperation memory op = _buildUserOp(address(kernel));
        bytes32 opHash = ep.getUserOpHash(op);
        op.signature = _signHash(ecdsaSignerKey, opHash);

        vm.prank(address(ep));
        uint256 validationData = kernel.validateUserOp(op, opHash, 0);
        assertEq(validationData, 0, "Fallback validator should be available");
    }

    /*//////////////////////////////////////////////////////////////
                    _initialize TESTS
    //////////////////////////////////////////////////////////////*/

    function test_When_initializeIsCalledWithEmptyPackages() external {
        // it should not revert and not set root
        // KernelImmutableECDSA._initialize does NOT call _setRoot and does NOT require packages.length > 0
        Install[] memory emptyPackages = new Install[](0);

        // Deploy with empty packages - should succeed because _initialize just calls _install
        Kernel kernel = Kernel(payable(factory.deployECDSA(ecdsaSigner, emptyPackages, 100)));
        // Kernel is deployed and initialized without reverting
        assertTrue(address(kernel) != address(0), "Kernel should be deployed with empty packages");
    }

    function test_When_initializeIsCalledWithPackages() external {
        // it should install packages without requiring root
        // KernelImmutableECDSA._initialize calls _install(packages) without _setRoot
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 2, module: address(mockExecutor), moduleData: hex"", internalData: hex""});

        Kernel kernel = Kernel(payable(factory.deployECDSA(ecdsaSigner, packages, 101)));

        // Executor should be installed
        assertTrue(
            kernel.isModuleInstalled(2, address(mockExecutor), ""), "Executor should be installed via _initialize"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    initialize (initializer modifier) TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WhenInitializeIsCalledForTheFirstTime() external {
        // it should succeed and initialize
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(mockValidator), moduleData: hex"", internalData: hex""});

        // Deploy deploys + initializes atomically via factory
        Kernel kernel = Kernel(payable(factory.deployECDSA(ecdsaSigner, packages, 200)));
        assertTrue(address(kernel) != address(0), "Kernel should deploy successfully");
    }

    function test_WhenInitializeIsCalledASecondTime() external {
        // it should revert with InvalidInitialization
        Install[] memory packages = new Install[](0);
        Kernel kernel = Kernel(payable(factory.deployECDSA(ecdsaSigner, packages, 300)));

        // Trying to initialize again should revert because of the `initializer` modifier
        Install[] memory newPackages = new Install[](1);
        newPackages[0] =
            Install({moduleType: 1, module: address(mockValidator), moduleData: hex"", internalData: hex""});

        vm.expectRevert(InvalidInitialization.selector);
        kernel.initialize(newPackages);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployECDSAKernel(address signer) internal returns (Kernel) {
        Install[] memory packages = new Install[](0);
        return Kernel(payable(factory.deployECDSA(signer, packages, _nextNonce())));
    }

    uint256 private _nonce = 1000;

    function _nextNonce() internal returns (uint256) {
        return _nonce++;
    }

    function _buildUserOp(address sender) internal view returns (PackedUserOperation memory op) {
        op.sender = sender;
        // nonce with ROOT validation type (0x00) and zero vId (triggers fallback path)
        uint192 key = uint192(bytes24(abi.encodePacked(uint8(0), bytes1(0), bytes20(0), bytes2(0x00))));
        op.nonce = ep.getNonce(sender, key);
        op.callData = abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), "");
        op.accountGasLimits = bytes32(uint256(100000) << 128 | uint256(100000));
        op.preVerificationGas = 100000;
        op.gasFees = bytes32(uint256(1) << 128 | uint256(1));
    }

    function _signHash(uint256 privateKey, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }
}
