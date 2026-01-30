// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {StakerBTTModifiers} from "./StakerBTTModifiers.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Ownable} from "solady/auth/Ownable.sol";

abstract contract Staker_stake is StakerBTTModifiers {
    function setUp() public {
        _initializeStaker();
    }

    function test_WhenTheCallerIsNotTheOwner() external {
        // it should revert with Unauthorized error
        address notOwner = makeAddr("notOwner");
        vm.deal(notOwner, 10 ether);

        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        staker.stake{value: 1 ether}(ep, 1 days);
    }

    modifier whenTheCallerIsTheOwner() override {
        vm.startPrank(owner);
        _;
        vm.stopPrank();
    }

    function test_GivenMsgValueIsZero() external whenTheCallerIsTheOwner {
        // it should call addStake with zero value
        IEntryPoint.DepositInfo memory infoBefore = ep.getDepositInfo(address(staker));

        vm.prank(owner);
        staker.stake{value: 0}(ep, 1 days);

        IEntryPoint.DepositInfo memory infoAfter = ep.getDepositInfo(address(staker));
        assertEq(infoAfter.stake, infoBefore.stake, "Stake should not change with zero value");
    }

    function test_GivenMsgValueIsGreaterThanZero() external whenTheCallerIsTheOwner {
        // it should call addStake on the EntryPoint
        // it should increase the stake by msg value
        uint256 stakeAmount = 1 ether;
        IEntryPoint.DepositInfo memory infoBefore = ep.getDepositInfo(address(staker));

        vm.prank(owner);
        staker.stake{value: stakeAmount}(ep, 1 days);

        IEntryPoint.DepositInfo memory infoAfter = ep.getDepositInfo(address(staker));
        assertEq(infoAfter.stake, infoBefore.stake + stakeAmount, "Stake should increase by msg.value");
        assertTrue(infoAfter.staked, "Should be staked");
    }
}
