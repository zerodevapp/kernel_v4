# Kernel v4 — Security Audit Report

**Audit branch:** `fix/audit-internal-batch-1` (head `664fd76`)
**Scope:** `src/` (Kernel v4 core) + `kernel-7579-plugins/src/` (in-scope ERC-7579 modules)
**Methodology:** Three-headed audit (Feynman + State + Master Audit Skill catalog) with external-model dispatch (codex gpt-5.4 xhigh, gemini-3.1-pro, grok-build) and git-log review of parallel-branch fix commits
**Report date:** 2026-05-26

---

## Executive summary

**5 open HIGH-severity findings** are present on the audit branch. Two were independently surfaced by external-model dispatch; three were surfaced by reviewing fix commits the team has already shipped on the `audit/fv-round-1` branch but has not yet brought into the audit branch.

| ID | Title | Status | Fix available |
|----|-------|--------|---------------|
| HIGH-01 | Enable-mode ERC-1271 `_checkNonce` doesn't increment — pre-signed enable signatures replayable forever | OPEN | none — design change required |
| HIGH-02 | Stateless ECDSA `_verifySignature` accepts garbage signatures when expected signer is `address(0)` | OPEN | trivial — add `signer != 0` guard in plugin |
| HIGH-03 | `_installExecutor` accepts EOA/codeless/non-IModule address — installed EOA owns the kernel via `executeFromExecutor` | OPEN | trivial — mirror validator hardening |
| HIGH-04 | `executeUserOp.selector` grant to non-root validation bypasses inner-selector allow-list → full kernel takeover | OPEN | cherry-pick `0921b25` from `audit/fv-round-1` |
| HIGH-05 | `_setRoot` rotation does not invalidate stale grants on demoted root → fast-path bypass re-engages (companion to HIGH-04) | OPEN | cherry-pick `ce185f6` from `audit/fv-round-1` |

5 previously-known issues are confirmed fixed (FIX-01..05). One root-hook bypass is documented and intentional (BYDES-01). Two suggestions from external models were verified as non-bugs and recorded as disproven (NEG-01 Staker nonce-grief, NEG-02 setRoot self-replacement brick).

All findings carry runnable PoCs at `test/audit/` that pass against the current branch when the bug is present, and fail (kernel correctly reverts) once the fix is applied.

---

## How to reproduce

```bash
# from the repo root
forge test --match-path 'test/audit/*.t.sol'
```

Expected outcome on `664fd76`:
- 12 tests PASS — open bugs (HIGH-01..05) plus BYDES-01 + 2 disproven negative-results.
- 6 tests FAIL with kernel reverts — already-applied fixes (FIX-01..03) correctly reject the PoC inputs.

---

## Finding 1 — HIGH-01: Phantom session key (enable-mode ERC-1271 nonce never increments)

**Locations**
- `src/core/ModuleManager.sol:151` — `_erc1271IsValidSignatureNowCalldata` calls view-only `_checkNonce(sig.nonce)` instead of `_checkAndIncrementNonce`.
- `src/Kernel.sol:149` — the userOp enable path correctly calls `_checkAndIncrementNonce(sig.nonce)`. The ERC-1271 path cannot, because `isValidSignature` is `view`.

**Mechanism**
A root-signed `EnableModeSignature{nonce, packages, enableSignature, userOpSignature}` whose nonce has never been consumed on-chain becomes a permanent ERC-1271 forgery oracle. The session-key holder produces a fresh ECDSA signature per attacker-chosen hash; the root's enable signature is the single credential that unlocks the session key's authority for off-chain flows.

**Realistic impact**
Account holding 100 USDC with Permit2 approval. User signs an enable-mode install for a session key during onboarding; the userOp is dropped by the bundler (gas price race, fee market shift, paymaster postOp revert — normal bundler failure modes). Attacker who later compromises the session key produces ERC-1271 signatures for Permit2 / Seaport / Uniswap-X / DAI-permit indefinitely. No on-chain footprint until each attack hash is consumed by its respective flow.

**Recommended fix**
Bind the ERC-1271 enable-mode signature to the hash being verified — make the install digest a function of `hash` so a session-key signature isn't replayable across different hashes.

**PoC**
`test/audit/PhantomSessionKey.t.sol` — both tests PASS (bug present).

---

## Finding 2 — HIGH-02: Zero-address stateless ECDSA bypass

