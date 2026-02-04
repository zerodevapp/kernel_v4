// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {StakerBTTModifiers} from "./StakerBTTModifiers.sol";
import {APPROVE_FACTORY_STRUCT_HASH} from "src/types/Constants.sol";
import {EfficientHashLib} from "solady/utils/EfficientHashLib.sol";
import {Staker} from "src/Staker.sol";

abstract contract Staker_approveFactoryWithSignature is StakerBTTModifiers {
    function setUp() public override {
        _initializeStaker();
    }

    modifier givenTheSignatureIsValid() override {
        _;
    }

    function test_GivenTheSignatureIsInvalid() external {
        // it should revert with "InvalidSignature"
        (, uint256 wrongKey) = makeAddrAndKey("wrongOwner");

        uint256 nonce = staker.nonces(factoryAddr);
        bytes32 structHash = EfficientHashLib.hash(
            uint256(APPROVE_FACTORY_STRUCT_HASH), uint256(uint160(factoryAddr)), uint256(1), nonce
        );
        bytes32 digest = _hashTypedDataSansChainId(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Staker.InvalidSignature.selector);
        staker.approveFactoryWithSignature(factoryAddr, true, signature);
    }

    function test_GivenTheSignatureIsValid() external givenTheSignatureIsValid {
        // it should set the factory approval
        // it should allow cross-chain signatures (sans chainId)
        uint256 nonce = staker.nonces(factoryAddr);
        bytes32 structHash = EfficientHashLib.hash(
            uint256(APPROVE_FACTORY_STRUCT_HASH), uint256(uint160(factoryAddr)), uint256(1), nonce
        );
        bytes32 digest = _hashTypedDataSansChainId(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertFalse(staker.approved(factoryAddr), "Factory should not be approved before");

        staker.approveFactoryWithSignature(factoryAddr, true, signature);

        assertTrue(staker.approved(factoryAddr), "Factory should be approved via signature");
    }
}
