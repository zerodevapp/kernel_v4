/* SPDX-License-Identifier: MIT */

/**
 * Kernel v4 — Property #1: executeUserOp ↔ validateUserOp linkage
 *
 * SECURITY claim from src/Kernel.sol (executeUserOp NatSpec):
 *   The safety of the inner delegatecall to address(this) rests entirely on
 *   validateUserOp having approved the outer UserOp under a validation that
 *   owns the inner selector.
 *
 * STATUS (FV Round 2, after commit 0921b25):
 *   The fix at commit 0921b25 (src/core/ValidationManager.sol, _grantAccess)
 *   adds the require:
 *     require(selector != IAccountExecute.executeUserOp.selector
 *             || vId == $.root, InvalidSelectorGrant());
 *   This makes the original CEX unreachable for newly granted non-ROOT
 *   validations and the naive rule
 *   (validateUserOpEnforcesInnerSelectorAccess_naive) now PASSES.
 *
 * STRUCTURAL INVARIANT enforced by the fix
 *   (nonRootCannotAllowExecuteUserOp):
 *     For any vId != $.root, allowed[vId][executeUserOp.selector] == 0.
 *   _grantAccess is the sole writer of $.allowed; the fix blocks the only
 *   path that could ever raise that entry above zero for a non-root vId.
 *
 * Refined form (validateUserOpEnforcesInnerSelectorAccess_strict — kept for
 *   regression after the fix):
 *   Adds an additional precondition that EXCLUDES the fast-path bypass:
 *       NOT( allowed[vId][outerSel] == vInfo[vId].nonce
 *            AND vInfo[vId].hook == HOOK_MODULE_INSTALLED_NO_HOOK )
 *   With that exclusion, validateUserOp reaches the require on
 *   Kernel.sol L179-183 which enforces _allowedSelector(vId, innerSel).
 *
 * ORIGINAL IMPLEMENTATION FINDING (now mitigated by commit 0921b25):
 *   The fast-path branch in `_processUserOp` (Kernel.sol lines 172-176)
 *   bypassed the inner-selector require statement when:
 *     - vType != ROOT,
 *     - `_allowedSelector(vId, outerSel)` was true with outerSel ==
 *       executeUserOp.selector,
 *     - `vInfo[vId].hook == HOOK_MODULE_INSTALLED_NO_HOOK`.
 *   In that branch, `_setValidationHook` was never called, the transient
 *   hook for `userOpHash` stayed at 0, and `executeUserOp`'s inner
 *   delegatecall ran with NO selector check — handing a non-ROOT validation
 *   the equivalent of root privileges.
 *
 *   The fix in `_grantAccess` makes this precondition unreachable for
 *   non-ROOT validations: a non-ROOT validation can no longer satisfy
 *   `allowed[vId][executeUserOp.selector] == vInfo[vId].nonce` since that
 *   write is now blocked.
 *
 * Verified contract: KernelHarness (extends KernelUUPS). Harness exposes
 * read accessors only — production logic in validateUserOp is unchanged.
 *
 * NARROWINGS (for tractability — orchestrator is informed):
 *   - vMode bit 0x08 (enable mode) and 0x40 (replayable userOp hash) are
 *     constrained off. Enable-mode invokes _verifyInstallSignatureRaw +
 *     _install which the Prover's hashing engine cannot bound. Replayable
 *     invokes Lib4337.chainAgnosticUserOpHash, same issue. The fast-path
 *     bypass identified above does NOT depend on these modes, so the
 *     finding stands independently.
 *   - External module calls (validator/policy/signer/hook) are NONDET-
 *     summarised. Kernel's `_onlyEntryPointOrSelf` prevents reentrant
 *     writes to ValidationStorage from these modules, so the summary is
 *     sound for the property.
 *   - Internal validators `_validateUserOpValidator/Permission/Fallback`
 *     are NONDET-summarised — they don't write the (vInfo, allowed)
 *     mappings, only consult them. The fast-path branch never reaches
 *     these, so the strict rule does not depend on the summary.
 */

