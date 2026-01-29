// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

abstract contract Staker_stake is Test {
    function test_WhenTheCallerIsNotTheOwner() external {
        // it should revert with Unauthorized error
    }

    modifier whenTheCallerIsTheOwner() {
        _;
    }

    function test_GivenMsgValueIsZero() external whenTheCallerIsTheOwner {
        // it should call addStake with zero value
    }

    function test_GivenMsgValueIsGreaterThanZero() external whenTheCallerIsTheOwner {
        // it should call addStake on the EntryPoint
        // it should increase the stake by msg value
    }
}
