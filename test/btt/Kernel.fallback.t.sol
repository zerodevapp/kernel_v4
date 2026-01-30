// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";
import {Kernel} from "src/Kernel.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import {InvalidSelector, InvalidCallType} from "src/types/Error.sol";
import {MockFallback} from "../mock/MockFallback.sol";

abstract contract Kernel_fallback is BTTModifiers {
    function test_WhenTheSelectorIsOnERC721Received() external {
        // it should return the selector as magic value
        bytes4 selector = IERC721Receiver.onERC721Received.selector;
        (bool success, bytes memory result) = address(kernel).call(
            abi.encodeWithSelector(selector, address(this), address(this), 1, "")
        );
        assertTrue(success, "Call should succeed");
        assertEq(abi.decode(result, (bytes4)), selector, "Should return magic value");
    }

    function test_WhenTheSelectorIsOnERC1155Received() external {
        // it should return the selector as magic value
        bytes4 selector = IERC1155Receiver.onERC1155Received.selector;
        (bool success, bytes memory result) = address(kernel).call(
            abi.encodeWithSelector(selector, address(this), address(this), 1, 1, "")
        );
        assertTrue(success, "Call should succeed");
        assertEq(abi.decode(result, (bytes4)), selector, "Should return magic value");
    }

    function test_WhenTheSelectorIsOnERC1155BatchReceived() external {
        // it should return the selector as magic value
        bytes4 selector = IERC1155Receiver.onERC1155BatchReceived.selector;
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        (bool success, bytes memory result) = address(kernel).call(
            abi.encodeWithSelector(selector, address(this), address(this), ids, amounts, "")
        );
        assertTrue(success, "Call should succeed");
        assertEq(abi.decode(result, (bytes4)), selector, "Should return magic value");
    }

    modifier whenTheSelectorIsACustomRegisteredSelector() {
        _;
    }

    function test_GivenTheSelectorIsNotRegistered() external whenTheSelectorIsACustomRegisteredSelector {
        // it should revert with InvalidSelector error
        bytes4 unregisteredSelector = bytes4(keccak256("unregistered()"));
        vm.expectRevert(InvalidSelector.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(unregisteredSelector));
        // expectRevert handles the revert check
    }

    /*//////////////////////////////////////////////////////////////
                    HOOK = ADDRESS(0) BRANCH
    //////////////////////////////////////////////////////////////*/

    modifier givenTheSelectorIsRegisteredButHookIsAddress0() {
        _;
    }

    function test_WhenTheCallerIsNotTheEntryPoint()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
    {
        // it should revert with InvalidSelector error
        vm.stopPrank();
        vm.startPrank(address(ep));

        // Register fallback with hook=address(0)
        bytes4 testSelector = bytes4(keccak256("testHook0()"));
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(0), // hook = address(0)
            bytes1(0x00) // callType = CALL
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));
        vm.stopPrank();

        // Call from non-EntryPoint
        address randomCaller = makeAddr("randomCaller");
        vm.startPrank(randomCaller);
        vm.expectRevert(InvalidSelector.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    modifier whenTheCallerIsTheEntryPoint() {
        _;
    }

    modifier givenCallTypeIsCALL() {
        _;
    }

    function test_GivenCallTypeIsCALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsCALL
    {
        // it should call the target with msgdata plus msgsender
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testCallHook0()"));
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(0),
            bytes1(0x00) // CALL
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Call should succeed");
    }

    function test_WhenTheTargetCallSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsCALL
    {
        // it should return the call result
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testSuccess0()"));
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(0),
            bytes1(0x00)
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success, bytes memory result) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Call should succeed and return result");
    }

    function test_WhenTheTargetCallReverts()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsCALL
    {
        // it should propagate the revert
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = MockFallback.forceRevert.selector;
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(0),
            bytes1(0x00)
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        vm.expectRevert(MockFallback.FallbackRevert.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    modifier givenCallTypeIsDELEGATECALL() {
        _;
    }

    function test_GivenCallTypeIsDELEGATECALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsDELEGATECALL
    {
        // it should delegatecall the target with msgdata
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testDelegateHook0()"));
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(0),
            bytes1(0x01) // DELEGATECALL
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Delegatecall should succeed");
    }

    function test_WhenTheDelegatecallSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsDELEGATECALL
    {
        // it should return the delegatecall result
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testDelegateSuccess0()"));
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(0),
            bytes1(0x01)
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Delegatecall should return result");
    }

    function test_WhenTheDelegatecallReverts()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsDELEGATECALL
    {
        // it should propagate the revert
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = MockFallback.forceRevert.selector;
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(0),
            bytes1(0x01)
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        vm.expectRevert(MockFallback.FallbackRevert.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    function test_GivenCallTypeIsUnsupported()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
    {
        // it should revert with InvalidCallType error
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testUnsupported0()"));
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(0),
            bytes1(0x02) // Unsupported call type
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        vm.expectRevert(InvalidCallType.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    /*//////////////////////////////////////////////////////////////
                    HOOK = ADDRESS(1) BRANCH
    //////////////////////////////////////////////////////////////*/

    modifier givenTheSelectorIsRegisteredWithHookSetToAddress1() {
        _;
    }

    function test_GivenTheSelectorIsRegisteredWithHookSetToAddress1()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
    {
        // it should skip preHook and postHook
        // it should allow any caller
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testHook1()"));
        bytes memory fallbackConfig = abi.encodePacked(
            address(mockFallback),
            address(1), // hook = address(1) - skip hooks
            bytes1(0x00)
        );
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));
        vm.stopPrank();

        // Call from any address should work
        address anyCaller = makeAddr("anyCaller");
        vm.startPrank(anyCaller);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Any caller should succeed with hook=address(1)");
    }

    function test_GivenCallTypeIsCALL_GivenCallTypeIsCALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
        givenCallTypeIsCALL
    {
        // it should call the target with msgdata plus msgsender
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testCall1()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(1), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Call should succeed");
    }

    function test_WhenTheTargetCallSucceeds_GivenCallTypeIsCALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
        givenCallTypeIsCALL
    {
        // it should return the call result
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testSuccess1()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(1), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Should return call result");
    }

    function test_WhenTheTargetCallReverts_GivenCallTypeIsCALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
        givenCallTypeIsCALL
    {
        // it should propagate the revert
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = MockFallback.forceRevert.selector;
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(1), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        vm.expectRevert(MockFallback.FallbackRevert.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    function test_GivenCallTypeIsDELEGATECALL_GivenCallTypeIsDELEGATECALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
        givenCallTypeIsDELEGATECALL
    {
        // it should delegatecall the target with msgdata
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testDelegate1()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(1), bytes1(0x01));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Delegatecall should succeed");
    }

    function test_WhenTheDelegatecallSucceeds_GivenCallTypeIsDELEGATECALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
        givenCallTypeIsDELEGATECALL
    {
        // it should return the delegatecall result
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testDelegateSuccess1()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(1), bytes1(0x01));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Should return delegatecall result");
    }

    function test_WhenTheDelegatecallReverts_GivenCallTypeIsDELEGATECALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
        givenCallTypeIsDELEGATECALL
    {
        // it should propagate the revert
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = MockFallback.forceRevert.selector;
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(1), bytes1(0x01));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        vm.expectRevert(MockFallback.FallbackRevert.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    function test_GivenCallTypeIsUnsupported_GivenTheSelectorIsRegisteredWithHookSetToAddress1()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
    {
        // it should revert with InvalidCallType error
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testUnsupported1()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(1), bytes1(0x02));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        vm.expectRevert(InvalidCallType.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    /*//////////////////////////////////////////////////////////////
                    HOOK = CONTRACT BRANCH
    //////////////////////////////////////////////////////////////*/

    modifier givenTheSelectorIsRegisteredWithAHookContract() {
        _;
    }

    function test_GivenTheSelectorIsRegisteredWithAHookContract()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
    {
        // it should call preHook on the hook with msgdata
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testHookContract()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        hook.resetState();
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Call should succeed");
        assertTrue(hook.preHookCalled(), "preHook should be called");
    }

    function test_GivenPreHookReverts()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
    {
        // it should propagate the revert
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testPreHookRevert()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        hook.setRevertOnPreHook(true);
        vm.expectRevert("preHook reverted");
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    modifier givenPreHookSucceeds() {
        _;
    }

    function test_GivenCallTypeIsCALL_GivenCallTypeIsCALL_GivenPreHookSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsCALL
    {
        // it should call the target with msgdata plus msgsender
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testCallHookContract()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Call should succeed");
    }

    modifier whenTheTargetCallSucceeds() {
        _;
    }

    function test_WhenTheTargetCallSucceeds_WhenTheTargetCallSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsCALL
        whenTheTargetCallSucceeds
    {
        // it should call postHook with the context from preHook
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testPostHook()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        hook.resetState();
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Call should succeed");
        assertTrue(hook.postHookCalled(), "postHook should be called");
    }

    function test_GivenPostHookReverts()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsCALL
        whenTheTargetCallSucceeds
    {
        // it should propagate the revert
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testPostHookRevert()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        hook.setRevertOnPostHook(true);
        vm.expectRevert("postHook reverted");
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    function test_GivenPostHookSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsCALL
        whenTheTargetCallSucceeds
    {
        // it should return the call result
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testPostHookSuccess()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Should return call result");
    }

    function test_WhenTheTargetCallReverts_GivenCallTypeIsCALL_GivenPreHookSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsCALL
    {
        // it should propagate the revert and skip postHook
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = MockFallback.forceRevert.selector;
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x00));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        hook.resetState();
        vm.expectRevert(MockFallback.FallbackRevert.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    function test_GivenCallTypeIsDELEGATECALL_GivenCallTypeIsDELEGATECALL_GivenPreHookSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsDELEGATECALL
    {
        // it should delegatecall the target with msgdata
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testDelegateHookContract()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x01));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Delegatecall should succeed");
    }

    modifier whenTheDelegatecallSucceeds() {
        _;
    }

    function test_WhenTheDelegatecallSucceeds_WhenTheDelegatecallSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsDELEGATECALL
        whenTheDelegatecallSucceeds
    {
        // it should call postHook with the context from preHook
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testDelegatePostHook()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x01));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        hook.resetState();
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Delegatecall should succeed");
        assertTrue(hook.postHookCalled(), "postHook should be called");
    }

    function test_GivenPostHookReverts_WhenTheDelegatecallSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsDELEGATECALL
        whenTheDelegatecallSucceeds
    {
        // it should propagate the revert
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testDelegatePostRevert()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x01));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        hook.setRevertOnPostHook(true);
        vm.expectRevert("postHook reverted");
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    function test_GivenPostHookSucceeds_WhenTheDelegatecallSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsDELEGATECALL
        whenTheDelegatecallSucceeds
    {
        // it should return the delegatecall result
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testDelegatePostSuccess()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x01));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
        assertTrue(success, "Should return delegatecall result");
    }

    function test_WhenTheDelegatecallReverts_GivenCallTypeIsDELEGATECALL_GivenPreHookSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsDELEGATECALL
    {
        // it should propagate the revert and skip postHook
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = MockFallback.forceRevert.selector;
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x01));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        vm.expectRevert(MockFallback.FallbackRevert.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }

    function test_GivenCallTypeIsUnsupported_GivenPreHookSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
    {
        // it should revert with InvalidCallType error
        vm.stopPrank();
        vm.startPrank(address(ep));

        bytes4 testSelector = bytes4(keccak256("testUnsupportedHook()"));
        bytes memory fallbackConfig = abi.encodePacked(address(mockFallback), address(hook), bytes1(0x02));
        kernel.installModule(3, address(0), abi.encode(testSelector, fallbackConfig, hex""));

        vm.expectRevert(InvalidCallType.selector);
        (bool success,) = address(kernel).call(abi.encodeWithSelector(testSelector));
    }
}