methods {
    // Harness storage / parse accessors (envfree — no env needed).
    function harness_vInfoNonce(bytes21)            external returns (uint32)  envfree;
    function harness_vInfoHook(bytes21)             external returns (address) envfree;
    function harness_allowedNonce(bytes21, bytes4)  external returns (uint32)  envfree;
    function harness_allowedSelector(bytes21, bytes4) external returns (bool)    envfree;
    function harness_root()                         external returns (bytes21) envfree;

    function harness_parseVType(uint256) external returns (bytes1)  envfree;
    function harness_parseVId(uint256)   external returns (bytes21) envfree;
    function harness_parseVMode(uint256) external returns (bytes1)  envfree;

    function harness_VT_ROOT()                external returns (bytes1) envfree;
    function harness_VT_VALIDATOR()           external returns (bytes1) envfree;
    function harness_VT_PERMISSION()          external returns (bytes1) envfree;
    function harness_HOOK_NOT_INSTALLED()     external returns (address) envfree;
    function harness_HOOK_INSTALLED_NO_HOOK() external returns (address) envfree;
    function harness_executeUserOpSelector()  external returns (bytes4)  envfree;
    function harness_isEnableMode(uint256)    external returns (bool)    envfree;
    function harness_isReplayableMode(uint256) external returns (bool)   envfree;

    function harness_outerSelector(KernelHarness.PackedUserOperation) external returns (bytes4) envfree;
    function harness_innerSelector(KernelHarness.PackedUserOperation) external returns (bytes4) envfree;
    function harness_callDataLength(KernelHarness.PackedUserOperation) external returns (uint256) envfree;

    // ----------------------- Internal summaries -----------------------
    // These functions are called from `validateUserOp` but their behaviour is
    // not relevant to the property — they only need to "exist" and return
    // arbitrary values. Summarising them keeps the TAC small enough to fit
    // in Certora's memory budget.
    //
    // _verifyInstallSignatureRaw — only invoked in enable-mode, which the
    // rule excludes via the precondition. Summarise anyway in case enable-
    // mode paths inline before the precondition is applied.
    function ValidationManager._validateUserOpValidator(
        KernelHarness.ValidationId, bytes32, KernelHarness.PackedUserOperation memory, bytes calldata
    ) internal returns (uint256) => NONDET;
    function ValidationManager._validateUserOpPermission(
        KernelHarness.ValidationId, bytes32, KernelHarness.PackedUserOperation memory, bytes calldata
    ) internal returns (uint256) => NONDET;
    function ValidationManager._validateUserOpFallback(
        KernelHarness.ValidationId, bytes32, KernelHarness.PackedUserOperation memory, bytes calldata
    ) internal returns (uint256) => NONDET;
    function ModuleManager._verifyInstallSignatureRaw(bool, uint256, KernelHarness.Install[] calldata, bytes calldata)
        internal returns (uint256) => NONDET;
    function Lib4337.chainAgnosticUserOpHash(address, KernelHarness.PackedUserOperation calldata)
        internal returns (bytes32) => CONSTANT;
    function Lib4337.intersectValidationData(uint256, uint256) internal returns (uint256) => NONDET;

    // External module / hook callbacks are dispatched as AUTO HAVOC by Certora.
    // The "havoc scope" excludes the KernelHarness contract, which is exactly
    // what we want: returns are arbitrary, but the Kernel's namespaced storage
    // is preserved across the external call. That over-approximation is sound
    // for this property because Kernel's _onlyEntryPointOrSelf prevents these
    // modules from re-entering and writing back into ValidationStorage anyway.
}

