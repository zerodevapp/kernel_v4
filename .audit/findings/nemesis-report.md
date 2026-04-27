# Nemesis Audit Report — Kernel v4

**Scope**: `./src/` (Kernel core + managers) and `./kernel-7579-plugins/src/` per `SCOPE.md`.
**Already-fixed (excluded)**: PRs #32, #34, #37, #38.
**Dispatch**: Claude + Codex (`gpt-5.4`, `model_reasoning_effort=xhigh`) + Gemini (`gemini-3.1-pro-preview`) + an independent code-review subagent.
**Severity rubric**: Immunefi smart-contract severity classification.

## Summary

Fix status checked against `origin/v0.4.0` @ `560f15d`. See `.audit/findings/v0.4.0-fix-status.md` for per-finding verdicts and the failing tests under `test/audit-pending/`.

| # | Severity | Title | Provenance | Fix status (v0.4.0) |
|---|----------|-------|------------|---------------------|
| 1 | **HIGH** | Default-allow selector grant — any non-root validator installed with empty internalData has unrestricted access to every kernel selector (including `setRoot` → governance takeover) | code-reviewer + claude + codex | ✅ FIXED |
| 2 | **HIGH** | Selector grants resurrect after uninstall + minimal-internalData reinstall (validator path AND permission-signer path — same root cause in `_initializeValidation`) | codex + claude | ✅ FIXED |
| 3 | **HIGH** | Phantom session key — pre-signed enable-mode install whose userOp nonce is never consumed grants UNLIMITED ERC-1271 signing authority to the would-be session key (`_erc1271IsValidSignatureNowCalldata` enable branch calls `_checkNonce` view-only, no increment) | gemini + claude | ❌ UNFIXED |
| 4 | MEDIUM | `vType = ROOT` short-circuits the root validator's hook AND the selector allowlist (defense-in-depth bypass under compromised-root threat model) | codex | ❌ UNFIXED |
| 5 | MEDIUM | TimelockPolicy marks proposal `Executed` during validation — execution revert burns the key; mitigated by ERC-4337 nonce consumption | codex | ❌ UNFIXED *(re-rated LOW in fix-status)* |
| 6 | MEDIUM | TimelockPolicy proposal contents carried in the policy-sig slot and not bound to the signer's approval | codex | ❌ UNFIXED |
| 7 | LOW | Codeless-address validator authorizes every userOp (`bytes32(empty)=0=SIG_VALIDATION_SUCCESS`); requires owner-signed install of a codeless address | codex + claude + gemini | ✅ FIXED |
| 8 | LOW | `_verifyStatelessSignature` PERMISSION branch matches packages by `bytes4(internalData) == pId` regardless of moduleType; requires owner-signed crafted package set | gemini + codex + claude | 🟡 PARTIAL (last-package check added; non-last positions still un-typed) |
| 9 | LOW | `MODULE_TYPE_STATELESS_VALIDATOR_WITH_SENDER` (type 10) modules drop the `sender` arg and silently downgrade to type 7 semantics | codex | 🟡 DOCUMENTED *(re-rated INFO)* |
| 10 | LOW | `_setRoot(ValidationId)` does not require the target vId to be installed (`vInfo[vId].hook != 0`); owner can self-brick the `vType=ROOT` path by pointing root at an uninstalled vId | code-reviewer + claude | ✅ FIXED |

**Out-of-scope / informational (not counted above):**
- Staker `approveFactoryWithSignature` is chain-agnostic — `Staker.sol` is not in `SCOPE.md`'s contract listing, and the behavior is documented as intentional.

**All 9 PoC tests pass** under Foundry v-latest docker build (solc 0.8.30). See PoC run instructions below.

### Severity methodology

Final distribution after consistent application of Immunefi severity criteria: **3 High / 3 Medium / 4 Low**.

The governing principle applied across every finding: **the attacker's precondition set** determines the severity cap. A vulnerability that requires the root signer to have taken a specific on-chain action (install a particular module, sign a crafted package list, install a module with a codeless target) is capped at HIGH at best — even if the post-condition is total loss — because the owner's signature is the enabling step. Owner-authenticated admin actions that silently exceed the owner's expressed intent are HIGH; owner-authenticated actions whose safety depends on the owner screening the install arguments (codeless address, crafted package list, specific moduleType mismatch) are LOW/MEDIUM.