**Locations**
- `kernel-7579-plugins/src/validators/ECDSAValidator.sol:60-67` (`_verifySignature`) and `:101-117` (stateless entry points).
- `kernel-7579-plugins/src/signers/ECDSASigner.sol:30-37` (helper) and `:84-100` (stateless entry points).

**Mechanism**
Solady's `ECDSA.tryRecoverCalldata` returns `address(0)` on recovery failure. The stateful entry points (`validateUserOp`, `isValidSignatureWithSender`) carry an explicit `if (owner == address(0)) return SIG_VALIDATION_FAILED_UINT;` guard. The stateless paths do not. When the kernel passes `moduleData = bytes20(0)` to `_verifySignature(hash, garbageSig, signer=0)`, the comparison `address(0) == ECDSA.tryRecoverCalldata(hash, garbageSig)` returns `true` and the verifier accepts.

**Mechanism — chained with HIGH-01**
The kernel's `_verifyStatelessSignature` (ModuleManager.sol:384-441) is reached from the ERC-1271 enable-mode path without `_install` running. A root-signed enable package with `moduleData = bytes20(0)` becomes a permanent ERC-1271 forgery oracle: any 65-byte garbage signature validates against `signer == address(0)`. Combined with HIGH-01's never-consumed nonce, a single root signature on a malformed install package authorises arbitrary ERC-1271 outputs for the lifetime of the account.

**Realistic impact**
User signs a single typed-data prompt where the wallet renders `moduleData` as opaque hex behind a "details" toggle — a documented UX gap in mainstream wallets (MetaMask, Rainbow, Frame, hardware wallets routed through any of them). Account is drained across all ERC-1271-gated flows in a single block. No further user interaction required.

**Recommended fix**
Add `if (signer == address(0)) return false;` at the top of `_verifySignature` in both `ECDSAValidator` and `ECDSASigner`. Matches the protection the stateful paths already have. The comment at `ECDSAValidator.sol:76` already documents the invariant the stateless path is missing.

**PoC**
`test/audit/ZeroAddressStatelessBypass.t.sol` — both tests PASS (bug present).

---

## Finding 3 — HIGH-03: EOA installable as executor → direct kernel drain

**Location**
`src/core/ExecutorManager.sol:41-50` (`_installExecutor`).

**Mechanism**
The executor install path explicitly ignores `_installSuccess`, does not check `_executor.code.length > 0`, and does not check `IModule(_executor).isModuleType(MODULE_TYPE_EXECUTOR)`. Compare to the validator install path (`src/core/ValidationManager.sol:143-151`) which has all three guards after the FIX-01 hardening. For an EOA-address module, `module.call(onInstall(data))` succeeds with empty returndata; `_installExecutor` ignores the lack of code and records the EOA as an installed executor.

After install, the `executorHook` modifier (`ModuleManager.sol:56-62`) authorises calls to `executeFromExecutor` purely by `_executorConfig(IExecutor(msg.sender)).hook != HOOK_MODULE_NOT_INSTALLED`. No additional code/type check. The EOA can directly call `kernel.executeFromExecutor(mode, executionData)` and trigger `_execute(mode, executionData)` for arbitrary external call / delegatecall.

**Realistic impact**
Account holding 5 ETH + 100,000 USDC. Owner signs an enable-mode or direct install with `Install{moduleType: 2, module: attackerEOA, ...}` — same wallet-UX phishing class as HIGH-02. Once installed, the attacker EOA calls `executeFromExecutor` directly:
1. `executeFromExecutor(SINGLE, encodePacked(recipient=attacker, value=5 ether, ""))` → drains 5 ETH.
2. `executeFromExecutor(SINGLE, encodePacked(USDC, 0, transfer(attacker, 100000e6)))` → drains 100k USDC.
3. `executeFromExecutor(SINGLE, encodePacked(address(this), 0, encodeWithSelector(Kernel.setRoot.selector, attackerPackages, false, "")))` → installs attacker's validator as root. Permanent takeover.

**Recommended fix**
Mirror the validator hardening exactly:

```solidity
function _installExecutor(address _executor, bytes calldata _internalData, bool _installSuccess) internal {
    require(_installSuccess, ModuleInstallFailed());
    require(_executor.code.length > 0, ModuleInstallFailed());
    require(IModule(_executor).isModuleType(MODULE_TYPE_EXECUTOR), ModuleInstallFailed());
    // ...existing hook handling...
}
```

Drop the "we don't care if install was successful" comment — that exact relaxation is what enables the EOA path.

