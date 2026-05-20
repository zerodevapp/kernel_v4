// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {ValidationId, ValidationType, ValidationMode, PermissionId} from "src/types/Types.sol";
import {ValidationInfo, ValidationStorage} from "src/types/Structs.sol";
import {IHook} from "src/interfaces/IERC7579Modules.sol";
import {parseNonce, getType} from "src/lib/Utils.sol";
import {
    VALIDATION_TYPE_ROOT,
    VALIDATION_TYPE_VALIDATOR,
    VALIDATION_TYPE_PERMISSION,
    VALIDATION_MANAGER_STORAGE_SLOT,
    HOOK_MODULE_NOT_INSTALLED,
    HOOK_MODULE_INSTALLED_NO_HOOK
} from "src/types/Constants.sol";

/// @title KernelHarness — Certora-only wrapper exposing internal views.
/// @notice DO NOT DEPLOY. Used only for formal verification. Adds public
///         accessors over the namespaced ValidationStorage so CVL rules can
///         read nonce / allowed entries without bypassing the production
///         storage layout, plus pure helpers that re-export `parseNonce`,
///         module-type constants, and `bytes4(op.callData[0:4]/[4:8])`
///         extraction. Production logic in `validateUserOp` / `executeUserOp`
///         is unchanged; the harness only adds new external read functions.
contract KernelHarness is KernelUUPS {
    constructor(IEntryPoint _entryPoint) KernelUUPS(_entryPoint) {}

    // ------------------------------------------------------------------
    // Storage accessors (mirror ValidationManager._allowedSelector / _validationStorage)
    // ------------------------------------------------------------------

    function harness_vInfoNonce(bytes21 vId) external view returns (uint32) {
        return _vs().vInfo[ValidationId.wrap(vId)].nonce;
    }

    function harness_vInfoHook(bytes21 vId) external view returns (address) {
        return _vs().vInfo[ValidationId.wrap(vId)].hook;
    }

    function harness_allowedNonce(bytes21 vId, bytes4 sel) external view returns (uint32) {
        return _vs().allowed[ValidationId.wrap(vId)][sel];
    }

    function harness_allowedSelector(bytes21 vId, bytes4 sel) external view returns (bool) {
        ValidationStorage storage $ = _vs();
        ValidationId v = ValidationId.wrap(vId);
        return $.allowed[v][sel] == $.vInfo[v].nonce;
    }

    function harness_root() external view returns (bytes21) {
        return ValidationId.unwrap(_vs().root);
    }

    // ------------------------------------------------------------------
    // Pure helpers.
    // ------------------------------------------------------------------

    function harness_parseVType(uint256 nonce) external pure returns (bytes1) {
        (, ValidationType vType,) = parseNonce(nonce);
        return ValidationType.unwrap(vType);
    }

    function harness_parseVId(uint256 nonce) external pure returns (bytes21) {
        (,, ValidationId vId) = parseNonce(nonce);
        return ValidationId.unwrap(vId);
    }

    function harness_parseVMode(uint256 nonce) external pure returns (bytes1) {
        (ValidationMode vMode,,) = parseNonce(nonce);
        return ValidationMode.unwrap(vMode);
    }

    function harness_validationHook(bytes32 userOpHash) external view returns (address) {
        IHook h;
        assembly {
            h := tload(userOpHash)
        }
        return address(h);
    }

    // ------------------------------------------------------------------
    // Constant exposers.
    // ------------------------------------------------------------------

    function harness_VT_ROOT() external pure returns (bytes1) {
        return ValidationType.unwrap(VALIDATION_TYPE_ROOT);
    }

    function harness_VT_VALIDATOR() external pure returns (bytes1) {
        return ValidationType.unwrap(VALIDATION_TYPE_VALIDATOR);
    }

    function harness_VT_PERMISSION() external pure returns (bytes1) {
        return ValidationType.unwrap(VALIDATION_TYPE_PERMISSION);
    }

    function harness_HOOK_NOT_INSTALLED() external pure returns (address) {
        return HOOK_MODULE_NOT_INSTALLED;
    }

    function harness_HOOK_INSTALLED_NO_HOOK() external pure returns (address) {
        return HOOK_MODULE_INSTALLED_NO_HOOK;
    }

    function harness_executeUserOpSelector() external pure returns (bytes4) {
        return this.executeUserOp.selector;
    }

    function harness_isEnableMode(uint256 nonce) external pure returns (bool) {
        (ValidationMode vMode,,) = parseNonce(nonce);
        return ValidationMode.unwrap(vMode) & bytes1(0x08) != 0;
    }

    function harness_isReplayableMode(uint256 nonce) external pure returns (bool) {
        (ValidationMode vMode,,) = parseNonce(nonce);
        return ValidationMode.unwrap(vMode) & bytes1(0x40) != 0;
    }

    // ------------------------------------------------------------------
    // Extraction helpers — return the (outer, inner) selectors of a
    // PackedUserOperation calldata, mirroring how validateUserOp / executeUserOp
    // read them. Reverts if calldata is too short.
    // ------------------------------------------------------------------

    function harness_outerSelector(PackedUserOperation calldata op) external pure returns (bytes4) {
        require(op.callData.length >= 4, "callData<4");
        return bytes4(op.callData[0:4]);
    }

    function harness_innerSelector(PackedUserOperation calldata op) external pure returns (bytes4) {
        require(op.callData.length >= 8, "callData<8");
        return bytes4(op.callData[4:8]);
    }

    function harness_callDataLength(PackedUserOperation calldata op) external pure returns (uint256) {
        return op.callData.length;
    }

    // ------------------------------------------------------------------
    function _vs() internal pure returns (ValidationStorage storage $) {
        bytes32 slot = VALIDATION_MANAGER_STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
