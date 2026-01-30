// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";
import {Kernel} from "src/Kernel.sol";
import {Install} from "src/types/Structs.sol";
import {MockCallee} from "../mock/MockCallee.sol";
import {KernelFactory} from "src/KernelFactory.sol";

abstract contract KernelFactory_deployECDSAWithCall is BTTModifiers {
    // Expected error selector (to be added to KernelFactory.sol)
    error CallFailed();

    // State variables for deployECDSAWithCall branch tracking
    bool internal _ecdsaAddressAlreadyDeployed;

    function test_WhenTheECDSAOwnerIsAddressZero() external {
        // it should revert with InvalidSigner error
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory callData = abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), hex"");

        vm.expectRevert(KernelFactory.InvalidSigner.selector);
        factory.deployECDSAWithCall(address(0), packages, 0, callData);
    }

    modifier whenTheAddressIsAlreadyDeployedForThisOwnerAndNonce() {
        _ecdsaAddressAlreadyDeployed = true;
        _;
    }

    function test_WhenTheAddressIsAlreadyDeployedForThisOwnerAndNonce()
        external
        whenTheAddressIsAlreadyDeployedForThisOwnerAndNonce
    {
        // it should return the existing account address
        // it should execute extraCall on the account
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );

        // Deploy first time
        Kernel first = factory.deployECDSAWithCall(owner, packages, 0, callData);
        uint256 barAfterFirst = callee.bar();

        // Deploy again with same params - should return existing and execute call again
        Kernel second = factory.deployECDSAWithCall(owner, packages, 0, callData);
        uint256 barAfterSecond = callee.bar();

        assertEq(address(first), address(second), "Should return same address");
        assertEq(barAfterSecond, barAfterFirst + 1, "Should execute extraCall on existing account");
    }

    function test_WhenExtraCallReverts() external whenTheAddressIsAlreadyDeployedForThisOwnerAndNonce {
        // it should revert with "call failed"
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        // Deploy first with valid call
        bytes memory validCall = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );
        factory.deployECDSAWithCall(owner, packages, 0, validCall);

        // Try again with reverting call
        bytes memory revertingCall = abi.encodeWithSelector(
            Kernel.execute.selector,
            bytes32(0),
            abi.encodePacked(address(callee), uint256(0), MockCallee.forceRevert.selector)
        );

        vm.expectRevert(CallFailed.selector);
        factory.deployECDSAWithCall(owner, packages, 0, revertingCall);
    }

    modifier whenTheECDSAOwnerIsAValidAddressAndNotYetDeployed() {
        _ecdsaAddressAlreadyDeployed = false;
        _;
    }

    function test_WhenTheECDSAOwnerIsAValidAddressAndNotYetDeployed()
        external
        whenTheECDSAOwnerIsAValidAddressAndNotYetDeployed
    {
        // it should deploy a KernelImmutableECDSA proxy using CREATE2
        // it should initialize the account with the packages
        // it should execute extraCall on the account
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        uint256 barBefore = callee.bar();
        bytes memory callData = abi.encodeWithSelector(
            Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector)
        );

        Kernel account = factory.deployECDSAWithCall(owner, packages, 0, callData);

        assertTrue(address(account) != address(0), "Account should be deployed");
        assertTrue(address(account).code.length > 0, "Account should have code");
        assertEq(callee.bar(), barBefore + 1, "extraCall should have executed");
    }

    function test_WhenExtraCallReverts_WhenTheECDSAOwnerIsAValidAddressAndNotYetDeployed()
        external
        whenTheECDSAOwnerIsAValidAddressAndNotYetDeployed
    {
        // it should revert with "call failed"
        address owner = makeAddr("ecdsaOwner");
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory revertingCall = abi.encodeWithSelector(
            Kernel.execute.selector,
            bytes32(0),
            abi.encodePacked(address(callee), uint256(0), MockCallee.forceRevert.selector)
        );

        vm.expectRevert(CallFailed.selector);
        factory.deployECDSAWithCall(owner, packages, 0, revertingCall);
    }
}
