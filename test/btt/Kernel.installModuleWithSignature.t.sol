// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";

abstract contract Kernel_installModuleWithSignature is BTTModifiers {
    modifier whenReplayableIsFalse() {
        _;
    }

    modifier givenTheSignatureIsValidForThisChain() {
        _;
    }

    function test_GivenTheNonceHasNotBeenUsed() external whenReplayableIsFalse givenTheSignatureIsValidForThisChain {
        // it should verify the root validator signature
        // it should increment the nonce
        // it should install all packages
        // it should emit ModuleInstalled events for each package
    }

    function test_GivenTheNonceHasAlreadyBeenUsed()
        external
        whenReplayableIsFalse
        givenTheSignatureIsValidForThisChain
    {
        // it should revert with NonceAlreadyUsed error
    }

    function test_GivenTheSignatureIsInvalid() external whenReplayableIsFalse {
        // it should revert with InstallSignatureVerificationFailed error
    }

    modifier whenReplayableIsTrue() {
        _;
    }

    modifier givenTheSignatureIsValid() {
        _;
    }

    function test_GivenTheNonceHasNotBeenUsedOnThisChain() external whenReplayableIsTrue givenTheSignatureIsValid {
        // it should verify the root validator signature
        // it should increment the nonce on this chain
        // it should install all packages
        // it should allow the same signature on different chains
    }

    function test_GivenTheNonceHasAlreadyBeenUsedOnThisChain() external whenReplayableIsTrue givenTheSignatureIsValid {
        // it should revert with NonceAlreadyUsed error
    }

    function test_GivenTheSignatureIsInvalid_WhenReplayableIsTrue() external whenReplayableIsTrue {
        // it should revert with InstallSignatureVerificationFailed error
    }

    function test_GivenPackagesContainAValidator() external {
        // it should install the validator with its hook and allowed selectors
        // it should NOT automatically set it as root
    }

    function test_GivenPackagesContainAnExecutor() external {
        // it should install the executor with its hook
    }

    function test_GivenPackagesContainAFallbackHandler() external {
        // it should register the selector to the fallback
    }

    function test_GivenPackagesContainPoliciesAndSignerForAPermission() external {
        // it should install all policies for the permissionId
        // it should install the signer for the permissionId
    }

    function test_GivenPackagesContainAHook() external {
        // it should enable the hook
    }
}
