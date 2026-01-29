// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

abstract contract Staker_deployWithFactory is Test {
    function test_GivenTheFactoryIsNotApproved() external {
        // it should revert with FactoryNotApproved error
    }

    modifier givenTheFactoryIsApproved() {
        _;
    }

    function test_GivenTheFactoryIsApproved() external givenTheFactoryIsApproved {
        // it should call the factory deploy function with the provided data
    }

    function test_WhenTheFactoryDeploymentSucceeds() external givenTheFactoryIsApproved {
        // it should return the deployed account address
    }

    function test_WhenTheFactoryDeploymentReverts() external givenTheFactoryIsApproved {
        // it should propagate the revert
    }
}