// --------------------------------------------------------------------------
// Invariant: nonRootCannotAllowExecuteUserOp
//
// The structural guarantee enforced by the commit 0921b25 fix in
// `_grantAccess`. Stated over `allowedNonce` (the raw mapping entry) rather
// than `allowedSelector` (the `==` comparison to vInfo[vId].nonce) because
// the latter is true-by-default for any uninstalled vId (both sides are 0).
//
//   For any vId != $.root:
//       allowed[vId][executeUserOp.selector] == 0
//
// `_grantAccess` is the sole writer of `$.allowed` (verified by static
// grep over src/). The fix's require:
//     require(selector != executeUserOp.selector || vId == $.root, …)
// blocks the only path that could ever raise this entry above zero for a
// non-root vId.
//
// If this invariant holds, then `_allowedSelector(vId, executeUserOp)` for
// non-root vId implies `vInfo[vId].nonce == 0` — which only happens for
// uninstalled validations. Combined with the fast-path's hook == INSTALLED
// precondition (which requires installation, i.e. nonce > 0), the fast-path
// bypass becomes structurally unreachable.
//
// CAVEAT: if this invariant FAILS, the CEX trace will identify which
// mutator can violate it. The most likely candidate is `setRoot` /
// `installModule` (root rotation can leave stale grants on the prior root).
// That would be a separate, secondary finding — the immediate fix would
// still close the original attack, but root rotation could resurrect a
// related bypass. Report any such CEX honestly.
// --------------------------------------------------------------------------
invariant nonRootCannotAllowExecuteUserOp(bytes21 vId)
    vId != harness_root() => harness_allowedNonce(vId, harness_executeUserOpSelector()) == 0;

// --------------------------------------------------------------------------
// Helper invariant: installedValidationsHaveNonzeroNonce
//
// Whenever a validation has a non-zero hook (i.e. hook >= INSTALLED_NO_HOOK
// rather than HOOK_MODULE_NOT_INSTALLED), its nonce is strictly positive.
//
// Both initialization paths in `_initializeValidation` bump the nonce when
// they set the hook, and `_uninstallValidation` only ever zeroes the hook
// (it does not reset the nonce). So `hook != NOT_INSTALLED` implies
// `nonce > 0` is preserved by every mutator.
//
// This invariant is needed by the naive rule to rule out the residual
// fast-path corner case `nonce == 0 && hook == INSTALLED_NO_HOOK`, which is
// unreachable in production but would otherwise be admissible by Certora
// in the abstract state space.
// --------------------------------------------------------------------------
invariant installedValidationsHaveNonzeroNonce(bytes21 vId)
    harness_vInfoHook(vId) != harness_HOOK_NOT_INSTALLED() => harness_vInfoNonce(vId) > 0;

// --------------------------------------------------------------------------
// Rule: validateUserOpEnforcesInnerSelectorAccess_naive
//
// The most direct restatement of the NatSpec security claim. Before commit
// 0921b25 this rule FAILED with a CEX exposing the fast-path bypass. With
// the structural invariant `nonRootCannotAllowExecuteUserOp` established by
// the fix, the fast-path precondition (allowedSelector(vId, outerSel) with
// outerSel == executeUserOp AND vType != ROOT) is unreachable for a vId
// with non-zero `vInfo[vId].nonce`, and the rule now PASSES.
//
// Scope notes:
//   - `vId != $.root` is required because root is intentionally authorised
//     to use the fast-path (vType == ROOT branch). When the user-op nonce
//     encodes (vType != ROOT, vId == $.root), the kernel still recognises
//     the call as root through _checkValidation's vId-based info lookup,
//     and the security guarantee for that case is "root is unconditionally
//     authorised" (per the inline comments at Kernel.sol L160-168) — not
//     "innerSel must be allow-listed." We exclude that case to keep the
//     rule's intent precise.
//
// `requireInvariant` injects the structural invariant as a hypothesis at
// the start of the rule; Certora separately proves the invariant.
// --------------------------------------------------------------------------
rule validateUserOpEnforcesInnerSelectorAccess_naive(
    env e,
    KernelHarness.PackedUserOperation op,
    bytes32 userOpHash,
    uint256 missingAccountFunds
) {
    require harness_callDataLength(op) >= 8;
    bytes4 outerSel = harness_outerSelector(op);
    bytes4 innerSel = harness_innerSelector(op);
    bytes1  vType = harness_parseVType(op.nonce);
    bytes21 vId   = harness_parseVId(op.nonce);

    require outerSel == harness_executeUserOpSelector();
    require vType != harness_VT_ROOT();
    require vId != harness_root();  // root is intentionally exempt from inner-sel check
    require !harness_isEnableMode(op.nonce);
    require !harness_isReplayableMode(op.nonce);

    // Structural invariant enforced by the fix at commit 0921b25.
    requireInvariant nonRootCannotAllowExecuteUserOp(vId);
    // Helper: installed validations have non-zero nonce (rules out the
    // (nonce == 0, hook == INSTALLED_NO_HOOK) corner case).
    requireInvariant installedValidationsHaveNonzeroNonce(vId);

    validateUserOp@withrevert(e, op, userOpHash, missingAccountFunds);
    bool reverted = lastReverted;

    assert !reverted => harness_allowedSelector(vId, innerSel);
}

