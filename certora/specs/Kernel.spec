/* SPDX-License-Identifier: MIT */

/**
 * Kernel v4 — Property #1: executeUserOp ↔ validateUserOp linkage
 *
 * SECURITY claim from src/Kernel.sol (executeUserOp NatSpec):
 *   The safety of the inner delegatecall to address(this) rests entirely on
 *   validateUserOp having approved the outer UserOp under a validation that
 *   owns the inner selector.
 *
 * Strongest reformulation we tried to prove (FAILS with a CEX — see below):
 *   For any non-reverting call to validateUserOp where the outer selector
 *   is executeUserOp.selector and vType != ROOT, the post-state satisfies
 *       allowed[vId][innerSel] == vInfo[vId].nonce.
 *
 * Refined form actually verified (validateUserOpEnforcesInnerSelectorAccess_strict):
 *   Adds an additional precondition that EXCLUDES the fast-path bypass:
 *       NOT( allowed[vId][outerSel] == vInfo[vId].nonce
 *            AND vInfo[vId].hook == HOOK_MODULE_INSTALLED_NO_HOOK )
 *   With that exclusion, validateUserOp reaches the require on
 *   Kernel.sol L179-183 which enforces _allowedSelector(vId, innerSel).
 *
 * IMPLEMENTATION FINDING (the un-refined rule's counterexample is real):
 *   The fast-path branch in `_processUserOp` (Kernel.sol lines 172-176)
 *   bypasses the inner-selector require statement when:
 *     - vType != ROOT,
 *     - `_allowedSelector(vId, outerSel)` is true with outerSel ==
 *       executeUserOp.selector,
 *     - `vInfo[vId].hook == HOOK_MODULE_INSTALLED_NO_HOOK`.
 *   In that branch, `_setValidationHook` is NEVER called, so the transient
 *   hook for `userOpHash` stays at 0 (HOOK_MODULE_NOT_INSTALLED). When
 *   `executeUserOp` then runs, `_preHook`/`_postHook` no-op (because the
 *   hook is 0), and the inner delegatecall runs with NO selector check.
 *
 *   The fast-path's design intent (per the inline comment "fast-path that
 *   skips the executeUserOp wrapper because there is nothing for a hook to
 *   wrap") assumes the OUTER call is the actual inner function. Granting a
 *   non-ROOT validation access to `executeUserOp.selector` itself violates
 *   that assumption and yields a privilege escalation: the validation can
 *   call `executeUserOp(...)` with arbitrary inner calldata.
 *
 *   This is at minimum a documented-assumption hazard and at most a
 *   privilege-escalation bug. See `audit/fv-round-1-findings.md` for the
 *   recommended remediation (either block `executeUserOp.selector` from
 *   being granted to non-ROOT validations in `_grantAccess`, or extend the
 *   require to also check `outerSel != executeUserOp.selector` before the
 *   fast-path is taken).
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
// Rule: validateUserOpEnforcesInnerSelectorAccess_naive  (EXPECTED TO FAIL)
//
// The most direct restatement of the NatSpec security claim. This rule
// FAILS because of the fast-path bypass documented at the top of this file
// — Certora produces a counterexample that is preserved as evidence of the
// finding. Marked SATISFY so the negation can be inspected directly.
//
// We keep this rule in the file (rather than deleting it) as machine-
// checkable evidence of the security finding. Reviewers reading the
// Certora report can see the exact CEX witness.
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
    require !harness_isEnableMode(op.nonce);
    require !harness_isReplayableMode(op.nonce);

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
