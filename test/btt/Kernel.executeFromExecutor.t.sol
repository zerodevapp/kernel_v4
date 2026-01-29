// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";

abstract contract Kernel_executeFromExecutor is BTTModifiers {
    function test_WhenTheCallerIsNotAnInstalledExecutor() external {
        // it should revert with Unauthorized error
    }

    modifier whenTheCallerIsAnInstalledExecutor() {
        _;
    }

    modifier givenTheExecutorHasAHookConfigured() {
        _;
    }

    function test_GivenTheExecutorHasAHookConfigured()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutorHasAHookConfigured
    {
        // it should call preHook on the executor hook before execution
    }

    function test_GivenPreHookReverts()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutorHasAHookConfigured
    {
        // it should propagate the revert
    }

    modifier givenPreHookSucceeds() {
        _;
    }

    function test_GivenPreHookSucceeds()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutorHasAHookConfigured
        givenPreHookSucceeds
    {
        // it should execute the requested operations
        // it should call postHook on the executor hook after execution
    }

    function test_GivenPostHookReverts()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutorHasAHookConfigured
        givenPreHookSucceeds
    {
        // it should propagate the revert
    }

    function test_GivenPostHookSucceeds()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutorHasAHookConfigured
        givenPreHookSucceeds
    {
        // it should return the execution results
    }

    function test_GivenTheExecutorHasHookSetToAddress1() external whenTheCallerIsAnInstalledExecutor {
        // it should skip preHook and postHook calls
        // it should execute the requested operations directly
    }

    modifier givenTheExecutionModeCallTypeIsSINGLE() {
        _;
    }

    function test_WhenTheTargetCallSucceeds()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsSINGLE
    {
        // it should return the result in returnData array
    }

    function test_WhenTheTargetCallRevertsWithDEFAULTExecType()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsSINGLE
    {
        // it should propagate the revert
    }

    modifier givenTheExecutionModeCallTypeIsBATCH() {
        _;
    }

    function test_WhenAllCallsSucceed()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsBATCH
    {
        // it should return all results in returnData array
    }

    function test_WhenAnyCallRevertsWithDEFAULTExecType()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsBATCH
    {
        // it should propagate the revert
    }

    modifier givenTheExecutionModeCallTypeIsDELEGATECALL() {
        _;
    }

    function test_WhenTheDelegatecallSucceeds()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsDELEGATECALL
    {
        // it should return the result
    }

    function test_WhenTheDelegatecallRevertsWithDEFAULTExecType()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsDELEGATECALL
    {
        // it should propagate the revert
    }
}
