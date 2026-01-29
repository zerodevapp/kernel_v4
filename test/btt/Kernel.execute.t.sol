// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Kernel} from "src/Kernel.sol";
import {BTTModifiers} from "./BTTModifiers.sol";
import {MockCallee} from "../mock/MockCallee.sol";
import {MockAction} from "../mock/MockAction.sol";
import {Unauthorized} from "src/types/Error.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";
import {Call} from "src/types/Structs.sol";

/// @title Kernel.execute BTT Tests
/// @notice Tests for execute following Branching Tree Technique
/// @dev Tree specification: test/btt/Kernel.execute.tree
abstract contract Kernel_execute is BTTModifiers {
    modifier whenTheCallerIsNotTheEntryPoint() {
        _;
    }

    function test_WhenTheCallerIsNotTheAccountItself() external whenTheCallerIsNotTheEntryPoint {
        // it should revert with Unauthorized error
    }

    modifier whenTheCallerIsTheEntryPointOrSelf() {
        _;
    }

    modifier givenTheExecutionModeCallTypeIsSINGLE() {
        _;
    }

    modifier givenTheExecutionModeExecTypeIsDEFAULT() {
        _;
    }

    function test_WhenTheTargetCallSucceeds()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsSINGLE
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should return the call result in returnData array
        // it should have exactly one element in returnData
    }

    function test_WhenTheTargetCallReverts()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsSINGLE
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should propagate the revert
    }

    modifier givenTheExecutionModeExecTypeIsTRY() {
        _;
    }

    function test_WhenTheTargetCallSucceeds_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsSINGLE
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should return the call result in returnData array
        // it should have exactly one element in returnData
    }

    function test_WhenTheTargetCallReverts_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsSINGLE
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should NOT propagate the revert
        // it should return empty bytes for the failed call
    }

    modifier givenTheExecutionModeCallTypeIsBATCH() {
        _;
    }

    function test_WhenAllTargetCallsSucceed()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsBATCH
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should return all call results in returnData array
        // it should have N elements in returnData for N calls
    }

    function test_WhenAnyTargetCallReverts()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsBATCH
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should propagate the revert
        // it should NOT execute remaining calls after the failure
    }

    function test_WhenAllTargetCallsSucceed_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsBATCH
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should return all call results in returnData array
        // it should have N elements in returnData for N calls
    }

    function test_WhenAnyTargetCallReverts_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsBATCH
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should NOT propagate the revert
        // it should return empty bytes for the failed call
        // it should continue executing remaining calls
    }

    modifier givenTheExecutionModeCallTypeIsDELEGATECALL() {
        _;
    }

    function test_WhenTheDelegatecallSucceeds()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsDELEGATECALL
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should return the delegatecall result
        // it should execute in the context of the Kernel
    }

    function test_WhenTheDelegatecallReverts()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsDELEGATECALL
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should propagate the revert
    }

    function test_WhenTheDelegatecallSucceeds_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsDELEGATECALL
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should return the delegatecall result
    }

    function test_WhenTheDelegatecallReverts_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsTheEntryPointOrSelf
        givenTheExecutionModeCallTypeIsDELEGATECALL
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should NOT propagate the revert
        // it should return empty bytes
    }

    function test_RevertGiven_TheExecutionModeCallTypeIsUnsupported() external whenTheCallerIsTheEntryPointOrSelf {
        // it should revert
    }

    MockAction action;

    function _setupExecuteTests() internal {
        action = new MockAction();
    }

    /*//////////////////////////////////////////////////////////////
                        UNAUTHORIZED CALLER TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should revert with Unauthorized error when caller is not EntryPoint or self
    function test_execute_RevertWhen_CallerIsNotEntryPointAndNotSelf()
        external
        unitTest
        whenCallerIsNotEntryPoint
        whenCallerIsNotAccountItself
    {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT);
        bytes memory executionData = abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector);

        vm.expectRevert(Unauthorized.selector);
        kernel.execute(mode, executionData);
    }

    /*//////////////////////////////////////////////////////////////
                    SINGLE CALL + DEFAULT EXEC TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should return the call result when target call succeeds (SINGLE + DEFAULT)
    function test_WhenSingleCallSucceeds_DefaultExec()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsSingle
        givenExecTypeIsDefault
    {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT);
        bytes memory executionData = abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector);

        kernel.execute(mode, executionData);

        assertEq(callee.bar(), 1, "Callee state should be updated");
    }

    /// @notice it should propagate the revert when target call reverts (SINGLE + DEFAULT)
    function test_RevertWhen_SingleCallReverts_DefaultExec()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsSingle
        givenExecTypeIsDefault
    {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT);
        bytes memory executionData = abi.encodePacked(address(callee), uint256(0), MockCallee.revertingFn.selector);

        vm.expectRevert("MockCallee: revert");
        kernel.execute(mode, executionData);
    }

    /// @notice it should return the call result when target call succeeds (SINGLE + TRY)
    function test_WhenSingleCallSucceeds_TryExec()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsSingle
        givenExecTypeIsTry
    {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_TRY);
        bytes memory executionData = abi.encodePacked(address(callee), uint256(0), MockCallee.foo.selector);

        kernel.execute(mode, executionData);

        assertEq(callee.bar(), 1, "Callee state should be updated");
    }

    /// @notice it should NOT propagate the revert when target call reverts (SINGLE + TRY)
    function test_WhenSingleCallReverts_TryExec_NoRevert()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsSingle
        givenExecTypeIsTry
    {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_TRY);
        bytes memory executionData = abi.encodePacked(address(callee), uint256(0), MockCallee.revertingFn.selector);

        // Should NOT revert
        kernel.execute(mode, executionData);

        // Callee state should remain unchanged
        assertEq(callee.bar(), 0, "Callee state should remain unchanged after failed TRY");
    }

    /*//////////////////////////////////////////////////////////////
                    BATCH CALL + DEFAULT EXEC TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should return all call results when all batch calls succeed (BATCH + DEFAULT)
    function test_WhenBatchCallsAllSucceed_DefaultExec()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsBatch
        givenExecTypeIsDefault
    {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_BATCH, LibERC7579.EXECTYPE_DEFAULT);

        // Create batch of 3 calls using Call struct
        Call[] memory calls = new Call[](3);
        calls[0] = Call({to: address(callee), value: 0, data: abi.encodeWithSelector(MockCallee.foo.selector)});
        calls[1] = Call({to: address(callee), value: 0, data: abi.encodeWithSelector(MockCallee.foo.selector)});
        calls[2] = Call({to: address(callee), value: 0, data: abi.encodeWithSelector(MockCallee.foo.selector)});

        kernel.execute(mode, abi.encode(calls));

        assertEq(callee.bar(), 3, "Callee state should reflect 3 calls");
    }

    /// @notice it should propagate the revert when any batch call reverts (BATCH + DEFAULT)
    function test_RevertWhen_BatchCallReverts_DefaultExec()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsBatch
        givenExecTypeIsDefault
    {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_BATCH, LibERC7579.EXECTYPE_DEFAULT);

        // First call succeeds, second reverts
        Call[] memory calls = new Call[](2);
        calls[0] = Call({to: address(callee), value: 0, data: abi.encodeWithSelector(MockCallee.foo.selector)});
        calls[1] = Call({to: address(callee), value: 0, data: abi.encodeWithSelector(MockCallee.forceRevert.selector)});

        vm.expectRevert(MockCallee.Haha.selector);
        kernel.execute(mode, abi.encode(calls));
    }

    /// @notice it should NOT propagate the revert and continue when batch call reverts (BATCH + TRY)
    function test_WhenBatchCallReverts_TryExec_Continues()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsBatch
        givenExecTypeIsTry
    {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_BATCH, LibERC7579.EXECTYPE_TRY);

        // First call succeeds, second reverts, third succeeds
        Call[] memory calls = new Call[](3);
        calls[0] = Call({to: address(callee), value: 0, data: abi.encodeWithSelector(MockCallee.foo.selector)});
        calls[1] = Call({to: address(callee), value: 0, data: abi.encodeWithSelector(MockCallee.forceRevert.selector)});
        calls[2] = Call({to: address(callee), value: 0, data: abi.encodeWithSelector(MockCallee.foo.selector)});

        // Should NOT revert
        kernel.execute(mode, abi.encode(calls));

        // First and third calls should have executed
        assertEq(callee.bar(), 2, "First and third calls should have executed");
    }

    /*//////////////////////////////////////////////////////////////
                    DELEGATECALL + DEFAULT EXEC TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should execute in kernel context when delegatecall succeeds
    function test_WhenDelegatecallSucceeds_DefaultExec()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsDelegatecall
        givenExecTypeIsDefault
    {
        _setupExecuteTests();
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_DELEGATECALL, LibERC7579.EXECTYPE_DEFAULT);
        bytes memory executionData = abi.encodePacked(address(action), abi.encodeWithSelector(action.doAction.selector));

        kernel.execute(mode, executionData);

        // Action modifies kernel's storage
        assertEq(kernel.accountId(), "kernel.v0.4", "Delegatecall should execute in kernel context");
    }

    /// @notice it should propagate the revert when delegatecall reverts (DELEGATECALL + DEFAULT)
    function test_RevertWhen_DelegatecallReverts_DefaultExec()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsDelegatecall
        givenExecTypeIsDefault
    {
        _setupExecuteTests();
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_DELEGATECALL, LibERC7579.EXECTYPE_DEFAULT);
        bytes memory executionData =
            abi.encodePacked(address(action), abi.encodeWithSelector(action.doRevertingAction.selector));

        vm.expectRevert("MockAction: revert");
        kernel.execute(mode, executionData);
    }

    /// @notice it should NOT propagate the revert when delegatecall reverts (DELEGATECALL + TRY)
    function test_WhenDelegatecallReverts_TryExec_NoRevert()
        external
        unitTest
        whenCallerIsEntryPointOrSelf
        givenCallTypeIsDelegatecall
        givenExecTypeIsTry
    {
        _setupExecuteTests();
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_DELEGATECALL, LibERC7579.EXECTYPE_TRY);
        bytes memory executionData =
            abi.encodePacked(address(action), abi.encodeWithSelector(action.doRevertingAction.selector));

        // Should NOT revert
        kernel.execute(mode, executionData);
    }

    /*//////////////////////////////////////////////////////////////
                        ETH VALUE TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice it should transfer ETH value with the call
    function test_WhenSingleCallWithEthValue() external unitTest whenCallerIsEntryPointOrSelf givenCallTypeIsSingle {
        bytes32 mode = _encodeMode(LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT);
        uint256 value = 1 ether;
        bytes memory executionData = abi.encodePacked(address(callee), value, MockCallee.receiveEth.selector);

        uint256 calleeBalanceBefore = address(callee).balance;
        kernel.execute(mode, executionData);
        uint256 calleeBalanceAfter = address(callee).balance;

        assertEq(calleeBalanceAfter - calleeBalanceBefore, value, "Callee should receive ETH");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _encodeMode(bytes1 callType, bytes1 execType) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(callType, execType, bytes4(0), bytes4(0), bytes22(0)));
    }
}