- **HIGH #1 (was CRITICAL in an earlier draft):** Default-allow selector grant. Downgraded from Critical → High after applying the precondition rule consistently. The exploit does produce `setRoot`-level governance takeover, but the enabling step is the owner signing an install of a non-root validator with `internalData = hex""`. That is a documented, common-in-tests flow (see `test/Kernel.t.sol:81`), and the contract's interpretation silently inverts the owner's "restricted by default" mental model — so HIGH, not MEDIUM. Not CRITICAL because the attacker cannot initiate the exploit without the owner first signing the install.
- **HIGH #2 (merged from validator-path + permission-signer-path):** Codex's verdict was explicit — *"still 4 independent Highs, or 5 only if you split A1 off as a separate permission-specific instance of the same stale-selector resurrection bug."* Both paths share a single root cause in `_initializeValidation` and a single one-line fix; Immunefi counts one root cause as one finding. Both PoCs are retained as evidence.
- **HIGH #3 (Phantom session key — surfaced by Gemini on the crypto-path pass):** Pre-signed enable-mode install whose userOp never submitted gives the would-be session key UNLIMITED ERC-1271 signing authority. Owner's mental model for `enable-mode` install: "I pre-signed one userOp; if it doesn't run, nothing happens." Contract behaviour: `_erc1271IsValidSignatureNowCalldata` enable branch at `ModuleManager.sol:119-133` validates the session key's signature for arbitrary hashes as long as the root-signed install package's nonce is unconsumed — and the nonce is checked VIEW-ONLY (never incremented). With a compromised session key, attacker drains every Permit2/Seaport/Uniswap-X/DAI-permit integration. HIGH because (a) the two preconditions (pre-signed install + key compromise) are both realistic operational states for session-key accounts, and (b) the post-condition is direct theft of funds.
- **MEDIUM #4 (`vType=ROOT` skips hook):** Defense-in-depth bypass under compromised-root threat model. Immunefi treats defense-in-depth under privileged-compromise as Medium, not High.
- **MEDIUM #5-#6 (Timelock premature `Executed`, Timelock proposal-data unbinding):** Griefing / proposal-key-burn. Neither results in direct fund loss; both are Medium griefing under Immunefi.
- **LOW #7 (Codeless validator, was MEDIUM in earlier draft):** Downgraded from Medium → Low. Requires the root signer to sign an install whose `module` address has no deployed code — a precondition a realistic wallet UI screens out, and which is also trivially preventable by a one-line `extcodesize` check. The missing returndata-length guard at `ValidationManager.sol:282-287` is a real contract bug, but the exploit prerequisite (codeless-address install) is a narrow admin misconfiguration rather than a normal flow, so the severity tracks the precondition's narrowness.
- **LOW #8 (`_verifyStatelessSignature` moduleType mismatch):** Exploit path requires the root to sign a crafted `Install[]` package list whose non-policy module has `bytes4(internalData) == pId`. Narrow admin misconfiguration + an attacker-authored module. Low, matching the severity rule rather than averaging Gemini HIGH / Codex LOW.
- **LOW #9 (type-10 `sender` dropped):** Interface-contract violation; no direct fund loss, downstream consumers that rely on the type-10 guarantee are the affected surface. Low.
- **LOW #10 (`_setRoot(ValidationId)` missing installed-vId check — surfaced by the code-reviewer subagent):** Admin-footgun DoS. `_setRoot(vId)` validates `vType` and non-zero but never checks `vInfo[vId].hook != 0`, so a root-authorized caller can set root to a vId that has never been initialized. Subsequent `vType=ROOT` userOps hit `require(info.hook > address(0))` at `ValidationManager.sol:200` and revert. Not a direct privilege escalation (caller must already be root-authorized to call `setRoot`), and `vType=VALIDATOR` / `vType=PERMISSION` paths still work with other installed validators — so Low, owner-misconfiguration DoS only.

**Previously-proposed HIGH candidates verified as FALSE POSITIVES:**
- Gemini's "KernelFactory front-run" — `dependencies/solady-0.1.26/src/utils/LibClone.sol:1040` binds the CREATE2 address to `address()` (the factory itself). Third party cannot collide.
- Executor/Selector/Hook install-success-skipped cluster — gated by root-authorized install; no new privilege.
- ECDSA malleability / WeightedECDSA cross-chain / TimelockPolicy NoOp detection / Permissionless installModule meta-tx — all confirmed not-HIGH by codex with specific reasoning.

---

## HIGH #1 — Default-allow selector grant (any non-root validator = unrestricted co-root)
PoC: `test/audit/DefaultAllowSelector.t.sol` (both tests PASS — Alice drains 5 ETH; Alice also installs her own validator and flips root via `setRoot`).

### Severity rationale
The post-condition is severe: PoC `test_PoC_side_validator_can_takeover_via_setRoot` shows the non-root validator's signer calling `setRoot` and permanently locking the owner out. The precondition, however, is that the owner signed an install of that non-root validator with `internalData = hex""` — a routine and documented kernel install flow (see `test/Kernel.t.sol:81`), not a phishing-specific construction.

