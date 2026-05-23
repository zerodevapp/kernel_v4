// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {ValidationId, ValidationType, ValidationMode, PermissionId} from "src/types/Types.sol";
import {ValidationInfo, ValidationStorage} from "src/types/Structs.sol";
import {IHook} from "src/interfaces/IERC7579Modules.sol";
import {parseNonce, getType, permissionToIdentifier} from "src/lib/Utils.sol";
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
    // Permission-state accessors (used by SetRootLifo property).
    // ------------------------------------------------------------------

    /// @notice The number of policies installed under `vId`'s permission entry.
    function harness_vInfoPoliciesLength(bytes21 vId) external view returns (uint256) {
        return _vs().vInfo[ValidationId.wrap(vId)].policies.length;
    }

    /// @notice The signer module installed for `vId` (only meaningful for permission vIds).
    function harness_vInfoSigner(bytes21 vId) external view returns (address) {
        return _vs().vInfo[ValidationId.wrap(vId)].signer;
    }

    /// @notice Returns the policy address stored at index `i` for `vId`'s permission entry.
    /// @dev Reverts (out of bounds) if `i >= policies.length`.
    function harness_vInfoPolicyAt(bytes21 vId, uint256 i) external view returns (address) {
        return _vs().vInfo[ValidationId.wrap(vId)].policies[i];
    }

    /// @notice Returns the ValidationType (first byte) of a ValidationId.
    function harness_getType(bytes21 vId) external pure returns (bytes1) {
        return ValidationType.unwrap(getType(ValidationId.wrap(vId)));
    }

    /// @notice Encodes a 4-byte PermissionId into the corresponding permission-type ValidationId.
    function harness_permissionToVid(bytes4 permissionId) external pure returns (bytes21) {
        return ValidationId.unwrap(permissionToIdentifier(PermissionId.wrap(permissionId)));
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
    // Wrappers exposing the view (ERC-1271) and write (ERC-4337) permission
    // paths. Used by certora/specs/PermissionEquivalence.spec to compare the
    // two aggregate `validationData` results for the same inputs.
    //
    // Both functions read the same ValidationInfo (vInfo[vId]) and the same
    // PermissionId-derived `paddedVId`, iterate `vInfo[vId].policies` in the
    // same order, and intersect via Lib4337.intersectValidationData. The
    // STRUCTURAL difference is which external interface methods they invoke:
    //
    //   view path :  IPolicy.checkSignaturePolicy(paddedVId, requester, hash, sig)
    //                ISigner.checkSignature(paddedVId, requester, hash, sig)    -> bytes4
    //   write path:  IPolicy.checkUserOpPolicy(paddedVId, op)                   -> uint256
    //                ISigner.checkUserOpSignature(paddedVId, op, opHash)        -> uint256
    //
    // The audit property is "kernel-side framing is identical." The spec
    // CVL-summarises the four module entry points to a shared ghost so that,
    // under the assumption each module is deterministic with respect to its
    // inputs, the two paths must produce the same aggregate -- unless the
    // kernel itself diverges. Any divergence is a HIGH-severity finding.
    function harness_verifySignaturePermission(bytes21 vId, address requester, bytes32 hash, bytes calldata signature)
        external
        view
        returns (uint256)
    {
        ValidationStorage storage $ = _vs();
        ValidationId v = ValidationId.wrap(vId);
        return _verifySignaturePermission(v, $.vInfo[v], requester, hash, signature);
    }

    function harness_validateUserOpPermission(
        bytes21 vId,
        bytes32 opHash,
        PackedUserOperation memory op,
        bytes calldata userOpSignature
    ) external returns (uint256) {
        return _validateUserOpPermission(ValidationId.wrap(vId), opHash, op, userOpSignature);
    }

    // Length of the policies array for a vId (used as a loop bound in CVL).
    function harness_policiesLength(bytes21 vId) external view returns (uint256) {
        return _vs().vInfo[ValidationId.wrap(vId)].policies.length;
    }

    function harness_policyAt(bytes21 vId, uint256 i) external view returns (address) {
        return _vs().vInfo[ValidationId.wrap(vId)].policies[i];
    }

    function harness_signer(bytes21 vId) external view returns (address) {
        return _vs().vInfo[ValidationId.wrap(vId)].signer;
    }

    // ------------------------------------------------------------------
    // Writer-local invariant wrappers (Phase C Round 2)
    //
    // These expose the four ValidationStorage writers as external functions so
    // CVL rules can call exactly one writer at a time. The wrappers preserve
    // production semantics 1:1 -- they only adapt the parameter type
    // (bytes21 / ValidationId / Install) at the boundary.
    //
    // The four writers (verified by static grep over src/ on 2026-05-21):
    //   1. _grantAccess(vId, selectors)                  -- ValidationManager.sol:101
    //   2. _setRoot(vId)                                 -- ValidationManager.sol:461
    //   3. _uninstallValidation(_vId)                    -- ValidationManager.sol:210
    //   4. _initializeValidation(vId, _internalData)     -- ValidationManager.sol:125
    //
    // No other path writes $.allowed, $.vInfo[*].nonce, $.vInfo[*].hook, or
    // $.root. Public entry points (installModule, executeUserOp, etc.) reach
    // these writers via internal call chains, but the writers themselves are
    // the only place where the relevant storage slots are mutated.
    // ------------------------------------------------------------------

    function harness_grantAccess(bytes21 vId, bytes calldata selectors) external {
        _grantAccess(ValidationId.wrap(vId), selectors);
    }

    function harness_setRootById(bytes21 vId) external {
        _setRoot(ValidationId.wrap(vId));
    }

    function harness_uninstallValidation(bytes21 vId) external {
        _uninstallValidation(ValidationId.wrap(vId));
    }

    function harness_initializeValidation(bytes21 vId, bytes calldata internalData) external {
        _initializeValidation(ValidationId.wrap(vId), internalData);
    }

    // ------------------------------------------------------------------
    function _vs() internal pure returns (ValidationStorage storage $) {
        bytes32 slot = VALIDATION_MANAGER_STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
