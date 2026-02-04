// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {FactoryBTTModifiers} from "./FactoryBTTModifiers.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {Kernel} from "src/Kernel.sol";
import {Install} from "src/types/Structs.sol";
import {InvalidSigner} from "src/types/Error.sol";

abstract contract KernelFactory_deployECDSA is FactoryBTTModifiers {
    function test_WhenTheECDSAOwnerIsAddressZero() external {
        _initializeFactory();
        // it should revert with InvalidSigner error
        Install[] memory packages = new Install[](0);

        vm.expectRevert(InvalidSigner.selector);
        factory.deployECDSA(address(0), packages, 0);
    }

    modifier whenTheAddressIsAlreadyDeployedForThisOwnerAndNonce() {
        _addressAlreadyDeployed = true;
        _;
    }

    function test_WhenTheAddressIsAlreadyDeployedForThisOwnerAndNonce()
        external
        whenTheAddressIsAlreadyDeployedForThisOwnerAndNonce
    {
        _initializeFactory();
        // it should return the existing account address
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](0);

        // Deploy first time
        Kernel account1 = factory.deployECDSA(owner, packages, 0);

        // Deploy again with same params - should return existing
        Kernel account2 = factory.deployECDSA(owner, packages, 0);

        assertEq(address(account1), address(account2), "Should return existing account address");
    }

    modifier whenTheECDSAOwnerIsAValidAddressAndNotYetDeployed() {
        _addressAlreadyDeployed = false;
        _ecdsaOwner = makeAddr("ecdsaOwner");
        _;
    }

    function test_WhenTheECDSAOwnerIsAValidAddressAndNotYetDeployed()
        external
        whenTheECDSAOwnerIsAValidAddressAndNotYetDeployed
    {
        _initializeFactory();
        // it should deploy a KernelImmutableECDSA proxy using CREATE2
        // it should initialize the account with the packages
        // it should return the deployed account address
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](0);

        Kernel account = factory.deployECDSA(owner, packages, 0);

        assertTrue(address(account) != address(0), "Account should be deployed");
        assertTrue(address(account).code.length > 0, "Account should have code");

        // Verify it's deterministic
        address predicted = factory.getECDSAAddress(owner, packages, 0);
        assertEq(address(account), predicted, "Deployed address should match predicted");
    }
}