**PoC**
`test/audit/EOAExecutorBypass.t.sol` — both tests PASS (bug present).

---

## Finding 4 — HIGH-04: `executeUserOp.selector` grant to non-root validation enables full kernel takeover

**Location**
- `src/Kernel.sol:172-185` — `_processUserOp` fast-path bypasses inner-selector check when outer selector is allow-listed and validation has no hook.
- `src/Kernel.sol:201-213` — `executeUserOp` delegatecalls `userOp.callData[4:]` with `msg.sender == EntryPoint` preserved.
- `src/core/ValidationManager.sol:91-101` — `_grantAccess` (current) does NOT reject `executeUserOp.selector`.

**Fix exists on `audit/fv-round-1` (commit `0921b25` — "fix: block executeUserOp.selector grant to non-root validations") but is NOT in this branch.**

**Mechanism**
A side validation with `hook == HOOK_MODULE_INSTALLED_NO_HOOK` and `executeUserOp.selector` in its `allowed` map is admitted by the first branch of `_processUserOp` (the fast-path). The else-branch's `_allowedSelector(vId, bytes4(userOp.callData[4:]))` inner-selector check is skipped entirely. `executeUserOp` then does `address(this).delegatecall(userOp.callData[4:])` preserving `msg.sender == EntryPoint`, and the inner dispatch sails through `_onlyEntryPointOrSelf()` on `setRoot`, `installModule`, `execute`, `grantAccess`, `uninstallModule`, `setNonce`, `setValidNonceFrom`.

**Realistic impact**
Owner installs a side validator with `executeUserOp.selector` granted (intent: "this validator can submit userOps that go through the hook-wrapped path"). The side validator's key holder — a compromised session key, a dApp-controlled signer, an EOA that the user later considers deprecated — submits a userOp whose callData is `executeUserOp.selector || setRoot(attackerPackages, false, "")`. Fast-path triggers; inner setRoot dispatches; attacker becomes root.

**Recommended fix**
Cherry-pick commit `0921b25` from `audit/fv-round-1`:

```solidity
// src/core/ValidationManager.sol — inside _grantAccess
while (selectors.length >= 4) {
    bytes4 selector = bytes4(selectors[0:4]);
    require(
        selector != IAccountExecute.executeUserOp.selector || vId == $.root,
        InvalidSelectorGrant()
    );
    $.allowed[vId][selector] = nonce;
    selectors = selectors[4:];
}
```

Add `error InvalidSelectorGrant();` to `src/types/Error.sol`. Import `IAccountExecute`.

**PoC**
`test/audit/ExecuteUserOpSelectorTakeover.t.sol` — PASS (bug present).

---

## Finding 5 — HIGH-05: `_setRoot` rotation does not invalidate stale grants on demoted root

**Location**
`src/core/ValidationManager.sol:443-459` (`_setRoot(ValidationId)`).

**Fix exists on `audit/fv-round-1` (commit `ce185f6` — "fix: bump old root nonce on _setRoot rotation") but is NOT in this branch.**

**Mechanism (companion to HIGH-04)**
`_setRoot` updates `$.root` but does NOT bump `vInfo[oldRoot].nonce`. Any `allowed[oldRoot][selector]` entry that matched the old nonce continues to match after demotion. The demoted root retains its prior selector grants as a side validator.

The team's own FV (Certora) Round 2 explicitly documents this in `audit/fv-round-1-findings.md`: HIGH-04's `_grantAccess` fix alone leaves the rotation residual reachable on 8 entry points (`setRoot` overloads, `initialize`, `executeUserOp`, `execute`, `executeFromExecutor`, `upgradeToAndCall`, fallback path). Both `0921b25` and `ce185f6` are required for complete remediation.

**Attack sequence (post-`0921b25`-fix, still reachable without `ce185f6`)**
1. While V is root: `_initializeValidation(V, [HOOK_NO_HOOK | executeUserOp.selector | ...])` sets `allowed[V][executeUserOp.selector] = 1`, `vInfo[V].nonce = 1`. Grant is harmless because root bypasses selector check.
2. `setRoot(R2_pkg, false, "")` rotates root to R2. `vInfo[V].nonce` stays at 1; `allowed[V][executeUserOp.selector]` stays at 1.
3. V is now a non-root validation with `_allowedSelector(V, executeUserOp.selector) == true` and `hook == HOOK_NO_HOOK`.
4. Attacker with V's key submits a userOp with callData = `executeUserOp.selector || setRoot(attackerPackages, false, "")`. Fast-path triggers; inner setRoot dispatches; attacker becomes root.

