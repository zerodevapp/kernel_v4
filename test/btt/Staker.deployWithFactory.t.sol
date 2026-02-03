// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {StakerBTTModifiers} from "./StakerBTTModifiers.sol";
import {Staker} from "src/Staker.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {Install} from "src/types/Structs.sol";

abstract contract Staker_deployWithFactory is StakerBTTModifiers {
    function setUp() public override {
        _initializeStaker();
    }

    function test_GivenTheFactoryIsNotApproved() external {
        // it should revert with NotApprovedFactory error
        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory deployData = abi.encodeWithSelector(KernelFactory.deploy.selector, packages, uint256(0));

        vm.expectRevert(Staker.NotApprovedFactory.selector);
        staker.deployWithFactory(address(factory), deployData);
    }

    modifier givenTheFactoryIsApproved() override {
        vm.prank(owner);
        staker.approveFactory(address(factory), true);
        _;
    }

    function test_GivenTheFactoryIsApproved() external givenTheFactoryIsApproved {
        // it should call the factory deploy function with the provided data

        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory deployData = abi.encodeWithSelector(KernelFactory.deploy.selector, packages, uint256(0));

        address account = staker.deployWithFactory(address(factory), deployData);

        assertTrue(account != address(0), "Account should be deployed");
        assertTrue(account.code.length > 0, "Account should have code");
    }

    function test_WhenTheFactoryDeploymentSucceeds() external givenTheFactoryIsApproved {
        // it should return the deployed account address

        Install[] memory packages = new Install[](1);
        packages[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});

        bytes memory deployData = abi.encodeWithSelector(KernelFactory.deploy.selector, packages, uint256(1));

        address account = staker.deployWithFactory(address(factory), deployData);

        // Verify returned address matches predicted address
        address predicted = factory.getAddress(packages, 1);
        assertEq(account, predicted, "Returned address should match predicted");
    }

    function test_WhenTheFactoryDeploymentReverts() external givenTheFactoryIsApproved {
        // it should revert with DeployFailed error

        MockFailingFactory failingFactory = new MockFailingFactory();

        // Approve the failing factory
        vm.prank(owner);
        staker.approveFactory(address(failingFactory), true);

        bytes memory deployData = abi.encodeWithSelector(MockFailingFactory.deploy.selector);

        vm.expectRevert(Staker.DeployFailed.selector);
        staker.deployWithFactory(address(failingFactory), deployData);
    }
}

contract MockFailingFactory {
    error DeployFailed();

    function deploy() external pure returns (address) {
        revert DeployFailed();
    }
}
