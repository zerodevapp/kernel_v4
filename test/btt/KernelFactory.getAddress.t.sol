// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

abstract contract KernelFactory_getAddress is Test {
    function test_GivenAnyPackagesAndNonce() external {
        // it should return the deterministic address without deploying
        // it should return the same address for the same packages and nonce
        // it should return different addresses for different packages or nonces
    }
}
