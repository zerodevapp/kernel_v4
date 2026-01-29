// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";

abstract contract Kernel_executeUserOp is BTTModifiers {
    modifier whenTheCallerIsNotTheEntryPoint() {
        _;
    }

    function test_WhenTheCallerIsNotTheAccountItself() external whenTheCallerIsNotTheEntryPoint {
        // it should revert with Unauthorized error
    }

    modifier whenTheCallerIsTheEntryPointOrSelf() {
        _;
    }

    function test_GivenNoValidationHookIsSetInTransientStorage() external whenTheCallerIsTheEntryPointOrSelf {
        // it should skip the preHook call
        // it should execute the inner callData via delegatecall
        // it should skip the postHook call
    }

    modifier givenAValidationHookIsSetInTransientStorage() {
        _;
    }

    function test_GivenAValidationHookIsSetInTransientStorage()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenAValidationHookIsSetInTransientStorage
    {
        // it should call preHook on the hook contract with callData
    }

    function test_GivenPreHookReverts()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenAValidationHookIsSetInTransientStorage
    {
        // it should propagate the revert
    }

    modifier givenPreHookSucceeds() {
        _;
    }

    function test_GivenPreHookSucceeds()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenAValidationHookIsSetInTransientStorage
        givenPreHookSucceeds
    {
        // it should execute the inner callData via delegatecall
    }

    function test_GivenTheInnerExecutionReverts()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenAValidationHookIsSetInTransientStorage
        givenPreHookSucceeds
    {
        // it should propagate the revert message
    }

    modifier givenTheInnerExecutionSucceeds() {
        _;
    }

    function test_GivenTheInnerExecutionSucceeds()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenAValidationHookIsSetInTransientStorage
        givenPreHookSucceeds
        givenTheInnerExecutionSucceeds
    {
        // it should call postHook on the hook contract with context
    }

    function test_GivenPostHookReverts()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenAValidationHookIsSetInTransientStorage
        givenPreHookSucceeds
        givenTheInnerExecutionSucceeds
    {
        // it should propagate the revert
    }

    function test_GivenPostHookSucceeds()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenAValidationHookIsSetInTransientStorage
        givenPreHookSucceeds
        givenTheInnerExecutionSucceeds
    {
        // it should complete successfully
    }

    function test_WhenTheInnerCallDataIsExecuteWithSingleCall() external whenTheCallerIsTheEntryPointOrSelf {
        // it should execute the target call
        // it should return the call result
    }

    function test_WhenTheInnerCallDataIsExecuteWithBatchCalls() external whenTheCallerIsTheEntryPointOrSelf {
        // it should execute all calls in order
        // it should return all results
    }

    function test_WhenTheInnerCallDataIsExecuteWithDelegatecall() external whenTheCallerIsTheEntryPointOrSelf {
        // it should delegatecall to the target
        // it should return the delegatecall result
    }
}
