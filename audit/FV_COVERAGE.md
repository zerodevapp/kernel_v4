# Kernel v4 — FV Coverage Board

> **Live status table** mapping every public/external function plus security-relevant internal helper to its formal-verification obligation, backend, and proof state.

**Last updated**: 2026-05-23 (Round 2 Phase C closure)
**Branch**: `audit/fv-round-1` (PR #55, 30 commits)
**Companion docs**:
- [`audit/FV_PLAN.md`](./FV_PLAN.md) — Round 1 multi-phase plan
- [`audit/FV_PLAN_ROUND_2.md`](./FV_PLAN_ROUND_2.md) — Round 2 strategy
- [`audit/fv-gap-audit.md`](./fv-gap-audit.md) — original gap audit
- [`audit/fv-round-1-findings.md`](./fv-round-1-findings.md) — Round 1 per-property findings

## Legend

**Obligation types** (per the Round 2 plan):

- **AC** — Access Control: caller restrictions hold
- **TR** — Transition: every state change preserves the relevant invariant
- **EQ** — Equivalence: two paths agree on the audit-relevant outcome
- **NR** — Non-Replay: operations cannot be replayed
- **NB** — Non-Bypass: no path returns success without the expected predicate
- **DT** — Determinism: pure functions / CREATE2 deployments are deterministic
- **OF** — Overflow: arithmetic cannot overflow under reachable preconditions

**Status**:

- ✅ **PROVEN** — at least one FV backend has discharged the obligation
- 🟡 **PARTIAL** — partially proven (e.g., subset of inputs, complementary backends)
- ❌ **OPEN** — obligation identified but not yet attempted
- 🔵 **OOS** — explicitly out of scope (with rationale)

**Backends**:

- **H** = Halmos, **C** = Certora, **K** = Kontrol, **M** = Manual proof, **OOS** = out of scope

---

## `src/Kernel.sol`

| Visibility | Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|---|
| external | `initialize(packages)` (declared abstract) | AC, TR | — | 🔵 OOS | Implemented by subclasses (`KernelUUPS.initialize`, `KernelImmutableECDSA._initialize`). |
| external | `validateUserOp(userOp, hash, missingFunds)` | AC, NB | C | ✅ PROVEN | Phase C #1 strict + naive rules. Spec: `certora/specs/Kernel.spec`. |
| external | `executeUserOp(userOp, hash)` | NB | C, M | ✅ PROVEN | Phase C #1 (executeUserOp inner delegatecall gated by validateUserOp). |
| external | `execute(mode, executionData)` | AC | C (transitively via Phase C #1) | 🟡 PARTIAL | Routing through `_execute`; AC via `_onlyEntryPointOrSelf`. Direct unit/AC proof missing. |
| external | `setNonce(key, seq)` | AC, TR | C (Phase C writer-local) | ✅ PROVEN | `setRootPreservesNonBypass` + `_checkAndIncrementNonce` chain. Phase A #13 covers nonce no-overflow. |
| external | `setValidNonceFrom(seq)` | AC, TR | C (Phase C writer-local) | ✅ PROVEN | Same. |
| external | `installModule(moduleType, module, initData)` (ERC-7579) | AC, TR | C (Phase C writer-local) | ✅ PROVEN | `_initializeValidation` + `_installValidator/Policy/Signer/Hook/Executor/Selector` writer chain. |
| external | `uninstallModule(moduleType, module, initData)` | AC, TR | C (Phase C writer-local) | ✅ PROVEN | `uninstallValidationPreservesNonBypass`. |
| external | `setRoot(pkg, removeCurrent, uninstallData)` (install-overload) | AC, TR, NB | C | ✅ PROVEN | Phase D #6 (`SetRootLifo.spec`). LIFO cleanup post-conditions verified. |
| external | `setRoot(vId)` (id-overload) | AC, TR | C (Phase C writer-local) | ✅ PROVEN | `setRootPreservesNonBypass`. |
| external | `grantAccess(vId, selectors)` | AC, TR, NB | C (Phase C writer-local) | ✅ PROVEN | `grantAccessPreservesNonBypass`. Block executeUserOp.selector for non-root in fix `0921b25`. |
| external | `installModule(packages)` (enable-mode) | AC, NR | C, H (partial) | 🟡 PARTIAL | Phase D #4 covers permission totality. Enable-mode `_verifyInstallSignatureRaw` not separately proven; nonce check covered by Phase A #14. |
| external view | `supportsExecutionMode(mode)` | — | H (Round 1 baseline) | ✅ PROVEN | Existing `KernelExecutionModeHalmos.t.sol` on `fix/audit-internal-batch-1`. |
| external pure | `supportsModule(typeId)` | — | H (Round 1 baseline) | ✅ PROVEN | Same. |
| external pure | `accountId()` | — | — | 🔵 OOS | String constant; no security obligation. |
| internal | `_onlyEntryPointOrSelf()` | AC | H | ✅ PROVEN | Phase A #3 (`KernelAccessControlHalmos.t.sol` on baseline). |
| internal | `_initialize(packages)` | AC, TR | C (Phase C writer-local) | ✅ PROVEN | Through `_initializeValidation` + `_setRoot` writers. |
| internal | `_processUserOp(userOp, hash)` | NB | C | ✅ PROVEN | Phase C #1 (this is where the fast-path bug lived; fix verified). |
| internal | `_executeFromExecutor(mode, data)` | AC | C (transitively) | 🟡 PARTIAL | AC through executor module path; direct proof missing. |
| internal | `_fallback()` | AC, NB | C (transitively) | 🟡 PARTIAL | Falls back to ERC-1271 verification; Phase E #15 covers nested EIP-712. |

## `src/core/ValidationManager.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `_initializeValidation(vId, internalData)` | TR (nonce bump), NB (no stale grants) | H + C | ✅ PROVEN | Phase A #14 (nonce bump on both paths); Phase C writer-local. |
| `_installValidator(...)` | TR | C (Phase C writer-local) | ✅ PROVEN | Via `_initializeValidation`. |
| `_installPolicy(...)` | TR | C (Phase C writer-local) | ✅ PROVEN | Via `_checkPermissionInstall`. |
| `_installSigner(...)` | TR | C (Phase C writer-local) | ✅ PROVEN | Via `_initializeValidation`. |
| `_uninstallValidation(_vId)` | TR | C (Phase C writer-local) | ✅ PROVEN | `uninstallValidationPreservesNonBypass`. |
| `_uninstallValidator(...)` | TR | C (Phase C writer-local) | ✅ PROVEN | Via `_uninstallValidation`. |
| `_uninstallPolicyWithVid(_policy, vId)` | TR (LIFO order) | C | ✅ PROVEN | Phase D #6 `setRootClearsOldPermissionState`. |
| `_uninstallSignerWithVid(_signer, vId)` | TR (policies.length == 0 precondition) | C | ✅ PROVEN | Phase D #6 (after policies fully popped). |
| `_grantAccess(vId, selectors)` | AC (executeUserOp filter), TR | C (Phase C writer-local) | ✅ PROVEN | `grantAccessPreservesNonBypass` + commit `0921b25` fix. |
| `_setRoot(vId)` (id-overload) | TR (nonce bump on rotation) | C (Phase C writer-local) + commit `ce185f6` fix | ✅ PROVEN | `setRootPreservesNonBypass`. |
| `_setRoot(pkg)` (install-overload) | TR, NB | C | ✅ PROVEN | Phase D #6. |
| `_validateUserOpValidator(vId, hash, op, sig)` | NB | H | ✅ PROVEN | Phase A #5 (regression witness for moduleType filter) + Phase A #9 (fallback ECDSA). |
| `_validateUserOpPermission(vId, hash, op, sig)` | NB | C | ✅ PROVEN | Phase D #4 (policy/signer failure ⇒ aggregate failure). |
| `_validateUserOpFallback(vId, hash, op, sig)` | NB | H | ✅ PROVEN | Phase A #9. |
| `_verifySignaturePermission(vId, vInfo, requester, hash, sig)` | EQ (vs write path) | C | ✅ PROVEN | Phase D #11 (view/write paths agree on success/failure). |
| `_verifyInstallSignature(replayable, nonce, packages, sig)` | NR | C (NONDET summary in Phase C) | 🟡 PARTIAL | Summarised in Phase C/D specs; direct proof TBD. |
| `_verifyInstallSignatureRaw(...)` | NB | — | ❌ OPEN | Hashing unbounded bytes — needs Halmos partial or Certora summaries. |
| `_checkValidation(vType, vId)` | — | — | ❌ OPEN | Routing logic; need a proof that vType matches the installed validation. |
| `_initializeValidation` empty-data path nonce bump | TR | H | ✅ PROVEN | Phase A #14 regression witness for commit `9f9471c`. |

## `src/core/ModuleManager.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `_checkNonce(nonce)` view | EQ (vs write path) | H | ✅ PROVEN | Phase B #7 (`NonceConsistencyHalmos.t.sol`) — below saturation. |
| `_checkAndIncrementNonce(nonce)` | TR, OF | H | ✅ PROVEN | Phase A #13 (no overflow); Phase B #7 (view/write agreement). |
| `_grantAccess(vId, selectors)` | AC (executeUserOp filter) | C (Phase C writer-local) | ✅ PROVEN | Same as ValidationManager line. |
| `_verifyInstallSignatureRaw(...)` | NB | — | ❌ OPEN | Same as ValidationManager line. |
| `_installHash(packages)` | DT | — | ❌ OPEN | Pure salt derivation; quick Halmos target. |
| `_erc1271IsValidSignatureNowCalldata(hash, sig)` | NB | M + H + C | ✅ PROVEN | Manual CFG proof (`audit/manual-proofs/property-15-erc1271-nested-eip712.md`) covers Path P and Path T. Production binding by Phase A #9. |

## `src/core/ExecutionManager.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `_execute(mode, executionData)` | AC (caller is Kernel itself) | — | ❌ OPEN | Routing function; AC implicit. |
| `_executeCall(executionData, onRevert)` | NB | — | ❌ OPEN | Quick Halmos target — bounded calldata. |
| `_executeDelegateCall(executionData, onRevert)` | NB | — | ❌ OPEN | Same. |
| `_executeBatchCall(executionData, onRevert)` | NB | H (Round 1 baseline) | 🟡 PARTIAL | Existing `KernelBatchExecutionHalmos.t.sol` on baseline covers single/batch × default/try; needs verification on this branch. |
| `_getReturn()` | — | — | 🔵 OOS | Pure assembly memory return; no security obligation. |
| `_call(target, value, callData)` | — | — | 🔵 OOS | Solidity primitive wrapper. |
| `_delegateCall(delegate, callData)` | — | — | 🔵 OOS | Solidity primitive wrapper. |

## `src/core/ExecutorManager.sol` / `HookManager.sol` / `SelectorManager.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `executorConfig(executor)` view | — | — | 🔵 OOS | Pure getter. |
| `_installExecutor(...)` | TR | — | ❌ OPEN | Module-level installer. |
| `_uninstallExecutor(...)` | TR | — | ❌ OPEN | Module-level uninstaller. |
| `_installHook(...)` | TR | — | ❌ OPEN | Hook installer (HOOK_MODULE_INSTALLED_NO_HOOK sentinel). |
| `_uninstallHook(...)` | TR | — | ❌ OPEN | Hook uninstaller. |
| `_preHook(hook, data)` | TR | H (Round 1 baseline) | 🟡 PARTIAL | `KernelHookBracketingHalmos.t.sol` on baseline. |
| `_postHook(hook, context)` | TR | H (Round 1 baseline) | 🟡 PARTIAL | Same. |
| `_hookEnabled(hook)` view | — | — | 🔵 OOS | Pure view. |
| `_installSelector(...)` | TR | H (Round 1 baseline) | 🟡 PARTIAL | `KernelSelectorHalmos.t.sol` on baseline. |
| `_uninstallSelector(...)` | TR | H (Round 1 baseline) | 🟡 PARTIAL | Same. |

## `src/KernelUUPS.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `initialize(packages)` | AC, TR | C (Phase C writer-local) | ✅ PROVEN | Via `_initializeValidation`. |
| `upgradeToAndCall(impl, data)` | AC | H | ✅ PROVEN | Phase A #3 (`KernelUUPSHalmos.t.sol`). |
| `_authorizeUpgrade(impl)` | AC | H | ✅ PROVEN | Same. |
| `proxiableUUID()` pure | — | — | 🔵 OOS | EIP-1822 constant. |

## `src/Kernel7702.sol` / `src/KernelImmutableECDSA.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `_verifyFallbackSignature(hash, sig)` | NB (iff ECDSA recovery) | H | ✅ PROVEN | Phase A #9 (`FallbackSignatureHalmos.t.sol`). Both variants. |
| `_fallbackValidatorAvailable()` pure | — | — | 🔵 OOS | Constant. |
| `_erc1271RawAllowed()` pure | — | — | 🔵 OOS | Constant. |
| `_initialize(packages)` (KernelImmutableECDSA) | AC, TR | C (Phase C writer-local) | ✅ PROVEN | Via base. |

## `src/KernelFactory.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `deploy(initialPackages, nonce)` | DT, NR (no double-init) | H | ✅ PROVEN | Phase A #12. |
| `deployECDSA(signer, initialPackages, nonce)` | DT, NR | H | ✅ PROVEN | Same. |
| `getAddress(initialPackages, nonce)` view | DT | H | ✅ PROVEN | Same. |
| `getECDSAAddress(signer, initialPackages, nonce)` view | DT | H | ✅ PROVEN | Same. |
| `_initialize(...)` | TR | — | ❌ OPEN | Factory-level init. |

## `src/Staker.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `deployWithFactory(factory, createData)` | — | — | 🔵 OOS | Factory call wrapper. |
| `approveFactory(factory, approval)` | AC | — | ❌ OPEN | `onlyOwner`; quick Halmos target. |
| `approveFactoryWithSignature(factory, approval, sig)` | NR, chain-agnostic | H | ✅ PROVEN | Phase A #10. |
| `stake(entryPoint, unstakeDelay)` | AC | — | ❌ OPEN | `onlyOwner` only; low priority. |
| `unlockStake(entryPoint)` | AC | — | ❌ OPEN | Same. |
| `withdrawStake(entryPoint, recipient)` | AC | — | ❌ OPEN | Same. |

## `src/lib/ERC1271.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `isValidSignature(hash, sig)` public view | NB | H + M | ✅ PROVEN | Manual CFG + Phase E Halmos PersonalSign. |
| `_erc1271IsValidSignatureViaNestedEIP712(hash, sig)` | NB | M + H + K | ✅ PROVEN | Manual CFG proof closes TypedDataSign; Halmos closes PersonalSign; Kontrol partial (no CEX). |
| `_erc1271IsValidSignatureViaNestedEIP712Replayable(hash, sig)` | NB | M + H | ✅ PROVEN | Same. |
| `_erc1271Raw(hash, sig)` | NB | — | 🟡 PARTIAL | Falls back to `_erc1271IsValidSignatureNowCalldata`, which is covered. |

## `src/lib/Lib4337.sol`

| Function | Obligations | Backend | Status | Evidence |
|---|---|---|---|---|
| `intersectValidationData(a, b)` | TR (aggregator preservation) | H | ✅ PROVEN | Phase A #2 (`Lib4337Halmos.t.sol`, 8/8 PASS). |
| `chainAgnosticUserOpHash(sender, op)` | DT | — | ❌ OPEN | Quick Halmos target if needed; mostly used for replayable mode. |
| `parseNonce(nonce)` | DT | H | ✅ PROVEN | Phase A #8 (`ParseNonceHalmos.t.sol`). |

---

## Summary

| Layer | Count | Status |
|---|---|---|
| Public/external functions | 22 | 14 proven, 4 partial, 4 open or OOS |
| Security-relevant internal helpers | ~30 | 18 proven, 6 partial, 6 open |
| Total obligations identified | ~60 | ~38 proven, ~10 partial, ~12 open |

**Coverage score (proof-obligation form)**: ~63 % proven outright, ~17 % partial, ~20 % open or out-of-scope.

## Next-round priorities

Sorted by audit value × ease:

1. **`_verifyInstallSignatureRaw`** — install-signature gate; the ONE explicit OPEN gap with a clear security obligation. Halmos partial with bounded packages + bounded signature length should work.
2. **`_executeCall` / `_executeDelegateCall`** — bounded-calldata Halmos targets.
3. **`_checkValidation`** — routing predicate; quick Certora rule.
4. **`_installHash`** — pure salt derivation; trivial Halmos target.
5. **`approveFactory` / `stake` / `unlockStake` / `withdrawStake`** — pure `onlyOwner` AC; one Halmos test covers all four.
6. **`_install/uninstall{Executor, Hook, Selector}` writers** — extend Phase C's writer-local pattern to these.

## How to maintain this board

- Update after every Round N FV dispatch (success or refusal).
- Move rows between Status columns as backends close gaps.
- Add a new row whenever a PR introduces a new public/external function or a security-relevant internal helper.
- Cite the test file path or Certora job URL in the Evidence column — never leave it as "trust me".
