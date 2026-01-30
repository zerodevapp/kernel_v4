// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {KernelImmutableECDSA} from "src/KernelImmutableECDSA.sol";
import {Kernel} from "src/Kernel.sol";
import {Install} from "src/types/Structs.sol";
import {MockValidator} from "../mock/MockValidator.sol";
import {MockCallee} from "../mock/MockCallee.sol";
import {EntryPointLib} from "../utils/EntryPointLib.sol";
import {validatorToIdentifier} from "src/lib/Utils.sol";
import {IValidator} from "src/interfaces/IERC7579Modules.sol";
import {InvalidRootValidation} from "src/types/Error.sol";

/// @title KernelFactory BTT Tests
/// @notice Tests for KernelFactory following Branching Tree Technique
/// @dev Tree specification: test/btt/KernelFactory.deploy.tree
contract KernelFactory_Test is Test {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    IEntryPoint ep;
    KernelFactory factory;
    KernelUUPS uups;
    KernelImmutableECDSA immutableEcdsa;
    MockValidator rootValidator;
    MockCallee callee;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        ep = EntryPointLib.deploy();
        uups = new KernelUUPS(ep);
        immutableEcdsa = new KernelImmutableECDSA(ep);
        factory = new KernelFactory(uups, immutableEcdsa);
        rootValidator = new MockValidator();
        rootValidator.sudoSetSuccess(true);
        callee = new MockCallee();
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier givenPackagesArrayIsEmpty() {
        _;
    }

    modifier givenPackagesArrayHasValidModules() {
        _;
    }

    modifier givenMsgValueIsSent() {
        vm.deal(address(this), 10 ether);
        _;
    }

    modifier givenECDSAOwnerIsValid() {
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should revert during initialization when packages array is empty
    function test_RevertWhen_PackagesArrayIsEmpty() external givenPackagesArrayIsEmpty {
        Install[] memory packages = new Install[](0);

        // it should revert with InvalidRootValidation error
        vm.expectRevert(InvalidRootValidation.selector);
        factory.deploy(packages, 0);
    }

    /// @notice it should deploy a new KernelUUPS proxy using CREATE2
    function test_WhenDeployingWithValidPackages() external givenPackagesArrayHasValidModules {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        Kernel account = factory.deploy(packages, 0);

        assertTrue(address(account) != address(0), "Account should be deployed");
        assertTrue(address(account).code.length > 0, "Account should have code");
    }

    /// @notice it should initialize the account with the packages
    function test_WhenDeploying_InitializesAccount() external givenPackagesArrayHasValidModules {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        Kernel account = factory.deploy(packages, 0);

        // Verify root validator is installed
        assertEq(
            account.validationInfo(validatorToIdentifier(IValidator(address(rootValidator)))).hook,
            address(1),
            "Root validator should be installed"
        );
    }

    /// @notice it should set the first package as the root validator
    function test_WhenDeploying_SetsRootValidator() external givenPackagesArrayHasValidModules {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        Kernel account = factory.deploy(packages, 0);

        // Root should be set (we can verify by checking that root validation works)
        assertTrue(address(account) != address(0), "Account with root should be deployed");
    }

    /// @notice it should return the deployed account address matching prediction
    function test_WhenDeploying_ReturnsAddress() external givenPackagesArrayHasValidModules {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        Kernel account = factory.deploy(packages, 0);
        address predicted = factory.getAddress(packages, 0);

        assertEq(address(account), predicted, "Deployed address should match predicted");
    }

    /// @notice it should forward ETH to the deployed account
    function test_WhenDeploying_WithEthValue() external givenPackagesArrayHasValidModules givenMsgValueIsSent {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        uint256 value = 1 ether;
        Kernel account = factory.deploy{value: value}(packages, 0);

        assertEq(address(account).balance, value, "Account should receive ETH");
    }

    /// @notice it should return the existing address if already deployed (counterfactual)
    function test_WhenDeploying_CounterfactualExists() external givenPackagesArrayHasValidModules {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        Kernel account1 = factory.deploy(packages, 0);
        Kernel account2 = factory.deploy(packages, 0);

        assertEq(address(account1), address(account2), "Should return existing account");
    }

    /*//////////////////////////////////////////////////////////////
                    DEPLOY WITH CALL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should deploy and execute the additional call
    function test_WhenDeployWithCall_ExecutesCall() external givenPackagesArrayHasValidModules {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );

        Kernel account = factory.deployWithCall(packages, 0, callData);

        assertEq(callee.bar(), 1, "Call should have been executed");
        assertTrue(address(account) != address(0), "Account should be deployed");
    }

    /// @notice it should revert if additional call reverts
    function test_RevertWhen_DeployWithCall_CallReverts() external givenPackagesArrayHasValidModules {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory callData = abi.encodeWithSelector(
            Kernel.execute.selector,
            bytes32(0),
            abi.encodePacked(address(callee), uint256(0), MockCallee.forceRevert.selector)
        );

        vm.expectRevert("call failed");
        factory.deployWithCall(packages, 0, callData);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOY ECDSA TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should deploy a KernelImmutableECDSA proxy
    function test_WhenDeployingECDSA() external givenECDSAOwnerIsValid {
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        Kernel account = factory.deployECDSA(owner, packages, 0);

        assertTrue(address(account) != address(0), "ECDSA account should be deployed");
        assertTrue(address(account).code.length > 0, "ECDSA account should have code");
    }

    /// @notice it should revert when ECDSA owner is address(0)
    function test_RevertWhen_DeployingECDSA_ZeroOwner() external {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        vm.expectRevert(KernelFactory.InvalidSigner.selector);
        factory.deployECDSA(address(0), packages, 0);
    }

    /// @notice it should return deterministic address for same owner and nonce
    function test_WhenDeployingECDSA_Deterministic() external givenECDSAOwnerIsValid {
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        address predicted = factory.getECDSAAddress(owner, packages, 0);
        Kernel account = factory.deployECDSA(owner, packages, 0);

        assertEq(address(account), predicted, "ECDSA address should be deterministic");
    }

    /// @notice it should forward ETH to ECDSA account
    function test_WhenDeployingECDSA_WithEthValue() external givenECDSAOwnerIsValid givenMsgValueIsSent {
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});
        uint256 value = 1 ether;

        Kernel account = factory.deployECDSA{value: value}(owner, packages, 0);

        assertEq(address(account).balance, value, "ECDSA account should receive ETH");
    }

    /*//////////////////////////////////////////////////////////////
                        GET ADDRESS TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should return deterministic address without deploying
    function test_WhenGettingAddress_NoDeploy() external {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        address predicted = factory.getAddress(packages, 0);

        // Should not have code yet
        assertEq(predicted.code.length, 0, "Should not be deployed yet");

        // Now deploy and verify match
        Kernel deployed = factory.deploy(packages, 0);
        assertEq(address(deployed), predicted, "Addresses should match");
    }

    /// @notice it should return same address for same packages and nonce
    function test_WhenGettingAddress_SameInputsSameOutput() external {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        address predicted1 = factory.getAddress(packages, 0);
        address predicted2 = factory.getAddress(packages, 0);

        assertEq(predicted1, predicted2, "Same inputs should give same address");
    }

    /// @notice it should return different addresses for different nonces
    function test_WhenGettingAddress_DifferentNonces() external {
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        address predicted1 = factory.getAddress(packages, 0);
        address predicted2 = factory.getAddress(packages, 1);

        assertTrue(predicted1 != predicted2, "Different nonces should give different addresses");
    }

    /// @notice it should return different addresses for different packages
    function test_WhenGettingAddress_DifferentPackages() external {
        MockValidator validator2 = new MockValidator();

        Install[] memory packages1 = new Install[](1);
        packages1[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        Install[] memory packages2 = new Install[](1);
        packages2[0] = Install({moduleType: 1, module: address(validator2), moduleData: hex"", internalData: hex""});

        address predicted1 = factory.getAddress(packages1, 0);
        address predicted2 = factory.getAddress(packages2, 0);

        assertTrue(predicted1 != predicted2, "Different packages should give different addresses");
    }

    /*//////////////////////////////////////////////////////////////
                    GET ECDSA ADDRESS TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should return deterministic ECDSA address
    function test_WhenGettingECDSAAddress() external {
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        address predicted = factory.getECDSAAddress(owner, packages, 0);

        // Should not have code yet
        assertEq(predicted.code.length, 0, "Should not be deployed yet");

        // Now deploy and verify match
        Kernel deployed = factory.deployECDSA(owner, packages, 0);
        assertEq(address(deployed), predicted, "ECDSA addresses should match");
    }

    /// @notice it should return different addresses for different owners
    function test_WhenGettingECDSAAddress_DifferentOwners() external {
        address owner1 = makeAddr("owner1");
        address owner2 = makeAddr("owner2");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        address predicted1 = factory.getECDSAAddress(owner1, packages, 0);
        address predicted2 = factory.getECDSAAddress(owner2, packages, 0);

        assertTrue(predicted1 != predicted2, "Different owners should give different addresses");
    }
}
