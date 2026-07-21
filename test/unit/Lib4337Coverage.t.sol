// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Lib4337Harness} from "../mock/Lib4337Harness.sol";
import {Lib4337} from "src/lib/Lib4337.sol";
import {ValidityFormatMismatch} from "src/types/Error.sol";

/// @notice Unit tests for Lib4337.intersectValidationData covering all quadrants
/// and edge cases for aggregator handling.
/// @author taek <leekt216@gmail.com>
contract Lib4337CoverageTest is Test {
    Lib4337Harness harness;

    /// @dev MODE_BIT from Lib4337 - highest bit of uint48, marks block-number format
    uint48 internal constant MODE_BIT = 0x800000000000;

    uint48 internal constant _T_AFTER = 100;
    uint48 internal constant _T_UNTIL = 200;

    uint48 internal constant _UNBOUNDED_BLOCK_AFTER = MODE_BIT | 10;
    uint48 internal constant _BOUNDED_BLOCK_AFTER = MODE_BIT | 20;
    uint48 internal constant _BOUNDED_BLOCK_UNTIL = MODE_BIT | 100;

    function setUp() public {
        harness = new Lib4337Harness();
    }

    function _pack(uint48 validAfter, uint48 validUntil, address result) internal pure returns (uint256) {
        return (uint256(validAfter) << 208) | (uint256(validUntil) << 160) | uint160(result);
    }

    // =========================================================================
    // parseValidationData
    // =========================================================================

    function test_parseValidationData_WhenZero_ShouldReturnDefaultValues() public view {
        (uint48 validAfter, uint48 validUntil, address result) = harness.parseValidationData(0);
        assertEq(validAfter, 0, "validAfter should be 0");
        assertEq(validUntil, type(uint48).max, "validUntil should be max when encoded as 0");
        assertEq(result, address(0), "result should be address(0)");
    }

    function test_parseValidationData_WhenSigValidationFailed_ShouldReturnAddress1() public view {
        (uint48 validAfter, uint48 validUntil, address result) = harness.parseValidationData(1);
        assertEq(validAfter, 0, "validAfter should be 0");
        assertEq(validUntil, type(uint48).max, "validUntil should be max");
        assertEq(result, address(1), "result should be address(1) for SIG_VALIDATION_FAILED");
    }

    function test_parseValidationData_WhenTimeBoundsSet_ShouldReturnCorrectBounds() public view {
        // Pack: validAfter=100, validUntil=200, result=address(0)
        uint256 packed = (uint256(100) << 208) | (uint256(200) << 160);
        (uint48 validAfter, uint48 validUntil, address result) = harness.parseValidationData(packed);
        assertEq(validAfter, 100, "validAfter should be 100");
        assertEq(validUntil, 200, "validUntil should be 200");
        assertEq(result, address(0), "result should be address(0)");
    }

    // =========================================================================
    // checkValidation
    // =========================================================================

    function test_checkValidation_WhenSuccess_ShouldReturnTrue() public view {
        assertTrue(harness.checkValidation(0), "Zero validationData means success");
    }

    function test_checkValidation_WhenFailed_ShouldReturnFalse() public view {
        assertFalse(harness.checkValidation(1), "SIG_VALIDATION_FAILED should return false");
    }

    function test_checkValidation_WhenExpired_ShouldReturnFalse() public {
        // Set validUntil in the past
        vm.warp(1000);
        uint256 packed = (uint256(0) << 208) | (uint256(500) << 160); // validUntil = 500, now = 1000
        assertFalse(harness.checkValidation(packed), "Expired validUntil should return false");
    }

    function test_checkValidation_WhenNotYetValid_ShouldReturnFalse() public {
        // Set validAfter in the future
        vm.warp(100);
        uint256 packed = (uint256(500) << 208) | (uint256(1000) << 160); // validAfter = 500, now = 100
        assertFalse(harness.checkValidation(packed), "Future validAfter should return false");
    }

    function test_checkValidation_WhenCurrentEqualsValidAfter_ShouldReturnFalse() public {
        // Canonical EP v0.9 interval is (validAfter, validUntil] — exclusive lower bound.
        vm.warp(500);
        uint256 packed = (uint256(500) << 208) | (uint256(1000) << 160); // validAfter = 500, now = 500
        assertFalse(harness.checkValidation(packed), "current == validAfter must be excluded");
    }

    function test_checkValidation_WhenCurrentEqualsValidUntil_ShouldReturnTrue() public {
        // Inclusive upper bound: current == validUntil is still valid.
        vm.warp(1000);
        uint256 packed = (uint256(0) << 208) | (uint256(1000) << 160); // validAfter = 0, validUntil = 1000
        assertTrue(harness.checkValidation(packed), "current == validUntil must be included");
    }

    function test_checkValidation_WhenBlockNumberModeValid_ShouldReturnTrue() public {
        uint48 modeBit = 0x800000000000;
        vm.roll(1000);
        vm.warp(1); // timestamp small, proves block.number is used not timestamp
        // masked validAfter = 500, masked validUntil = 2000, block.number = 1000
        uint256 packed = (uint256(modeBit | 500) << 208) | (uint256(modeBit | 2000) << 160);
        assertTrue(harness.checkValidation(packed), "block number mode within bounds should be valid");
    }

    function test_checkValidation_WhenBlockNumberModeExpired_ShouldReturnFalse() public {
        uint48 modeBit = 0x800000000000;
        vm.roll(3000);
        // masked validUntil = 2000, block.number = 3000 > 2000
        uint256 packed = (uint256(modeBit | 500) << 208) | (uint256(modeBit | 2000) << 160);
        assertFalse(harness.checkValidation(packed), "block number past validUntil should be invalid");
    }

    function test_checkValidation_WhenBlockNumberModeNotYetValid_ShouldReturnFalse() public {
        uint48 modeBit = 0x800000000000;
        vm.roll(100);
        // masked validAfter = 500, block.number = 100 <= 500
        uint256 packed = (uint256(modeBit | 500) << 208) | (uint256(modeBit | 2000) << 160);
        assertFalse(harness.checkValidation(packed), "block number before validAfter should be invalid");
    }

    // -- remaining boundary points of the canonical (validAfter, validUntil] interval --

    function test_checkValidation_WhenCurrentIsOneAboveValidAfter_ShouldReturnTrue() public {
        vm.warp(501);
        uint256 packed = (uint256(500) << 208) | (uint256(1000) << 160); // validAfter=500, validUntil=1000
        assertTrue(harness.checkValidation(packed), "current == validAfter+1 must be included");
    }

    function test_checkValidation_WhenCurrentIsOneAboveValidUntil_ShouldReturnFalse() public {
        vm.warp(1001);
        uint256 packed = (uint256(0) << 208) | (uint256(1000) << 160); // validAfter=0, validUntil=1000
        assertFalse(harness.checkValidation(packed), "current == validUntil+1 must be excluded");
    }

    function test_checkValidation_BlockMode_WhenBlockNumberEqualsValidAfter_ShouldReturnFalse() public {
        vm.roll(_BOUNDED_BLOCK_AFTER & ~MODE_BIT);
        uint256 packed = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, address(0));
        assertFalse(harness.checkValidation(packed), "block.number == validAfter is excluded (open lower bound)");
    }

    function test_checkValidation_BlockMode_WhenBlockNumberIsOneAboveValidAfter_ShouldReturnTrue() public {
        vm.roll((_BOUNDED_BLOCK_AFTER & ~MODE_BIT) + 1);
        uint256 packed = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, address(0));
        assertTrue(harness.checkValidation(packed), "block.number == validAfter+1 is included");
    }

    function test_checkValidation_BlockMode_WhenBlockNumberEqualsValidUntil_ShouldReturnTrue() public {
        vm.roll(_BOUNDED_BLOCK_UNTIL & ~MODE_BIT);
        uint256 packed = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, address(0));
        assertTrue(harness.checkValidation(packed), "block.number == validUntil is included (closed upper bound)");
    }

    function test_checkValidation_BlockMode_WhenBlockNumberIsOneAboveValidUntil_ShouldReturnFalse() public {
        vm.roll((_BOUNDED_BLOCK_UNTIL & ~MODE_BIT) + 1);
        uint256 packed = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, address(0));
        assertFalse(harness.checkValidation(packed), "block.number == validUntil+1 is excluded");
    }

    function test_checkValidation_WhenRawValidUntilIsZero_ShouldNormalizeToUnboundedUpperBound() public {
        // Raw validUntil=0 must parse to type(uint48).max (no expiry), even far in the future.
        vm.warp(type(uint48).max - 1);
        uint256 packed = _pack(100, 0, address(0));
        assertTrue(harness.checkValidation(packed), "raw validUntil=0 must normalize to max, i.e. no expiry");
    }

    function test_checkValidation_WhenResultIsAggregatorAddress_ShouldReturnFalse() public {
        // Time bounds are satisfied (validAfter=0, validUntil raw=0 -> max) but result is a nonzero
        // aggregator address rather than the failure sentinel address(1); checkValidation requires res==0.
        vm.warp(500);
        uint256 packed = _pack(0, 0, address(0xBEEF));
        assertFalse(harness.checkValidation(packed), "nonzero aggregator result must be rejected");
    }

    // =========================================================================
    // _usesBlockNumberFormat
    // =========================================================================

    function test_usesBlockNumberFormat_WhenBothEqualModeBit_ShouldReturnTrue() public view {
        uint48 modeBit = 0x800000000000;
        assertTrue(harness.usesBlockNumberFormat(modeBit, modeBit), "equality with MODE_BIT counts as set");
    }

    function test_usesBlockNumberFormat_WhenBothAboveModeBit_ShouldReturnTrue() public view {
        uint48 modeBit = 0x800000000000;
        assertTrue(harness.usesBlockNumberFormat(modeBit | 5, modeBit | 9), "both above MODE_BIT is block format");
    }

    function test_usesBlockNumberFormat_WhenOnlyValidAfterSet_ShouldReturnFalse() public view {
        uint48 modeBit = 0x800000000000;
        assertFalse(harness.usesBlockNumberFormat(modeBit, 100), "only validAfter set is not block format");
    }

    function test_usesBlockNumberFormat_WhenOnlyValidUntilSet_ShouldReturnFalse() public view {
        uint48 modeBit = 0x800000000000;
        assertFalse(harness.usesBlockNumberFormat(100, modeBit), "only validUntil set is not block format");
    }

    function test_usesBlockNumberFormat_WhenNeitherSet_ShouldReturnFalse() public view {
        assertFalse(harness.usesBlockNumberFormat(100, 200), "timestamp bounds are not block format");
    }

    function test_usesBlockNumberFormat_WhenBothOneBelowModeBit_ShouldReturnFalse() public view {
        // All 47 lower bits set but MODE_BIT itself unset — the maximum non-block-format value.
        // Pins that the check is an exact bit test, not a magnitude comparison.
        uint48 justBelow = MODE_BIT - 1;
        assertFalse(
            harness.usesBlockNumberFormat(justBelow, justBelow), "MODE_BIT-1 on both must not count as block format"
        );
    }

    // =========================================================================
    // intersectValidationData — identity cases (a=0 or b=0)
    // =========================================================================

    function test_intersectValidationData_WhenAIsZero_ShouldReturnB() public view {
        uint256 b = (uint256(100) << 208) | (uint256(200) << 160);
        uint256 result = harness.intersectValidationData(0, b);
        assertEq(result, b, "When a=0, result should be b");
    }

    function test_intersectValidationData_WhenBIsZero_ShouldReturnA() public view {
        uint256 a = (uint256(100) << 208) | (uint256(200) << 160);
        uint256 result = harness.intersectValidationData(a, 0);
        assertEq(result, a, "When b=0, result should be a");
    }

    function test_intersectValidationData_WhenBothZero_ShouldReturnZero() public view {
        uint256 result = harness.intersectValidationData(0, 0);
        assertEq(result, 0, "Both zero should return zero");
    }

    // =========================================================================
    // intersectValidationData — time bounds quadrants
    // =========================================================================

    function test_intersectValidationData_WhenBothValid_ShouldIntersectTimeBounds() public view {
        // a: validAfter=100, validUntil=500
        // b: validAfter=200, validUntil=400
        // Expected: validAfter=max(100,200)=200, validUntil=min(500,400)=400
        uint256 a = (uint256(100) << 208) | (uint256(500) << 160);
        uint256 b = (uint256(200) << 208) | (uint256(400) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (uint48 validAfter, uint48 validUntil, address res) = harness.parseValidationData(result);

        assertEq(validAfter, 200, "validAfter should be max(100,200)=200");
        assertEq(validUntil, 400, "validUntil should be min(500,400)=400");
        assertEq(res, address(0), "Both success => result address(0)");
    }

    function test_intersectValidationData_WhenFirstExpired_ShouldPreserveNarrowerBounds() public view {
        // a: validAfter=0, validUntil=100 (expired when block.timestamp > 100)
        // b: validAfter=0, validUntil=200
        // Expected: validUntil=min(100,200)=100
        uint256 a = (uint256(0) << 208) | (uint256(100) << 160);
        uint256 b = (uint256(0) << 208) | (uint256(200) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (uint48 validAfter, uint48 validUntil,) = harness.parseValidationData(result);

        assertEq(validAfter, 0, "validAfter should be 0");
        assertEq(validUntil, 100, "validUntil should be min(100,200)=100");
    }

    function test_intersectValidationData_WhenSecondExpired_ShouldPreserveNarrowerBounds() public view {
        // a: validAfter=0, validUntil=500
        // b: validAfter=0, validUntil=50
        uint256 a = (uint256(0) << 208) | (uint256(500) << 160);
        uint256 b = (uint256(0) << 208) | (uint256(50) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (, uint48 validUntil,) = harness.parseValidationData(result);

        assertEq(validUntil, 50, "validUntil should be min(500,50)=50");
    }

    function test_intersectValidationData_WhenBothExpiredWithDifferentBounds_ShouldPickSmaller() public view {
        // a: validAfter=50, validUntil=100
        // b: validAfter=80, validUntil=90
        // Expected: validAfter=max(50,80)=80, validUntil=min(100,90)=90
        uint256 a = (uint256(50) << 208) | (uint256(100) << 160);
        uint256 b = (uint256(80) << 208) | (uint256(90) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (uint48 validAfter, uint48 validUntil,) = harness.parseValidationData(result);

        assertEq(validAfter, 80, "validAfter should be max(50,80)=80");
        assertEq(validUntil, 90, "validUntil should be min(100,90)=90");
    }

    function test_intersectValidationData_WhenValidUntilIsZero_ShouldTreatAsMaxUint48() public view {
        // validUntil=0 means "no expiry" (converted to type(uint48).max internally)
        // a: validAfter=0, validUntil=0 (no expiry)
        // b: validAfter=0, validUntil=500
        uint256 a = 1; // SIG_VALIDATION_FAILED with validUntil=0
        uint256 b = (uint256(500) << 160) | 1; // SIG_VALIDATION_FAILED with validUntil=500

        uint256 result = harness.intersectValidationData(a, b);
        (, uint48 validUntil,) = harness.parseValidationData(result);

        assertEq(validUntil, 500, "validUntil should be min(max,500)=500");
    }

    function test_intersectValidationData_WhenSecondValidUntilIsZero_ShouldTreatAsMaxUint48() public view {
        // Symmetric to the above: b's raw validUntil == 0 must normalize to max before min().
        uint256 a = (uint256(500) << 160) | 1; // SIG_VALIDATION_FAILED with validUntil=500
        uint256 b = 1; // SIG_VALIDATION_FAILED with validUntil=0

        uint256 result = harness.intersectValidationData(a, b);
        (, uint48 validUntil,) = harness.parseValidationData(result);

        assertEq(validUntil, 500, "validUntil should be min(500,max)=500");
    }

    // =========================================================================
    // intersectValidationData — aggregator logic
    // =========================================================================

    function test_intersectValidationData_WhenBothSuccess_ShouldReturnSuccess() public view {
        // Both have result=address(0) => success
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160);
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, address(0), "Both success => aggregator address(0)");
    }

    function test_intersectValidationData_WhenFirstFailed_ShouldReturnFailed() public view {
        // a has result=1 (failure), b has result=0 (success)
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160) | 1;
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, address(1), "Any failure => aggregator address(1)");
    }

    function test_intersectValidationData_WhenSecondFailed_ShouldReturnFailed() public view {
        // a has result=0, b has result=1
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160);
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160) | 1;

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, address(1), "Any failure => aggregator address(1)");
    }

    function test_intersectValidationData_WhenBothFailed_ShouldReturnFailed() public view {
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160) | 1;
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160) | 1;

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, address(1), "Both failure => aggregator address(1)");
    }

    function test_intersectValidationData_WhenAggregatorAndSuccess_ShouldPreserveAggregator() public view {
        // a has aggregator=address(0x1234), b has success
        address aggregator = address(0x1234);
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160) | uint160(aggregator);
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, aggregator, "Aggregator + success => preserve aggregator");
    }

    function test_intersectValidationData_WhenSuccessAndAggregator_ShouldAdoptAggregator() public view {
        // a has success, b has aggregator=address(0x5678)
        address aggregator = address(0x5678);
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160);
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160) | uint160(aggregator);

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, aggregator, "Success + aggregator => adopt aggregator");
    }

    function test_intersectValidationData_WhenSameAggregator_ShouldKeepIt() public view {
        address aggregator = address(0xABCD);
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160) | uint160(aggregator);
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160) | uint160(aggregator);

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, aggregator, "Same aggregator => keep it");
    }

    function test_intersectValidationData_WhenDifferentAggregators_ShouldFail() public view {
        address agg1 = address(0xAAAA);
        address agg2 = address(0xBBBB);
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160) | uint160(agg1);
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160) | uint160(agg2);

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, address(1), "Different aggregators => conflict => fail");
    }

    function test_intersectValidationData_WhenAggregatorAndFailure_ShouldReturnFailure() public view {
        address aggregator = address(0xDEAD);
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160) | uint160(aggregator);
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160) | 1;

        uint256 result = harness.intersectValidationData(a, b);
        (,, address res) = harness.parseValidationData(result);
        assertEq(res, address(1), "Aggregator + failure => failure takes precedence");
    }

    // =========================================================================
    // intersectValidationData — ValidityFormatMismatch
    // =========================================================================

    function test_intersectValidationData_WhenFormatMismatch_ShouldRevert() public {
        // Block number format: both validAfter and validUntil have MODE_BIT (0x800000000000) set
        uint48 modeBit = 0x800000000000;

        // a uses block number format (both have MODE_BIT set)
        uint256 a = (uint256(modeBit | 10) << 208) | (uint256(modeBit | 100) << 160);
        // b uses timestamp format (no MODE_BIT)
        uint256 b = (uint256(20) << 208) | (uint256(200) << 160);

        vm.expectRevert(ValidityFormatMismatch.selector);
        harness.intersectValidationData(a, b);
    }

    function test_intersectValidationData_WhenBothBlockNumberFormat_ShouldSucceed() public view {
        uint48 modeBit = 0x800000000000;

        uint256 a = (uint256(modeBit | 10) << 208) | (uint256(modeBit | 100) << 160);
        uint256 b = (uint256(modeBit | 20) << 208) | (uint256(modeBit | 80) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (uint48 validAfter, uint48 validUntil,) = harness.parseValidationData(result);
        assertEq(validAfter, modeBit | 20, "validAfter should be max with MODE_BIT");
        assertEq(validUntil, modeBit | 80, "validUntil should be min with MODE_BIT");
    }

    function test_intersectValidationData_WhenTimestampFormatMismatchReversed_ShouldRevert() public {
        uint48 modeBit = 0x800000000000;

        // a uses timestamp format
        uint256 a = (uint256(10) << 208) | (uint256(100) << 160);
        // b uses block number format
        uint256 b = (uint256(modeBit | 20) << 208) | (uint256(modeBit | 200) << 160);

        vm.expectRevert(ValidityFormatMismatch.selector);
        harness.intersectValidationData(a, b);
    }

    function test_intersectValidationData_WhenBlockModeWithZeroValidUntil_ShouldNotRevert() public view {
        // RP-01: normalization (validUntil==0 -> max) MUST happen before format classification.
        // a is block-number mode with no upper bound (raw validUntil field == 0).
        // Without normalize-first, a would classify as timestamp and falsely mismatch with b.
        uint48 modeBit = 0x800000000000;

        uint256 a = uint256(modeBit | 10) << 208; // validAfter = modeBit|10, validUntil raw = 0
        uint256 b = (uint256(modeBit | 20) << 208) | (uint256(modeBit | 80) << 160);

        uint256 result = harness.intersectValidationData(a, b);
        (uint48 validAfter, uint48 validUntil,) = harness.parseValidationData(result);

        assertEq(validAfter, modeBit | 20, "validAfter should be max(modeBit|10, modeBit|20)");
        assertEq(validUntil, modeBit | 80, "validUntil should be min(max, modeBit|80)");
    }

    function test_intersectValidationData_WhenBoundedBlockRangeIntersectsUnboundedBlockRange_ShouldNotRevert()
        public
        view
    {
        // Same as WhenBlockModeWithZeroValidUntil_ShouldNotRevert but with operand order swapped —
        // normalize-before-classify must not depend on which side carries the raw-zero validUntil.
        uint256 unbounded = _pack(_UNBOUNDED_BLOCK_AFTER, 0, address(0));
        uint256 bounded = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, address(0));

        uint256 result = harness.intersectValidationData(bounded, unbounded);
        (uint48 validAfter, uint48 validUntil,) = harness.parseValidationData(result);

        assertEq(validAfter, _BOUNDED_BLOCK_AFTER, "validAfter should be max(unbounded, bounded)");
        assertEq(validUntil, _BOUNDED_BLOCK_UNTIL, "validUntil should be min(max, bounded)");
    }

    function test_intersectValidationData_WhenNormalizedUnboundedTimestampMismatchesBoundedBlock_BothOrders_ShouldRevert()
        public
    {
        // Timestamp-mode, unbounded upper (raw validUntil=0, validAfter carries no MODE_BIT). After
        // normalization its validUntil becomes type(uint48).max (which does carry MODE_BIT), but its
        // validAfter still doesn't, so this remains a genuine timestamp-mode operand — a real mismatch
        // against the block-mode bounded operand, not a normalization false-positive.
        uint256 timestampUnbounded = _pack(10, 0, address(0));
        uint256 boundedBlock = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, address(0));

        vm.expectRevert(ValidityFormatMismatch.selector);
        harness.intersectValidationData(timestampUnbounded, boundedBlock);

        vm.expectRevert(ValidityFormatMismatch.selector);
        harness.intersectValidationData(boundedBlock, timestampUnbounded);
    }

    function test_intersectValidationData_WhenAggregatorOnUnboundedBlockIntersectsSuccessOnBoundedBlock_BothOrders_ShouldPreserveOrAdoptAggregator()
        public
        view
    {
        address aggregator = address(0xCAFE);
        uint256 unboundedWithAggregator = _pack(_UNBOUNDED_BLOCK_AFTER, 0, aggregator);
        uint256 boundedWithSuccess = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, address(0));

        // Aggregator as the pre operand => preserved.
        (uint48 va1, uint48 vu1, address res1) =
            harness.parseValidationData(harness.intersectValidationData(unboundedWithAggregator, boundedWithSuccess));
        assertEq(res1, aggregator, "aggregator on the unbounded operand must survive normalization");
        assertEq(va1, _BOUNDED_BLOCK_AFTER, "bounds still take the bounded operand's validAfter");
        assertEq(vu1, _BOUNDED_BLOCK_UNTIL, "bounds still take the bounded operand's validUntil");

        // Aggregator as the res operand => adopted.
        (uint48 va2, uint48 vu2, address res2) =
            harness.parseValidationData(harness.intersectValidationData(boundedWithSuccess, unboundedWithAggregator));
        assertEq(res2, aggregator, "aggregator on the unbounded operand must be adopted regardless of order");
        assertEq(va2, _BOUNDED_BLOCK_AFTER, "bounds still take the bounded operand's validAfter");
        assertEq(vu2, _BOUNDED_BLOCK_UNTIL, "bounds still take the bounded operand's validUntil");
    }

    function test_intersectValidationData_WhenFailureOnUnboundedBlockIntersectsSuccessOnBoundedBlock_BothOrders_ShouldReturnFailure()
        public
        view
    {
        uint256 unboundedFailure = _pack(_UNBOUNDED_BLOCK_AFTER, 0, address(1));
        uint256 boundedSuccess = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, address(0));

        (,, address res1) =
            harness.parseValidationData(harness.intersectValidationData(unboundedFailure, boundedSuccess));
        assertEq(res1, address(1), "failure must survive normalization regardless of order");

        (,, address res2) =
            harness.parseValidationData(harness.intersectValidationData(boundedSuccess, unboundedFailure));
        assertEq(res2, address(1), "failure must survive normalization regardless of order");
    }

    function test_intersectValidationData_WhenConflictingAggregatorsOnUnboundedAndBoundedBlockRanges_BothOrders_ShouldReturnFailure()
        public
        view
    {
        address agg1 = address(0x1111);
        address agg2 = address(0x2222);
        uint256 unboundedAgg1 = _pack(_UNBOUNDED_BLOCK_AFTER, 0, agg1);
        uint256 boundedAgg2 = _pack(_BOUNDED_BLOCK_AFTER, _BOUNDED_BLOCK_UNTIL, agg2);

        (,, address res1) = harness.parseValidationData(harness.intersectValidationData(unboundedAgg1, boundedAgg2));
        assertEq(res1, address(1), "conflicting aggregators fail regardless of order");

        (,, address res2) = harness.parseValidationData(harness.intersectValidationData(boundedAgg2, unboundedAgg1));
        assertEq(res2, address(1), "conflicting aggregators fail regardless of order");
    }
}
