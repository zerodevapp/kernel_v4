// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Lib4337Harness} from "../mock/Lib4337Harness.sol";

abstract contract Lib4337_Test is Test {
    Lib4337Harness harness;

    // State variables for BTT branch tracking - set by modifiers, used by tests
    uint256 internal _preValidationData;
    uint256 internal _validationRes;
    uint256 internal _currentTimestamp;

    function setUp() public virtual {
        harness = new Lib4337Harness();
    }

    // Helper to pack validation data: validAfter (48 bits) | validUntil (48 bits) | result (160 bits)
    function packValidationData(uint48 validAfter, uint48 validUntil, address result) internal pure returns (uint256) {
        return (uint256(validAfter) << 208) | (uint256(validUntil) << 160) | uint160(result);
    }

    modifier whenCallingParseValidationData() {
        // Set up default packed data for parsing tests
        _preValidationData = packValidationData(100, 0, address(0));
        _;
    }

    function test_GivenValidUntilIsZeroInThePackedData() external whenCallingParseValidationData {
        // Pack data with validUntil = 0
        uint256 validationData = packValidationData(100, 0, address(0));

        (uint48 validAfter, uint48 validUntil, address result) = harness.parseValidationData(validationData);

        assertEq(validAfter, 100, "validAfter should be 100");
        assertEq(validUntil, type(uint48).max, "validUntil should be max uint48 when packed as 0");
        assertEq(result, address(0), "result should be address(0)");
    }

    function test_GivenValidUntilIsNon_zeroInThePackedData() external whenCallingParseValidationData {
        // Pack data with validUntil = 5000
        uint256 validationData = packValidationData(100, 5000, address(0x1234));

        (uint48 validAfter, uint48 validUntil, address result) = harness.parseValidationData(validationData);

        assertEq(validAfter, 100, "validAfter should be 100");
        assertEq(validUntil, 5000, "validUntil should be exact value 5000");
        assertEq(result, address(0x1234), "result should be 0x1234");
    }

    modifier whenCallingCheckValidation() {
        // Set up default timestamp for checkValidation tests
        _currentTimestamp = 1000;
        vm.warp(_currentTimestamp);
        _;
    }

    function test_GivenValidAfterIsGreaterThanCurrentTimestamp() external whenCallingCheckValidation {
        // validAfter = 2000 (future), validUntil = 0 (max), result = 0 (success)
        // _currentTimestamp is 1000, so validAfter > current
        uint256 validationData = packValidationData(2000, 0, address(0));

        bool isValid = harness.checkValidation(validationData);

        assertFalse(isValid, "should return false when validAfter is in the future");
    }

    function test_GivenValidUntilIsLessThanCurrentTimestamp() external whenCallingCheckValidation {
        // Warp to later timestamp for this specific test
        vm.warp(5000);
        // validAfter = 0, validUntil = 1000 (past), result = 0 (success)
        uint256 validationData = packValidationData(0, 1000, address(0));

        bool isValid = harness.checkValidation(validationData);

        assertFalse(isValid, "should return false when validUntil is in the past");
    }

    function test_GivenResultAddressIsNotZero() external whenCallingCheckValidation {
        // Uses _currentTimestamp (1000) set by modifier
        // validAfter = 0, validUntil = 0 (max), result = 1 (failure)
        uint256 validationData = packValidationData(0, 0, address(1));

        bool isValid = harness.checkValidation(validationData);

        assertFalse(isValid, "should return false when result is not address(0)");
    }

    function test_GivenTimeBoundsAreValidAndResultIsZero() external whenCallingCheckValidation {
        // Uses _currentTimestamp (1000) set by modifier
        // validAfter = 500 (past), validUntil = 2000 (future), result = 0 (success)
        uint256 validationData = packValidationData(500, 2000, address(0));

        bool isValid = harness.checkValidation(validationData);

        assertTrue(isValid, "should return true when time bounds are valid and result is zero");
    }

    modifier whenCallingIntersectValidationData() {
        // Set up default validation data for intersect tests
        _preValidationData = packValidationData(100, 200, address(0x1234));
        _validationRes = packValidationData(100, 200, address(0x5678));
        _;
    }

    function test_GivenPreValidationDataIsZero() external whenCallingIntersectValidationData {
        // Override to zero for this specific test
        _preValidationData = 0;

        uint256 result = harness.intersectValidationData(_preValidationData, _validationRes);

        assertEq(result, _validationRes, "should return validationRes via short circuit when preValidationData is 0");
    }

    function test_GivenValidationResIsZero() external whenCallingIntersectValidationData {
        // Override to zero for this specific test
        _validationRes = 0;

        uint256 result = harness.intersectValidationData(_preValidationData, _validationRes);

        assertEq(result, _preValidationData, "should return preValidationData via short circuit when validationRes is 0");
    }

    modifier givenBothValuesAreNon_zero() {
        // Ensure both values are non-zero (override any zero values from parent modifier)
        if (_preValidationData == 0) {
            _preValidationData = packValidationData(100, 1000, address(0x1));
        }
        if (_validationRes == 0) {
            _validationRes = packValidationData(100, 1000, address(0x2));
        }
        _;
    }

    function test_GivenValidUntil1IsZero() external whenCallingIntersectValidationData givenBothValuesAreNon_zero {
        // validUntil1 = 0 means max, validUntil2 = 1000
        uint256 preValidationData = packValidationData(100, 0, address(0x1));
        uint256 validationRes = packValidationData(100, 1000, address(0x2));

        uint256 result = harness.intersectValidationData(preValidationData, validationRes);

        // Extract validUntil from result
        uint48 resultValidUntil = uint48(result >> 160);
        assertEq(resultValidUntil, 1000, "should use validUntil2 since validUntil1 (max) > validUntil2");
    }

    function test_GivenValidUntil2IsZero() external whenCallingIntersectValidationData givenBothValuesAreNon_zero {
        // validUntil1 = 1000, validUntil2 = 0 means max
        uint256 preValidationData = packValidationData(100, 1000, address(0x1));
        uint256 validationRes = packValidationData(100, 0, address(0x2));

        uint256 result = harness.intersectValidationData(preValidationData, validationRes);

        // Extract validUntil from result
        uint48 resultValidUntil = uint48(result >> 160);
        assertEq(resultValidUntil, 1000, "should use validUntil1 since validUntil2 is max");
    }

    function test_GivenValidUntil1IsGreaterThanValidUntil2()
        external
        whenCallingIntersectValidationData
        givenBothValuesAreNon_zero
    {
        // validUntil1 = 2000, validUntil2 = 1000
        uint256 preValidationData = packValidationData(100, 2000, address(0x1));
        uint256 validationRes = packValidationData(100, 1000, address(0x2));

        uint256 result = harness.intersectValidationData(preValidationData, validationRes);

        // Extract validUntil from result
        uint48 resultValidUntil = uint48(result >> 160);
        assertEq(resultValidUntil, 1000, "should use validUntil2 (smaller value)");
    }

    function test_GivenValidUntil1IsLessThanOrEqualToValidUntil2()
        external
        whenCallingIntersectValidationData
        givenBothValuesAreNon_zero
    {
        // validUntil1 = 1000, validUntil2 = 2000
        uint256 preValidationData = packValidationData(100, 1000, address(0x1));
        uint256 validationRes = packValidationData(100, 2000, address(0x2));

        uint256 result = harness.intersectValidationData(preValidationData, validationRes);

        // Extract validUntil from result
        uint48 resultValidUntil = uint48(result >> 160);
        assertEq(resultValidUntil, 1000, "should use validUntil1 (smaller value)");
    }

    function test_GivenValidAfter1IsLessThanValidAfter2()
        external
        whenCallingIntersectValidationData
        givenBothValuesAreNon_zero
    {
        // validAfter1 = 100, validAfter2 = 200
        uint256 preValidationData = packValidationData(100, 1000, address(0x1));
        uint256 validationRes = packValidationData(200, 1000, address(0x2));

        uint256 result = harness.intersectValidationData(preValidationData, validationRes);

        // Extract validAfter from result
        uint48 resultValidAfter = uint48(result >> 208);
        assertEq(resultValidAfter, 200, "should use validAfter2 (larger value)");
    }

    function test_GivenValidAfter1IsGreaterThanOrEqualToValidAfter2()
        external
        whenCallingIntersectValidationData
        givenBothValuesAreNon_zero
    {
        // validAfter1 = 300, validAfter2 = 200
        uint256 preValidationData = packValidationData(300, 1000, address(0x1));
        uint256 validationRes = packValidationData(200, 1000, address(0x2));

        uint256 result = harness.intersectValidationData(preValidationData, validationRes);

        // Extract validAfter from result
        uint48 resultValidAfter = uint48(result >> 208);
        assertEq(resultValidAfter, 300, "should use validAfter1 (larger value)");
    }

    function test_GivenPreValidationDataResultIs1ForAggregator()
        external
        whenCallingIntersectValidationData
        givenBothValuesAreNon_zero
    {
        // preValidationData result = 1 (aggregator marker)
        uint256 preValidationData = packValidationData(100, 1000, address(1));
        uint256 validationRes = packValidationData(100, 1000, address(0x5678));

        uint256 result = harness.intersectValidationData(preValidationData, validationRes);

        // Extract result address
        address resultAddr = address(uint160(result));
        assertEq(resultAddr, address(1), "should return 1 as result when preValidationData result is 1");
    }

    function test_GivenPreValidationDataResultIsNot1()
        external
        whenCallingIntersectValidationData
        givenBothValuesAreNon_zero
    {
        // preValidationData result = 0x1234 (not 1)
        uint256 preValidationData = packValidationData(100, 1000, address(0x1234));
        uint256 validationRes = packValidationData(100, 1000, address(0x5678));

        uint256 result = harness.intersectValidationData(preValidationData, validationRes);

        // Extract result address
        address resultAddr = address(uint160(result));
        assertEq(
            resultAddr, address(0x5678), "should return validationRes result when preValidationData result is not 1"
        );
    }
}

contract Lib4337_Concrete_Test is Lib4337_Test {}
