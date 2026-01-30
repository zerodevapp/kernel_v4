// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";
import {Unauthorized, InvalidNonce} from "src/types/Error.sol";

abstract contract Kernel_setValidNonceFrom is BTTModifiers {
    function test_WhenTheCallerIsNotTheEntryPointOrSelf() external {
        // it should revert with Unauthorized error
        vm.stopPrank();
        vm.startPrank(makeAddr("randomCaller"));

        vm.expectRevert(Unauthorized.selector);
        kernel.setValidNonceFrom(1);
    }

    modifier whenTheCallerIsTheEntryPointOrSelf() {
        vm.stopPrank();
        vm.startPrank(address(ep));
        _;
    }

    function test_WhenSettingANewValidNonceFromValue() external whenTheCallerIsTheEntryPointOrSelf {
        // it should update the validNonceFrom storage
        uint64 newSeq = 100;
        kernel.setValidNonceFrom(newSeq);

        // Verify by trying to set a lower value (will revert if the first call succeeded)
        vm.expectRevert(InvalidNonce.selector);
        kernel.setValidNonceFrom(newSeq);

        // Set to higher value should succeed
        uint64 higherSeq = 200;
        kernel.setValidNonceFrom(higherSeq);
    }

    modifier whenValidatingNonces() {
        _;
    }

    function test_GivenTheNonceIsBelowValidNonceFrom()
        external
        whenTheCallerIsTheEntryPointOrSelf
        whenValidatingNonces
    {
        // it should be invalid
        // First set validNonceFrom to a value
        kernel.setValidNonceFrom(10);

        // Try to set to a lower value (should revert because nonce below validNonceFrom)
        vm.expectRevert(InvalidNonce.selector);
        kernel.setValidNonceFrom(5);
    }

    function test_GivenTheNonceIsAtOrAboveValidNonceFrom()
        external
        whenTheCallerIsTheEntryPointOrSelf
        whenValidatingNonces
    {
        // it should be valid
        // First set validNonceFrom to 10
        kernel.setValidNonceFrom(10);

        // Setting to 20 (above 10) should succeed
        kernel.setValidNonceFrom(20);

        // Setting to 30 (above 20) should also succeed
        kernel.setValidNonceFrom(30);

        // Verify by checking that setting to a lower value reverts
        vm.expectRevert(InvalidNonce.selector);
        kernel.setValidNonceFrom(29);
    }
}
