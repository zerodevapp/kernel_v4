// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

abstract contract KernelFactory_deployECDSA is Test {
    function test_WhenTheECDSAOwnerIsAddressZero() external {
        // it should deploy with zero address
    }

    function test_WhenTheECDSAOwnerIsAValidAddress() external {
        // it should deploy a KernelImmutableECDSA proxy using CREATE2
        // it should NOT call initialize
        // it should return the deployed account address
        // it should emit AccountCreated event
    }

    function test_WhenTheSaltHasAlreadyBeenUsedForThisOwner() external {
        // it should revert with CREATE2 collision
    }

    function test_GivenMsgValueIsSent() external {
        // it should forward the ETH to the deployed account
    }
}
