// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";
import {Kernel} from "src/Kernel.sol";
import {Install} from "src/types/Structs.sol";
import {MockCallee} from "../mock/MockCallee.sol";

abstract contract KernelFactory_deployWithCall is BTTModifiers {
    modifier whenTheAddressIsAlreadyDeployedForThisInitPackagesHashAndNonce() {
        _;
    }

    function test_WhenTheAddressIsAlreadyDeployedForThisInitPackagesHashAndNonce()
        external
        whenTheAddressIsAlreadyDeployedForThisInitPackagesHashAndNonce
    {
        // it should return the existing account address
        // it should execute extraCall on the account
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory callData =
            abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector));

        // Deploy first time
        Kernel first = factory.deployWithCall(packages, 0, callData);
        uint256 barAfterFirst = callee.bar();

        // Deploy again with same params - should return existing and execute call again
        Kernel second = factory.deployWithCall(packages, 0, callData);
        uint256 barAfterSecond = callee.bar();

        assertEq(address(first), address(second), "Should return same address");
        assertEq(barAfterSecond, barAfterFirst + 1, "Should execute extraCall on existing account");
    }

    function test_WhenExtraCallReverts()
        external
        whenTheAddressIsAlreadyDeployedForThisInitPackagesHashAndNonce
    {
        // it should revert with "call failed"
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        // Deploy first with valid call
        bytes memory validCall =
            abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector));
        factory.deployWithCall(packages, 0, validCall);

        // Try again with reverting call
        bytes memory revertingCall =
            abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.forceRevert.selector));

        vm.expectRevert("call failed");
        factory.deployWithCall(packages, 0, revertingCall);
    }

    modifier whenTheAddressIsNotYetDeployed() {
        _;
    }

    function test_WhenTheAddressIsNotYetDeployed() external whenTheAddressIsNotYetDeployed {
        // it should deploy a new KernelUUPS proxy using CREATE2
        // it should initialize the account with the packages
        // it should execute extraCall on the account
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        uint256 barBefore = callee.bar();
        bytes memory callData =
            abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector));

        // Use a unique nonce to ensure fresh deployment
        Kernel account = factory.deployWithCall(packages, 999, callData);

        assertTrue(address(account) != address(0), "Account should be deployed");
        assertTrue(address(account).code.length > 0, "Account should have code");
        assertEq(callee.bar(), barBefore + 1, "extraCall should have executed");
    }

    function test_WhenExtraCallReverts_WhenTheAddressIsNotYetDeployed() external whenTheAddressIsNotYetDeployed {
        // it should revert with "call failed"
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory revertingCall =
            abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.forceRevert.selector));

        // Use unique nonce to ensure fresh deployment attempt
        vm.expectRevert("call failed");
        factory.deployWithCall(packages, 998, revertingCall);
    }

    function test_GivenMsgValueIsSent() external whenTheAddressIsNotYetDeployed {
        // it should fund the deployed account
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory callData =
            abi.encodeWithSelector(Kernel.execute.selector, bytes32(0), abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector));

        uint256 fundAmount = 1 ether;
        address predictedAddress = factory.getAddress(packages, 997);
        uint256 balanceBefore = predictedAddress.balance;

        // Deploy with value - use unique nonce
        factory.deployWithCall{value: fundAmount}(packages, 997, callData);

        assertEq(predictedAddress.balance, balanceBefore + fundAmount, "Account should be funded");
    }
}
