// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

abstract contract KernelFactory_deploy is Test {
    function test_WhenTheSaltHasAlreadyBeenUsedForThisInitPackagesHash() external {
        // it should revert with CREATE2 collision
    }

    modifier whenTheSaltIsUnique() {
        _;
    }

    function test_GivenPackagesArrayIsEmpty() external whenTheSaltIsUnique {
        // it should revert during initialization
    }

    function test_GivenPackagesArrayHasValidModules() external whenTheSaltIsUnique {
        // it should deploy a new KernelUUPS proxy using CREATE2
        // it should initialize the account with the packages
        // it should set the first package as the root validator
        // it should return the deployed account address
        // it should emit AccountCreated event
    }

    function test_GivenThePredictedAddressAlreadyHasCode() external whenTheSaltIsUnique {
        // it should return the existing address without redeploying
    }

    function test_GivenMsgValueIsSentWithTheCall() external whenTheSaltIsUnique {
        // it should forward the ETH to the deployed account
        // it should initialize the account with the ETH balance
    }
}
