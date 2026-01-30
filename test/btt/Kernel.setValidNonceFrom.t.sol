// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BTTModifiers} from "./BTTModifiers.sol";
import {Unauthorized, InvalidNonce} from "src/types/Error.sol";

abstract contract Kernel_setValidNonceFrom is BTTModifiers {
    function test_WhenCallerIsNotEntryPoint() external {
        // it should revert with Unauthorized error
        vm.stopPrank();
        vm.startPrank(makeAddr("randomCaller"));

        vm.expectRevert(Unauthorized.selector);
        kernel.setValidNonceFrom(1);
    }

    modifier whenCallerIsEntryPointOrSelf() override {
        vm.stopPrank();
        vm.startPrank(address(ep));
        _;
    }

    function test_GivenSeqIsLessThanOrEqualToCurrentValidNonceFrom() external whenCallerIsEntryPointOrSelf {
        // it should revert with InvalidNonce error
        // First set validNonceFrom to a value
        kernel.setValidNonceFrom(10);

        // Try to set to a lower value (should revert)
        vm.expectRevert(InvalidNonce.selector);
        kernel.setValidNonceFrom(5);

        // Try to set to the same value (should also revert since it must be greater)
        vm.expectRevert(InvalidNonce.selector);
        kernel.setValidNonceFrom(10);
    }

    function test_GivenSeqIsGreaterThanCurrentValidNonceFrom() external whenCallerIsEntryPointOrSelf {
        // it should update validNonceFrom to seq
        uint64 newSeq = 100;
        kernel.setValidNonceFrom(newSeq);

        // Verify by trying to set a lower value (will revert if the first call succeeded)
        vm.expectRevert(InvalidNonce.selector);
        kernel.setValidNonceFrom(newSeq);

        // Set to higher value should succeed
        uint64 higherSeq = 200;
        kernel.setValidNonceFrom(higherSeq);

        // Verify by trying to set lower again
        vm.expectRevert(InvalidNonce.selector);
        kernel.setValidNonceFrom(higherSeq);
    }
}