Rated **HIGH**, not Critical, under Immunefi's precondition rule: attacker cannot initiate exploitation without the owner first signing an install. The reason this is HIGH rather than MEDIUM is that the install flow in question is the normal/documented one — the contract silently inverts the owner's "restricted by default" mental model (which the kernel's own `test_install_validator_with_other_selector` codifies), so the owner's signed install produces a privilege envelope that exceeds the owner's expressed intent.

### Root cause
Three lines:
- `src/core/ValidationManager.sol:80-83`:
  ```solidity
  return $.allowed[vId][selector] == $.vInfo[vId].nonce;
  ```
  Both sides default to `0`, so `_allowedSelector` returns `true` for every `(vId, sel)` pair that was never touched by `_grantAccess`.
- `src/core/ValidationManager.sol:85-100` — `_initializeValidation` with empty internalData sets `hook = address(1)` and early-returns without bumping `nonce`.
- `src/Kernel.sol:120-122` — first-branch condition:
  ```solidity
  vType == VALIDATION_TYPE_ROOT
      || (_allowedSelector(vId, sel) && $.vInfo[vId].hook == address(1))
  ```
  For a non-root validator installed with empty internalData, `(true && address(1)==address(1))` → the first branch is taken; no selector check, no wrapper required, no hook ever set.

### Why this is a contract bug and not design intent
`test/KernelValidatorTest.sol:324` (`test_install_validator_with_other_selector`) installs a validator with `internalData = abi.encodePacked(address(0), kernel.setNonce.selector)` — granting exactly one selector — then expects `_sendUserOpValidator(false, false)`, i.e. the userOp targeting `execute` must fail. That test is direct evidence that the design *intends* selector grants to restrict. When `internalData = hex""` (the common default, including in this repo's own `test/Kernel.t.sol:81`), nonce stays at `0` and every grant vacuously matches, so the user's restriction intent is inverted into "allow everything".

### Exploit flow
1. Owner Bob installs a "side validator" owned by Alice (session key / dapp key / hardware-device key) with the default `internalData = hex""`. Bob's mental model: "Alice holds a sub-validator; she can sign userOps; without explicit `grantAccess` she has NO selector privileges."
2. Reality: `vInfo[sideVid].nonce = 0`; `allowed[sideVid][anySel] = 0`; `_allowedSelector(sideVid, anySel)` returns `true`; `hook == address(1)`. Alice's side validator has blanket access to every kernel selector.
3. Alice signs a userOp with `nonce.vType=VALIDATOR`, `vId=sideValidator`, `callData = installModule(1, aliceControlledValidator, ...)`. It passes validation (no hook, no selector check) and executes.
4. Alice signs a second userOp calling `setRoot(aliceControlledVid)`. It passes. **Root is now Alice's**; Bob is locked out.
5. Alice drains at leisure.

Demo PoC `test_PoC_side_validator_can_takeover_via_setRoot` does exactly steps 3-4; `test_PoC_side_validator_directly_calls_execute` does a direct 5-ETH drain in one userOp without even needing steps 3-4.

### Fix
Initialize `$.vInfo[vId].nonce = 1` (or any non-zero sentinel) inside `_initializeValidation` before either branch, so the default `allowed[vId][sel] = 0` never matches until a real `grantAccess` call bumps the nonce again. This one-line patch also single-handedly kills HIGH #2 below.

---

## HIGH #2 — Selector grants resurrect after uninstall + minimal-internalData reinstall
PoCs:
- `test/audit/SelectorResurrect.t.sol::test_PoC_grants_resurrect_after_uninstall_and_blank_reinstall` — VALIDATOR path.
- `test/audit/PermissionSelectorResurrect.t.sol::test_PoC_permission_selector_resurrects_on_signer_reinstall` — PERMISSION-signer path.

Both PoCs pass. Merged into one finding because both reach the same root-cause line and are fixed by the same one-liner.

### Root cause
Three interacting pieces:
1. `ValidationManager._grantAccess:67-77` versions selector grants by `vInfo[vId].nonce` — `allowed[vId][sel] = ++nonce`.
2. `ValidationManager._uninstallValidation:139-143` (and `_uninstallSignerWithVid:171-177` for the permission path) only zero `hook` / `signer`; neither clears `allowed[vId][sel]` and neither resets `vInfo[vId].nonce`.
3. `ValidationManager._initializeValidation:85-100` early-returns on empty internalData after setting `hook = address(1)`, **without** bumping the nonce. This same function is called from both `_installValidator:102-107` (with `internalData` passed through) and `_installSigner:115-121` (with `_internalData[4:]` — so a 4-byte pid-only install also hits the empty-internalData branch).

The test suite itself shows the common default: `test/Kernel.t.sol:81` installs a validator with `internalData: hex""`. Wallet UIs reasonably default to the same — "install with no hook, no selector restrictions".

### Exploit flow — VALIDATOR path
1. Owner installs side-validator `V` and grants it the `execute` selector via `grantAccess`. `vInfo[V].nonce=1`, `allowed[V][execute]=1`.
2. Owner uninstalls `V` to revoke the session key. `vInfo[V].hook=0`, but `nonce=1` and `allowed[V][execute]=1` persist.
3. Owner later wants to re-use `V` for a different, unrestricted workflow and reinstalls it with `internalData=hex""`.
4. `_initializeValidation` early-returns — `hook=1`, nonce stays at `1`.
5. The side-validator's holder signs a userOp to `execute(drainTo(attacker))`. `_allowedSelector(V, execute) = (1 == 1) = true`, `hook == address(1)` → direct path; userOp authorized and drains funds despite the owner's "revocation".

### Exploit flow — PERMISSION-signer path
1. Owner installs permission `(Policy_A, Signer_A)` for `pid_X`.
2. Owner grants `execute` to the permission via `grantAccess(permVid, [execute.selector])`. `vInfo[permVid].nonce = 1`, `allowed[permVid][execute] = 1`.
3. Owner rotates signer_A — uninstalls policy_A (LIFO required), then uninstalls signer_A. `vInfo[permVid].hook = 0`, `signer = 0`, `nonce = 1`, `allowed = 1`.
4. Owner reinstalls a new signer with `internalData = abi.encodePacked(pid_X)` — the minimal 4-byte form.
5. `_installSigner` passes `_internalData[4:]` (empty) to `_initializeValidation` → early-return branch → `hook = 1`, nonce stays at `1`.
6. New signer's holder submits a userOp under `vType=PERMISSION, vId=permVid, callData=execute(...)`. `_allowedSelector(permVid, execute) = (1 == 1) = true`; direct-call path taken; payload runs — the old grant has resurrected.

### PoC trace (permission path)
```
baseline — permission is installed, execute granted
  → userOp transfers 0.05 ETH via execute: PASS
uninstall mockPolicy (LIFO-first)
uninstall mockSigner       — signer=0, hook=0, nonce stays at 1
reinstall mockSigner with internalData = abi.encodePacked(PID)  — hook=1, nonce stays at 1
  → userOp transfers 0.05 ETH via execute: PASS   // bug: grant is still active
```

### Fix
`_initializeValidation` must always `++$.vInfo[vId].nonce` — placed before the empty-internalData early-return. A single patch covers both install paths and also covers HIGH #1 if the nonce is initialized to `1` on first install.

---

## HIGH #3 — Phantom session key via the enable-mode ERC-1271 path
PoC: `test/audit/PhantomSessionKey.t.sol` (2 tests PASS — validates arbitrary hash + validates unbounded number of distinct hashes under a single pre-signed credential).

### Severity rationale
Realistic two-factor preconditions + direct theft of funds:
- **Precondition 1:** Owner pre-signs an enable-mode install for a session key `K`. This is the entire intended flow for gas-less sponsored installs and on-demand session keys.
- **Precondition 2:** The userOp associated with the enable signature is not submitted / not executed on-chain. Realistic operational causes: bundler drops the op, user cancels, dApp-side state changes invalidate the callData, attacker withholds the op, user revokes by a different means without bumping this specific nonce key.
- **Precondition 3:** `K` is compromised OR willing to sign attacker-chosen hashes. Session keys typically live on less-secure surfaces (browser extensions, mobile apps, enclave-less hardware) and are assumed to be the weaker key in the threat model. Even an honest-but-tricked `K` (malicious dApp shows a benign-looking EIP-712 screen) yields the same outcome.
- **Post-condition:** Attacker forges ERC-1271 signatures for arbitrary hashes → drains Permit2/Seaport/Uniswap-X/CoWSwap/DAI-permit integrations. Every protocol that treats `isValidSignature` as authoritative for fund movement is affected.

Rated **HIGH** (not Medium). Compare to HIGH #1 (default-allow): both require an owner-signed install plus a compromised subordinate key. Here the post-condition is bounded to ERC-1271 (no direct `execute` authority) but ERC-1271 alone suffices for off-chain token drain via Permit2 et al. Rated HIGH, not Critical, under the same precondition rule applied elsewhere in this report.

### Root cause
Four interacting pieces:

1. `src/core/ModuleManager.sol:119-133` — `_erc1271IsValidSignatureNowCalldata`'s enable-mode branch:
   ```solidity
   if (isEnable(vMode)) {
       require(vType != VALIDATION_TYPE_ROOT, InvalidValidationType());
       bool enableReplayable = isEnableReplayable(vMode);
       EnableModeSignature calldata sig;
       assembly { sig := signature.offset }
       if (!Lib4337.checkValidation(
               _verifyInstallSignatureRaw(enableReplayable, sig.nonce, sig.packages, sig.enableSignature)
           )) {
           return false;
       }
       _checkNonce(sig.nonce);                                    // ← VIEW-ONLY, no increment
       return _verifyStatelessSignature(sig.packages, vId, hash, sig.userOpSignature);
   }
   ```
   (Note: `_verifyInstallSignatureRaw` at `ModuleManager.sol:302` already calls `_checkNonce(_nonce)` internally, so the explicit `_checkNonce(sig.nonce)` at line 132 is redundant — a refactor leftover. Both are view-only.)

2. `src/core/ModuleManager.sol:279-291` — `_checkNonce` is the view-only variant; it reverts on mismatch but never writes. Because `isValidSignature` is `view`, it CANNOT increment — so the consumed/unconsumed state of the nonce is entirely determined by whether anything ELSE (the userOp path) has bumped it.

3. `src/core/ModuleManager.sol:308-362` — `_verifyStatelessSignature` validates the `userOpSignature` against one of the root-signed packages WITHOUT requiring that package to have been installed on the account. That is: the session key can validate signatures even though it has no on-chain presence on the kernel.

4. The digest `_verifyInstallSignatureRaw` commits to is `(INSTALL_PACKAGES_STRUCT_HASH, nonce, installHash(packages))` only — it is **not bound to any specific ERC-1271 hash**. So a single (nonce, packages, enableSig) tuple authorises the session key to sign EVERY hash, not one.

### Exploit flow (step-by-step)
1. Owner prepares a gas-less enable-mode userOp: *"install `K` as a session-key validator, use it once for `callData` X."* The sig digest is `(INSTALL_PACKAGES_STRUCT_HASH, nonce=0, installHash([install_K]))`. Owner signs with root — call this `E`.
2. The userOp is handed to a bundler / broadcast on the bundler API. For any reason the userOp does not execute on-chain — bundler drops it, user cancels, userOp is replaced. Kernel's install-nonce `nonce[0]` remains `0`. `K` is not installed; `isModuleInstalled(1, K)` returns false.
3. Attacker obtains (i) the pre-signed `E` + the packages + the nonce (these travel together on public mempool/API surfaces) and (ii) `K`'s key, or induces honest-but-tricked `K` to sign a hash via a malicious dApp UI.
4. Attacker constructs a Permit2 (or Seaport/Uniswap-X/DAI-permit) digest `P` that authorizes transfer of account assets to attacker.
5. Attacker computes the wrapped hash that `_erc1271IsValidSignatureNowCalldata` will see: for a signature whose last 2 bytes are `0x0000`, Solady's `_erc1271IsValidSignatureViaNestedEIP712` falls back to PersonalSign, so `final_hash = _hashTypedData(keccak256(PERSONAL_SIGN_TYPEHASH, P))`.
6. Attacker has `K` sign `final_hash` (legitimate or via compromise) → `K_sig`.
7. Attacker assembles:
   ```
   sig = 0x08                                    // vMode = ENABLE
       || 0x01                                    // vType = VALIDATOR
       || bytes20(address(K_validator))
       || abi.encode(nonce=0, packages=[install_K], E, K_sig)
       || 0x0000                                  // PersonalSign-fallback trailer
   ```
8. Attacker (or the dApp) calls `kernel.isValidSignature(P, sig)`. Kernel routes through ERC1271 → PersonalSign fallback → `_erc1271IsValidSignatureNowCalldata`. The enable-mode branch: `_verifyInstallSignatureRaw` validates `E` against root ✓, `_checkNonce(0)` passes because `nonce[0] == 0` still ✓, `_verifyStatelessSignature` asks `K_validator.validateSignatureWithDataWithSender(msg.sender, final_hash, K_sig, install_K.moduleData)` → `K_sig` recovers to `K == abi.decode(moduleData)` ✓. Kernel returns `ERC1271_MAGICVALUE`.
9. Permit2 (or Seaport / Uniswap-X / ...) accepts, transfers out.

Because the enable credential is reusable until nonce bump, steps 4–9 repeat for every new asset / protocol without re-obtaining `E`.

### PoC trace
```
setup: kernel with rootValidator owned by Owner (key held off-chain)
Owner signs installDigest(address(kernel), replayable=false, nonce=0, [install_sessionValidator(alice)])
Owner does NOT submit the userOp
  assertEq(kernel.nonce(0), 0)                             // nonce still 0
  assertFalse(kernel.isModuleInstalled(1, sessionValidator)) // validator not installed

attacker picks attackerHash = keccak256("Permit2: drain 100 USDC")
attacker computes innerHash = _hashTypedData(keccak256(PERSONAL_SIGN_TYPEHASH, attackerHash))
alice.sign(innerHash) -> aliceSig
attackerSig = [0x08][0x01][addr(sessionValidator)] || abi.encode(0, packages, enableSig, aliceSig) || 0x0000
kernel.isValidSignature(attackerHash, attackerSig) -> 0x1626ba7e  // MAGICVALUE
```
And repeat with `attackerHash = keccak256("attack-1")`, `keccak256("attack-2")`, …  — all validate.

### Fix
Bind the enable credential to the hash being verified. `_verifyInstallSignatureRaw` must hash in the ERC-1271 `hash` parameter when invoked from the `isValidSignature` path — e.g., add a separate digest variant `_verifyInstallSignatureForERC1271(nonce, packages, enableSignature, hash)` whose struct-hash inputs include the `hash` the session key is being asked to validate. This makes each (nonce, packages, enableSig) tuple authorize exactly one ERC-1271 hash instead of an unlimited series of them, collapsing "durable session-key" semantics back into "single-use pre-auth" — which matches the owner's mental model when signing an enable-mode package for a specific userOp.

(A state-changing alternative — making the ERC-1271 path non-view and consuming the nonce on use — is not viable: `isValidSignature` is defined as `view` by ERC-1271, and breaking that breaks every downstream caller.)

---

## MEDIUM #4 — `vType = ROOT` skips validation hook AND selector allowlist
PoC: `test/audit/RootHookBypass.t.sol` (passes). CountingHook's `preCalls` / `postCalls` both remain `0` despite the hook being configured on the root validator.

### Severity rationale
Immunefi treats defense-in-depth bypasses under a compromised-admin threat model as Medium. The attack requires an attacker who already controls the root signer (HSM breach, phishing, multisig-seat compromise); the hook's failure to fire does not cause loss of funds on its own — it fails to *prevent* loss from an orthogonal compromise. The invariant "my root hook always runs" is genuinely violated at the contract level, which is why this is a real Medium and not an Informational.

### Root cause
`src/Kernel.sol:119-132`:
```solidity
if (
    vType == VALIDATION_TYPE_ROOT
        || (_allowedSelector(vId, bytes4(userOp.callData[0:4])) && $.vInfo[vId].hook == address(1))
) {
    // No-op, this is cheaper in gas
} else {
    require(
        bytes4(userOp.callData[0:4]) == this.executeUserOp.selector
            && _allowedSelector(vId, bytes4(userOp.callData[4:])),
        UnauthorizedCallData()
    );
    _setValidationHook(userOpHash, IHook($.vInfo[vId].hook));
}
```
When the attacker supplies `vType == VALIDATION_TYPE_ROOT`, the short-circuit takes the first branch:
- selector allowlist is never consulted — any inner calldata passes;
- `_setValidationHook` is never called, so `executeUserOp` later reads `_validationHook(userOpHash) == 0` and `_preHook(0, ...)` / `_postHook(0, ...)` in `src/core/HookManager.sol:31-43` become no-ops.

`ValidationManager._initializeValidation:94-96` will happily accept a real hook address during root installation (`internalData[0:20]`), and `kernel.validationInfo(rootVid).hook` faithfully stores it — it is just never invoked.

Introduced by PR #22 ("Hook Validation Logic Enhancement — Reordered conditional logic for gas optimization", commits `fa6a1bd`, `cdf738b`, per `CHANGELOG_AUDIT.md`).

### Fix
Resolve the effective vId (including root fallback) first, then always call `_setValidationHook(userOpHash, IHook($.vInfo[resolvedVid].hook))` regardless of whether the user typed `vType=ROOT` or `vType=VALIDATOR`.

---

## MEDIUM #5 — TimelockPolicy premature `Executed` during validation
`kernel-7579-plugins/src/policies/TimelockPolicy.sol:259` writes `proposal.status = ProposalStatus.Executed` during `checkUserOpPolicy`, i.e. in the ERC-4337 validation phase. EntryPoint v0.9 runs execution separately (`innerHandleOp` with caught execution reverts at `EntryPoint.sol:400-448`), so a failed execution leaves the `Executed` write in place.

Codex downgraded this from HIGH to LOW because EP v0.9 also consumes the AA nonce post-validation (`EntryPoint.sol:834`), so the exact same userOp could never have been retried anyway — the user can always pick a new `(callData, nonce)` pair. Kept at MEDIUM because (a) the "same key is dead forever" property still violates the user's "my proposal is either executed or it isn't" mental model and (b) a malicious callee / MEV front-run can reliably trigger it to grief timelock-gated emergency actions. Griefing is Medium under Immunefi.

---

## MEDIUM #6 — TimelockPolicy proposal data not signer-bound
`_handleProposalCreationInternal:196-235` reads `proposalCallData` and `proposalNonce` out of `permissionSig.signatures[timelockIndex]`. The signer only signs `userOpHash`, which does not cover `userOp.signature.permissionSig.signatures[*]`. A bundler or MITM can swap the policy slot to queue arbitrary proposal contents while leaving the signer's ECDSA signature intact.

Attack is griefing / nonce-burning unless the attacker can separately obtain signer authorization for the mutated execution — otherwise the attacker-queued proposal is unreachable. MEDIUM.

---

## LOW #7 — Codeless-address validator authorizes every userOp
PoC: `test/audit/EmptyValidator.t.sol` (both tests PASS). With a codeless validator installed, an attacker submits a userOp with a literal `0xdeadbeef...` signature and drains 1 ETH.

### Severity rationale
Rated **LOW** after consistent application of the precondition rule. The exploit requires the owner to sign an install of a module address that has no deployed code — a narrow admin misconfiguration rather than a normal flow, easily screened by wallet UIs and easily prevented by a one-line `extcodesize` check in `_installValidator`. EntryPoint v0.9 explicitly rejects short returndata at [EntryPoint.sol:616](../../dependencies/eth-infinitism-account-abstraction-0.9.0/contracts/core/EntryPoint.sol); Kernel does not. The missing returndata-length guard at `ValidationManager.sol:282-287` is still a real contract bug worth fixing — it remains LOW because the exploit path's root-signed-codeless-install precondition is narrow.

### Root cause
`src/core/ValidationManager.sol:282-287`:
```solidity
(bool success, bytes memory ret) =
    address(validator).call(abi.encodeCall(IValidator.validateUserOp, (op, opHash)));
validationData = success ? uint256(bytes32(ret)) : 1;
```
When `validator` has no deployed code (EOA / counterfactual CREATE2 / post-Cancun same-tx self-destruct / typo), the low-level `call` returns `success=true, ret=""`. Solidity 0.8.30 zero-pads `bytes32(bytes memory)` when shorter than 32 bytes, so `uint256(bytes32(empty))` evaluates to `0 = SIG_VALIDATION_SUCCESS_UINT`.

The install path compounds the issue: `ModuleManager._install:233` calls `module.call(onInstall, ...)` with a low-level `.call()`. An EOA / codeless address returns `success=true`, so `_installSuccess=true` and `_installValidator:102-107` accepts the install with no `extcodesize` check.

### Exploit flow
1. Owner is induced to sign an install with `module=X` where `X.code.length == 0` (counterfactual CREATE2, EOA typo, or a contract that self-destructed in the same tx).
2. Install succeeds silently — `vInfo[vId].hook = address(1)`.
3. Any attacker submits a userOp with nonce encoding `vType=VALIDATOR, vId=X` (or `vType=ROOT` if `X` is root) and any signature bytes.
4. `Kernel._validateUserOpValidator` calls `X.validateUserOp(op, hash)` via low-level `.call()`; codeless `X` returns `success=true, ret=""`; `validationData = 0 = SUCCESS`.
5. EntryPoint accepts the userOp, kernel executes the attacker's payload.

### Fix
```diff
- validationData = success ? uint256(bytes32(ret)) : 1;
+ if (!success || ret.length != 32) {
+     validationData = 1;
+ } else {
+     validationData = abi.decode(ret, (uint256));
+ }
```
Additionally, in `_installValidator` / `_installModule`: `require(module.code.length > 0, InvalidModule());`.

---

## LOW #8 — `_verifyStatelessSignature` PERMISSION branch pseudo-policy match
`src/core/ModuleManager.sol:337-357` iterates the root-signed `packages[]` and treats every package with `bytes4(pkg.internalData) == pId` as part of the permission's signature chain. Only the **last** matched package is forced to `moduleType == 6`. A type-3 (selector) or type-4 (hook) package whose `internalData[0:4]` equals a PermissionId is matched and invoked as a pseudo-policy via `IStatelessValidatorWithSender(pkg.module).validateSignatureWithDataWithSender(...)`.

If the attacker-chosen module returns `true` unconditionally, real policy restrictions get skipped. **Precondition**: the root must have signed an install list containing such a crafted package. That makes the severity LOW under Immunefi's precondition rule — same category as MEDIUM #3's codeless-validator signed-install requirement.

Gemini rated HIGH; codex rated LOW; this report agrees with codex. Averaging two model opinions is not a severity methodology — the precondition dominates.

**Fix**: `require(pkg.moduleType == 5 || (pkg.moduleType == 6 && isLast), BadModuleType());` inside the match.

---

## LOW #9 — Type-10 stateless validators ignore `sender`
`kernel-7579-plugins/src/validators/ECDSAValidator.sol:110-116` / `signers/ECDSASigner.sol:93-99` / `signers/WeightedECDSASigner.sol:141-149` all advertise `MODULE_TYPE_STATELESS_VALIDATOR_WITH_SENDER` (10) via `isModuleType`, but their `validateSignatureWithDataWithSender` implementations drop the `sender` argument. Type 10 effectively decays to type 7 — a documentation / interface guarantee is false. Downstream consumers that rely on per-sender binding are silently broken.

**Fix**: either remove the type-10 claim or fold `sender` into the authorized hash.

---

## LOW #10 — `_setRoot(ValidationId)` does not require target vId to be installed
`src/core/ValidationManager.sol:336-346` — `_setRoot(ValidationId)` only validates the vType and the non-zero invariant:

```solidity
function _setRoot(ValidationId vId) internal {
    ValidationType vType = getType(vId);
    require(
        vType == VALIDATION_TYPE_VALIDATOR || vType == VALIDATION_TYPE_PERMISSION
            || (_fallbackValidatorAvailable() && vType == VALIDATION_TYPE_FALLBACK),
        InvalidValidationType()
    );
    require(ValidationId.unwrap(vId) != bytes21(0) || _fallbackValidatorAvailable(), InvalidRootValidation());
    ValidationStorage storage $ = _validationStorage();
    $.root = vId;
}
```

It never checks `$.vInfo[vId].hook != 0`. A root-authorized caller can `setRoot(someVid)` where `someVid` was never initialized. Next `vType=ROOT` userOp hits `require(info.hook > address(0), InvalidVid(v))` at `ValidationManager.sol:200` and reverts.

**Severity LOW, not HIGH:** the caller must already be root-authorized to reach `setRoot(ValidationId)` (`_onlyEntryPointOrSelf`), so this is an admin footgun rather than a privilege escalation. `vType=VALIDATOR` and `vType=PERMISSION` paths through other installed validators still function after the brick — it is a DoS of the root path specifically, not a full brick. Recovery path: the owner submits a userOp under an installed non-root validator that's been granted `setRoot`, or re-installs the previously-intended root module so its `hook` becomes non-zero.

**Fix**: add `require($.vInfo[vId].hook != 0, NotInstalled());` at the end of `_setRoot(ValidationId)` — with a fallback-path exception when `vId == bytes21(0)` on `_fallbackValidatorAvailable()` kernels.

---

## Informational / Out of Scope

### INFO — Staker chain-agnostic approval replay (out of scope)
`src/Staker.sol:45-52` — `_hashTypedDataSansChainId` deliberately strips chainId; nonce is per-factory only. An owner approval signed for one chain is valid on every chain where the `Staker` lives at the same address. **`Staker.sol` is not listed in `SCOPE.md`'s enumerated in-scope contracts**, and the behavior is documented as "chain-agnostic by design". Recorded as informational; a clear UX foot-gun but not counted in the severity totals.

---

## Findings evaluated and rejected
- **Kernel7702 raw ERC-1271 "signature leak"** — rejected by both codex (explicit test-suite intent at `test/Kernel7702.t.sol:49`) and gemini. For 7702 the account *is* the EOA; accepting its raw ECDSA sig via `isValidSignature` is exact EOA-equivalence, not a scoping break.
- **Gemini's "TimelockPolicy executes when calldata != NoOp"** — misread; the non-NoOp branch requires a matching pre-existing Pending proposal.
- **Gemini's "executorHook bypass via self-call"** — `msg.sender` under a `delegatecall(address(this), ...)` is preserved as EntryPoint, not kernel.
- **Gemini's "permission chain intersect edge case"** — already fixed by PR #32.
- **WeightedECDSASigner EIP-712 domain lacks chainId** — false positive; Solady's EIP-712 domain includes `block.chainid` (`dependencies/solady-0.1.26/src/utils/EIP712.sol:71,139`).
- **Enable-mode install persisting on execution revert** — false positive; if final validationData is failure, EP reverts with `AA24`, unwinding the install.
- **`Kernel.installModule(bool replayable, ...)` being permissionless** — intentional meta-tx pattern; caller cannot widen the signed payload.
- **`_processUserOp` `missingAccountFunds` assembly oddity** (`callvalue()` as input/output pointers) — not reachable with non-zero callvalue on authorized paths.

---

## PoC run instructions

```bash
# Foundry via docker (the sandbox host's local forge binary has a GLIBC mismatch)
docker run --rm -u $(id -u):$(id -g) -v $PWD:/work -w /work ghcr.io/foundry-rs/foundry:latest \
  -c "forge test --match-path 'test/audit/*.t.sol' -vvv"
```

Expected tail:
```
[PASS] test_PoC_codeless_validator_authorizes_any_signature()
[PASS] test_PoC_install_codeless_validator_succeeds()
[PASS] test_PoC_side_validator_can_takeover_via_setRoot()
[PASS] test_PoC_side_validator_directly_calls_execute()
[PASS] test_PoC_root_hook_is_bypassed()
[PASS] test_PoC_grants_resurrect_after_uninstall_and_blank_reinstall()
[PASS] test_PoC_permission_selector_resurrects_on_signer_reinstall()
[PASS] test_PoC_phantom_session_key_validates_arbitrary_hashes()
[PASS] test_PoC_phantom_session_key_is_unlimited_use()
Ran 6 test suites: 9 tests passed, 0 failed, 0 skipped
```

---

## External-model provenance tags
Each finding carries who contributed the idea:
- `claude`: me, this session (direct reading of the contracts).
- `codex`: OpenAI Codex CLI, model `gpt-5.4`, `model_reasoning_effort=xhigh`.
- `gemini`: Google Gemini CLI, `gemini-3.1-pro-preview`.
- `code-reviewer`: the general-purpose code-reviewer sub-agent spawned via `Agent`.
- `user`: the user's instructions about scope and already-fixed PRs.

HIGH #1 was initially missed by claude and surfaced by the code-reviewer; codex later confirmed it. All remaining findings were independently confirmed by at least two of {claude, codex, gemini, code-reviewer}.