// --------------------------------------------------------------------------
// Rule: validateUserOpEnforcesInnerSelectorAccess_strict
//
// The provable refinement. Adds an explicit precondition that excludes the
// fast-path branch (lines 172-176 of Kernel.sol). With the fast-path
// excluded, validateUserOp's control flow falls into the `else` branch
// that enforces _allowedSelector(vId, innerSel) via a require.
//
// Proof obligation: for any non-reverting call to validateUserOp where
//   - vMode is NOT enable-mode and NOT replayable,
//   - outer selector == executeUserOp.selector,
//   - parsed vType != ROOT,
//   - op.callData has at least 8 bytes,
//   - NOT(allowed[vId][outerSel] == vInfo[vId].nonce
//         AND vInfo[vId].hook == HOOK_MODULE_INSTALLED_NO_HOOK),
// the post-state satisfies allowed[vId][innerSel] == vInfo[vId].nonce.
// --------------------------------------------------------------------------
rule validateUserOpEnforcesInnerSelectorAccess_strict(
    env e,
    KernelHarness.PackedUserOperation op,
    bytes32 userOpHash,
    uint256 missingAccountFunds
) {
    require harness_callDataLength(op) >= 8;
    bytes4 outerSel = harness_outerSelector(op);
    bytes4 innerSel = harness_innerSelector(op);
    bytes1  vType = harness_parseVType(op.nonce);
    bytes21 vId   = harness_parseVId(op.nonce);

    require outerSel == harness_executeUserOpSelector();
    require vType != harness_VT_ROOT();
    require !harness_isEnableMode(op.nonce);
    require !harness_isReplayableMode(op.nonce);

    // Exclude the fast-path: if _allowedSelector(vId, outerSel) holds AND
    // the validation has no hook, the require gate is bypassed (this is the
    // implementation finding, NOT a property of the spec).
    bool fastPath = harness_allowedSelector(vId, outerSel)
                    && harness_vInfoHook(vId) == harness_HOOK_INSTALLED_NO_HOOK();
    require !fastPath;

    validateUserOp@withrevert(e, op, userOpHash, missingAccountFunds);
    bool reverted = lastReverted;

    assert !reverted => harness_allowedSelector(vId, innerSel);
}

// --------------------------------------------------------------------------
// Sanity rule — ensure validateUserOp isn't vacuously rejecting all inputs
// in the spec setup. If this rule is provable, the main rule is vacuous.
// We want it to be SATISFIABLE only (Certora `satisfy`).
// --------------------------------------------------------------------------
rule sanityValidateUserOpReachesSuccess(
    env e,
    KernelHarness.PackedUserOperation op,
    bytes32 userOpHash,
    uint256 missingAccountFunds
) {
    require harness_callDataLength(op) >= 8;
    validateUserOp@withrevert(e, op, userOpHash, missingAccountFunds);
    satisfy !lastReverted;
}
