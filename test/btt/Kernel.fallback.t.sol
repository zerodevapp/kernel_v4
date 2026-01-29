// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";

abstract contract Kernel_fallback is BTTModifiers {
    function test_WhenTheSelectorIsOnERC721Received() external {
        // it should return the selector as magic value
    }

    function test_WhenTheSelectorIsOnERC1155Received() external {
        // it should return the selector as magic value
    }

    function test_WhenTheSelectorIsOnERC1155BatchReceived() external {
        // it should return the selector as magic value
    }

    modifier whenTheSelectorIsACustomRegisteredSelector() {
        _;
    }

    function test_GivenTheSelectorIsNotRegistered() external whenTheSelectorIsACustomRegisteredSelector {
        // it should revert with InvalidSelector error
    }

    modifier givenTheSelectorIsRegisteredButHookIsAddress0() {
        _;
    }

    function test_WhenTheCallerIsNotTheEntryPoint()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
    {
        // it should revert with InvalidSelector error
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
    }

    function test_WhenTheTargetCallSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsCALL
    {
        // it should return the call result
    }

    function test_WhenTheTargetCallReverts()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsCALL
    {
        // it should propagate the revert
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
    }

    function test_WhenTheDelegatecallSucceeds()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsDELEGATECALL
    {
        // it should return the delegatecall result
    }

    function test_WhenTheDelegatecallReverts()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredButHookIsAddress0
        whenTheCallerIsTheEntryPoint
        givenCallTypeIsDELEGATECALL
    {
        // it should propagate the revert
    }

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
    }

    function test_GivenCallTypeIsCALL_GivenTheSelectorIsRegisteredWithHookSetToAddress1()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
    {
        // it should call the target with msgdata plus msgsender
    }

    function test_GivenCallTypeIsDELEGATECALL_GivenTheSelectorIsRegisteredWithHookSetToAddress1()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithHookSetToAddress1
    {
        // it should delegatecall the target with msgdata
    }

    modifier givenTheSelectorIsRegisteredWithAHookContract() {
        _;
    }

    function test_GivenTheSelectorIsRegisteredWithAHookContract()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
    {
        // it should call preHook on the hook with msgdata
    }

    function test_GivenPreHookReverts()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
    {
        // it should propagate the revert
    }

    modifier givenPreHookSucceeds() {
        _;
    }

    function test_GivenCallTypeIsCALL_GivenCallTypeIsCALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsCALL
    {
        // it should call the target with msgdata plus msgsender
    }

    function test_WhenTheTargetCallSucceeds_GivenCallTypeIsCALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsCALL
    {
        // it should call postHook with the context from preHook
        // it should return the call result
    }

    function test_WhenTheTargetCallReverts_GivenCallTypeIsCALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsCALL
    {
        // it should propagate the revert and skip postHook
    }

    function test_GivenCallTypeIsDELEGATECALL_GivenCallTypeIsDELEGATECALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsDELEGATECALL
    {
        // it should delegatecall the target with msgdata
    }

    function test_WhenTheDelegatecallSucceeds_GivenCallTypeIsDELEGATECALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsDELEGATECALL
    {
        // it should call postHook with the context from preHook
        // it should return the delegatecall result
    }

    function test_WhenTheDelegatecallReverts_GivenCallTypeIsDELEGATECALL()
        external
        whenTheSelectorIsACustomRegisteredSelector
        givenTheSelectorIsRegisteredWithAHookContract
        givenPreHookSucceeds
        givenCallTypeIsDELEGATECALL
    {
        // it should propagate the revert and skip postHook
    }
}
