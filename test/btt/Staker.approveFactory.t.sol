// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

abstract contract Staker_approveFactory is Test {
    function test_WhenTheCallerIsNotTheOwner() external {
        // it should revert with Unauthorized error
    }

    modifier whenTheCallerIsTheOwner() {
        _;
    }

    function test_GivenTheFactoryIsNotApproved() external whenTheCallerIsTheOwner {
        // it should set the factory as approved
        // it should emit FactoryApproved event
    }

    function test_GivenTheFactoryIsAlreadyApproved() external whenTheCallerIsTheOwner {
        // it should remain approved
    }
}