**Realistic impact**
Owner originally installed root V1 with `internalData = [HOOK_NO_HOOK | executeUserOp.selector]` — a sensible-looking default ("future-proof, harmless while root"). Owner rotates root to V2 for routine key hygiene; V1 remains installed for backup-recovery purposes. The old V1 key leaks (sold phone, compromised cloud backup, old hardware wallet). The attacker holding V1 silently re-takes root via the stale grant — the user has no on-chain indication that the demoted key retained authority.

**Recommended fix**
Cherry-pick commit `ce185f6` from `audit/fv-round-1`:

```solidity
function _setRoot(ValidationId vId) internal {
    // ...existing checks...
    ValidationStorage storage $ = _validationStorage();
    if (ValidationId.unwrap(vId) != bytes21(0)) {
        require($.vInfo[vId].hook > HOOK_MODULE_NOT_INSTALLED, InvalidVid(vId));
    }
    // Invalidate stale grants on the previous root when rotating.
    ValidationId oldRoot = $.root;
    if (ValidationId.unwrap(oldRoot) != bytes21(0) && oldRoot != vId) {
        ++$.vInfo[oldRoot].nonce;
    }
    $.root = vId;
}
```

First install (oldRoot zero) and identity rotation are no-op skips. Cost: one SSTORE per rotation event.

**PoC**
`test/audit/SetRootRotationResidual.t.sol` — both tests PASS (bug present).

---

## Confirmed fixes (FIX-01..05)

All five previously-known issues are confirmed fixed on the audit branch. The original PoCs now FAIL with kernel reverts.

| ID | Title | Fix commit | PoC outcome |
|----|-------|------------|-------------|
| FIX-01 | Validator returndata length missing → silent SUCCESS for codeless validator | `bccbb5d` | `test/audit/EmptyValidator.t.sol` FAILS with `ModuleInstallFailed()` |
| FIX-02 | Selector grants resurrect after uninstall/blank-reinstall | `9f9471c` | `test/audit/SelectorResurrect.t.sol` + `test/audit/PermissionSelectorResurrect.t.sol` FAIL with `AA23 reverted` |
| FIX-03 | Side validator with empty `internalData` had blanket selector access | `9f9471c` | `test/audit/DefaultAllowSelector.t.sol` FAILS with `AA23 reverted` |
| FIX-04 | `_verifyStatelessSignature` permission path accepted matching `pId` from any module type | `bfbef77` | no committed PoC; fix verified by inspection |
| FIX-05 | `_setRoot` could promote uninstalled `vId` to root | `5a6c865` | no committed PoC; fix verified by inspection |

---

## By-design

**BYDES-01** — `src/Kernel.sol:160-184` documents that ROOT-authorized userOps intentionally bypass the validation hook and selector allow-list, so a misconfigured / compromised hook on a scoped validation cannot lock the user out of their own account. Verified by `test/audit/RootHookBypass.t.sol` (PASS = behavior confirmed, not a finding).

---

## Disproven claims from this audit pass

**NEG-01** (Grok) — Staker `nonces[_factory]++` runs before signature verify, allowing nonce-grief.
Disproven: standard Solidity revert semantics roll back the SSTORE when `require(...)` fires. `test/audit/StakerNonceCheck.t.sol` confirms (PASS = rollback works).

**NEG-02** (Gemini-3.1-pro) — `setRoot(pkg, true, uninstallData)` self-replacement bricks the kernel when `pkg[0]` resolves to the current root's `vId`.
Disproven: `_uninstallValidation`'s `require($.root != _vId, CannotUninstallRoot())` guard reverts the whole operation safely. `test/audit/SetRootSelfBrick.t.sol` confirms (PASS = revert is correct).

---

## Out of scope / pre-existing

Carried over from prior audits and not re-evaluated this pass:
- DELEGATECALL via `execute` / `executeFromExecutor` — by-design per `Kernel.sol:195-198` explicit code comment.
- Kernel7702 raw ERC-1271 acceptance — by-design.
- M-V3-02 ERC-1271 broad validator authority — documented MEDIUM.
- Staker `approveFactoryWithSignature` chain-agnostic — documented MEDIUM.
- TimelockPolicy proposal marked `Executed` during validation — documented LOW.
- TimelockPolicy proposal data not signer-bound — documented MEDIUM.

---

## PoC inventory

