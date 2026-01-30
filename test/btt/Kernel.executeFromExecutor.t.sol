// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";
import {Unauthorized, InvalidExecType, InvalidCallType} from "src/types/Error.sol";
import {MockExecutor} from "../mock/MockExecutor.sol";
import {MockCallee} from "../mock/MockCallee.sol";
import {MockHook} from "../mock/MockHook.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";
import {Call} from "src/types/Structs.sol";

abstract contract Kernel_executeFromExecutor is BTTModifiers {
    MockExecutor testExecutor;

    function _setupExecutorTests() internal {
        testExecutor = new MockExecutor();
        vm.stopPrank();
        vm.startPrank(address(ep));
        kernel.installModule(2, address(testExecutor), abi.encode(hex"", hex""));
        vm.stopPrank();
    }

    function test_WhenTheCallerIsNotAnInstalledExecutor() external {
        // it should revert with Unauthorized error
        MockExecutor uninstalledExecutor = new MockExecutor();

        vm.expectRevert(Unauthorized.selector);
        uninstalledExecutor.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, address(callee), 0, MockCallee.foo.selector
        );
    }

    modifier whenTheCallerIsAnInstalledExecutor() {
        _setupExecutorTests();
        _;
    }

    function test_GivenTheExecutionModeExecTypeIsUnsupported() external whenTheCallerIsAnInstalledExecutor {
        // it should revert with InvalidExecType error
        vm.expectRevert(InvalidExecType.selector);
        testExecutor.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, bytes1(0x02), address(callee), 0, MockCallee.foo.selector
        );
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
        MockHook mockHook = new MockHook();
        MockExecutor executorWithHook = new MockExecutor();

        vm.startPrank(address(ep));
        kernel.installModule(2, address(executorWithHook), abi.encode(hex"", abi.encodePacked(address(mockHook))));
        vm.stopPrank();

        executorWithHook.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, address(callee), 0, MockCallee.foo.selector
        );

        assertTrue(mockHook.preHookCalled(), "preHook should be called");
    }

    function test_GivenPreHookReverts() external whenTheCallerIsAnInstalledExecutor givenTheExecutorHasAHookConfigured {
        // it should propagate the revert
        MockHook revertingHook = new MockHook();
        revertingHook.setRevertOnPreHook(true);
        MockExecutor executorWithHook = new MockExecutor();

        vm.startPrank(address(ep));
        kernel.installModule(2, address(executorWithHook), abi.encode(hex"", abi.encodePacked(address(revertingHook))));
        vm.stopPrank();

        vm.expectRevert("preHook reverted");
        executorWithHook.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, address(callee), 0, MockCallee.foo.selector
        );
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
        MockHook mockHook = new MockHook();
        MockExecutor executorWithHook = new MockExecutor();

        vm.startPrank(address(ep));
        kernel.installModule(2, address(executorWithHook), abi.encode(hex"", abi.encodePacked(address(mockHook))));
        vm.stopPrank();

        executorWithHook.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, address(callee), 0, MockCallee.foo.selector
        );

        assertTrue(mockHook.postHookCalled(), "postHook should be called");
        assertEq(callee.bar(), 1, "Callee should be called");
    }

    function test_GivenPostHookReverts()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutorHasAHookConfigured
        givenPreHookSucceeds
    {
        // it should propagate the revert
        MockHook revertingHook = new MockHook();
        revertingHook.setRevertOnPostHook(true);
        MockExecutor executorWithHook = new MockExecutor();

        vm.startPrank(address(ep));
        kernel.installModule(2, address(executorWithHook), abi.encode(hex"", abi.encodePacked(address(revertingHook))));
        vm.stopPrank();

        vm.expectRevert("postHook reverted");
        executorWithHook.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, address(callee), 0, MockCallee.foo.selector
        );
    }

    function test_GivenPostHookSucceeds()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutorHasAHookConfigured
        givenPreHookSucceeds
    {
        // it should return the execution results
        MockHook mockHook = new MockHook();
        MockExecutor executorWithHook = new MockExecutor();

        vm.startPrank(address(ep));
        kernel.installModule(2, address(executorWithHook), abi.encode(hex"", abi.encodePacked(address(mockHook))));
        vm.stopPrank();

        bytes[] memory results = executorWithHook.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, address(callee), 0, MockCallee.foo.selector
        );

        assertEq(results.length, 1, "Should return one result");
    }

    function test_GivenTheExecutorHasHookSetToAddress1() external whenTheCallerIsAnInstalledExecutor {
        // it should skip preHook and postHook calls
        // it should execute the requested operations directly
        MockExecutor executorNoHook = new MockExecutor();

        vm.startPrank(address(ep));
        // address(1) means skip hooks
        kernel.installModule(2, address(executorNoHook), abi.encode(hex"", abi.encodePacked(address(1))));
        vm.stopPrank();

        uint256 barBefore = callee.bar();
        executorNoHook.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, address(callee), 0, MockCallee.foo.selector
        );

        assertEq(callee.bar(), barBefore + 1, "Callee should be called directly");
    }

    modifier givenTheExecutionModeCallTypeIsSINGLE() {
        _;
    }

    modifier givenTheExecutionModeExecTypeIsDEFAULT() {
        _;
    }

    function test_WhenTheTargetCallSucceeds()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsSINGLE
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should return the result in returnData array
        bytes[] memory results = testExecutor.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, address(callee), 0, MockCallee.foo.selector
        );

        assertEq(results.length, 1, "Should return one result");
        assertEq(callee.bar(), 1, "Callee should be called");
    }

    function test_WhenTheTargetCallReverts()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsSINGLE
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should propagate the revert
        vm.expectRevert(MockCallee.Haha.selector);
        testExecutor.executeViaKernel(
            kernel,
            LibERC7579.CALLTYPE_SINGLE,
            LibERC7579.EXECTYPE_DEFAULT,
            address(callee),
            0,
            MockCallee.forceRevert.selector
        );
    }

    modifier givenTheExecutionModeExecTypeIsTRY() {
        _;
    }

    function test_WhenTheTargetCallSucceeds_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsSINGLE
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should return the result in returnData array
        bytes[] memory results = testExecutor.executeViaKernel(
            kernel, LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_TRY, address(callee), 0, MockCallee.foo.selector
        );

        assertEq(results.length, 1, "Should return one result");
        assertEq(callee.bar(), 1, "Callee should be called");
    }

    function test_WhenTheTargetCallReverts_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsSINGLE
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should NOT propagate the revert
        // it should return empty bytes for the failed call
        bytes[] memory results = testExecutor.executeViaKernel(
            kernel,
            LibERC7579.CALLTYPE_SINGLE,
            LibERC7579.EXECTYPE_TRY,
            address(callee),
            0,
            MockCallee.forceRevert.selector
        );

        assertEq(results.length, 1, "Should return one result");
        assertEq(callee.bar(), 0, "Callee should NOT be called");
    }

    modifier givenTheExecutionModeCallTypeIsBATCH() {
        _;
    }

    function test_WhenAllCallsSucceed()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsBATCH
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should return all results in returnData array
        bytes[] memory results = testExecutor.executeBatchViaKernel(kernel, LibERC7579.EXECTYPE_DEFAULT, 3);

        assertEq(results.length, 3, "Should return three results");
        // Note: MockExecutor.executeBatchViaKernel calls kernel.accountId(), not callee
    }

    function test_WhenAnyCallReverts()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsBATCH
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should propagate the revert
        vm.expectRevert(MockCallee.Haha.selector);
        testExecutor.executeBatchWithRevertViaKernel(kernel, LibERC7579.EXECTYPE_DEFAULT);
    }

    function test_WhenAllCallsSucceed_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsBATCH
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should return all results in returnData array
        bytes[] memory results = testExecutor.executeBatchViaKernel(kernel, LibERC7579.EXECTYPE_TRY, 3);

        assertEq(results.length, 3, "Should return three results");
        // Note: MockExecutor.executeBatchViaKernel calls kernel.accountId(), not callee
    }

    function test_WhenAnyCallReverts_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsBATCH
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should NOT propagate the revert
        // it should return empty bytes for the failed call
        // it should continue executing remaining calls
        bytes[] memory results = testExecutor.executeBatchWithRevertViaKernel(kernel, LibERC7579.EXECTYPE_TRY);

        assertEq(results.length, 3, "Should return three results");
        // First and third calls succeed (kernel.accountId()), second reverts (forceRevert)
        // Note: MockExecutor calls kernel.accountId() for first and third, not callee
    }

    modifier givenTheExecutionModeCallTypeIsDELEGATECALL() {
        _;
    }

    function test_WhenTheDelegatecallSucceeds()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsDELEGATECALL
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should return the result
        bytes[] memory results = testExecutor.executeDelegatecallViaKernel(kernel, LibERC7579.EXECTYPE_DEFAULT, false);

        assertEq(results.length, 1, "Should return one result");
    }

    function test_WhenTheDelegatecallReverts()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsDELEGATECALL
        givenTheExecutionModeExecTypeIsDEFAULT
    {
        // it should propagate the revert
        vm.expectRevert("MockAction: revert");
        testExecutor.executeDelegatecallViaKernel(kernel, LibERC7579.EXECTYPE_DEFAULT, true);
    }

    function test_WhenTheDelegatecallSucceeds_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsDELEGATECALL
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should return the result
        bytes[] memory results = testExecutor.executeDelegatecallViaKernel(kernel, LibERC7579.EXECTYPE_TRY, false);

        assertEq(results.length, 1, "Should return one result");
    }

    function test_WhenTheDelegatecallReverts_GivenTheExecutionModeExecTypeIsTRY()
        external
        whenTheCallerIsAnInstalledExecutor
        givenTheExecutionModeCallTypeIsDELEGATECALL
        givenTheExecutionModeExecTypeIsTRY
    {
        // it should NOT propagate the revert
        // it should return empty bytes
        bytes[] memory results = testExecutor.executeDelegatecallViaKernel(kernel, LibERC7579.EXECTYPE_TRY, true);

        assertEq(results.length, 1, "Should return one result");
    }

    function test_GivenTheExecutionModeCallTypeIsUnsupported() external whenTheCallerIsAnInstalledExecutor {
        // it should revert with InvalidCallType error
        vm.expectRevert(InvalidCallType.selector);
        testExecutor.executeViaKernelWithCallType(kernel, bytes1(0x03), LibERC7579.EXECTYPE_DEFAULT);
    }
}
