// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

abstract contract Staker_revokeFactory is Test {
    function test_WhenTheCallerIsNotTheOwner() external {
        // it should revert with Unauthorized error
    }

    modifier whenTheCallerIsTheOwner() {
        _;
    }

    function test_GivenTheFactoryIsApproved() external whenTheCallerIsTheOwner {
        // it should set the factory as not approved
        // it should emit FactoryRevoked event
    }

    function test_GivenTheFactoryIsNotApproved() external whenTheCallerIsTheOwner {
        // it should remain not approved
    }
}