| File | Tests | Behavior on `664fd76` |
|------|-------|----------------------|
| `test/audit/PhantomSessionKey.t.sol` | 2 | PASS (HIGH-01 bug present) |
| `test/audit/ZeroAddressStatelessBypass.t.sol` | 2 | PASS (HIGH-02 bug present) |
| `test/audit/EOAExecutorBypass.t.sol` | 2 | PASS (HIGH-03 bug present) |
| `test/audit/ExecuteUserOpSelectorTakeover.t.sol` | 1 | PASS (HIGH-04 bug present) |
| `test/audit/SetRootRotationResidual.t.sol` | 2 | PASS (HIGH-05 bug present) |
| `test/audit/RootHookBypass.t.sol` | 1 | PASS (BYDES-01 confirmed) |
| `test/audit/StakerNonceCheck.t.sol` | 1 | PASS (NEG-01 disproven) |
| `test/audit/SetRootSelfBrick.t.sol` | 1 | PASS (NEG-02 disproven) |
| `test/audit/EmptyValidator.t.sol` | 2 | FAIL (FIX-01 applied) |
| `test/audit/SelectorResurrect.t.sol` | 1 | FAIL (FIX-02 applied) |
| `test/audit/DefaultAllowSelector.t.sol` | 2 | FAIL (FIX-02 + FIX-03 applied) |
| `test/audit/PermissionSelectorResurrect.t.sol` | 1 | FAIL (FIX-02 applied) |

Run `forge test --match-path 'test/audit/*.t.sol'` to reproduce. Expected total: 12 passing, 6 failing.

---

## Recommended remediation order

1. **HIGH-02** — one-line guard in plugin; trivially backportable; closes the worst chain (combines with HIGH-01 for permanent ERC-1271 forgery oracle on one user signature).
2. **HIGH-04** — cherry-pick `0921b25`; one-line require + new error + import.
3. **HIGH-05** — cherry-pick `ce185f6`; one-line nonce bump + new local variable. Required to fully close HIGH-04.
4. **HIGH-03** — mirror validator hardening in `_installExecutor`; three-line block.
5. **HIGH-01** — requires design discussion. Options:
   - Bind the ERC-1271 enable-mode signature to `hash` (make the install digest a function of the verified hash so each session-key signature is single-use against a fixed hash).
   - Remove the ERC-1271 enable-mode path entirely; require modules to be installed via a successful userOp before any ERC-1271 query.

After remediation: re-run `forge test --match-path 'test/audit/*.t.sol'` and confirm the 12 currently-passing PoCs all FAIL (kernel correctly rejecting the attack vectors).

---

## Audit methodology notes

- 7 perspectives consulted per finding (main / Feynman lens / State lens / Master Audit Skill catalog / codex gpt-5.4 xhigh / gemini-3.1-pro / grok-build).
- HIGH-03 was a single-source codex find (1/7) — the kind of pattern other heads classify as "configuration risk" by default.
- HIGH-04 was gemini-hinted (1/7) and confirmed via git-log review of the team's `audit/fv-round-1` branch.
- HIGH-05 was found via git-log review (0/7 external models surfaced it independently); the team's own Certora FV Round 2 had already documented it as the Phase C residual.
- **Lesson:** when the team has shipped fix commits on a parallel branch that the audit branch does not contain, that's a structural reason to re-examine, not a configuration choice to dismiss. Five out of seven heads dismissed both HIGH-04 and HIGH-05 as "documented configuration risk per `Kernel.sol:195-198` SECURITY comment" — but the comment was itself outdated relative to the team's own subsequent FV findings.

---

## Open questions for the team

1. Why are `0921b25` (HIGH-04 fix) and `ce185f6` (HIGH-05 fix) not yet in `fix/audit-internal-batch-1`? Are they planned for a different release cut?
2. For HIGH-01: is the project willing to either (a) bind the ERC-1271 enable signature to `hash`, or (b) remove the ERC-1271 enable-mode path entirely? If neither is acceptable, the residual risk needs to be documented in user-facing materials.
3. For HIGH-02: confirm the same `signer != 0` guard should be added to `ECDSAValidator._verifySignature` and `ECDSASigner._verifySignature`. The plugins are versioned separately from the kernel core — what is the release path?
4. For HIGH-03: should `_installSelector` (fallback) and `_installHook` get the same code/type checks for consistency? Their failure modes are softer (DoS via codeless target) but the asymmetry with the validator path is itself a maintenance hazard.
