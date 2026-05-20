# Certora — Kernel v4

Formal verification harness for properties that need multi-step traces or unbounded-array quantification (out of Halmos's reach).

## Layout

```
certora/
├── conf/        # certoraRun config (JSON)
├── specs/       # CVL rules + invariants
└── harnesses/   # Solidity wrappers when storage/inheritance tricks are needed
```

## Running

```bash
# 1) Activate the venv (certora-cli is installed there)
source ~/.certora-venv/bin/activate

# 2) Export the API key. Certora expects CERTORAKEY (no underscore); this
#    repo's machine has it under CERTORA_KEY — alias before running.
export CERTORAKEY="$CERTORA_KEY"

# 3) Verify Java 21+ is on PATH (Temurin recommended)
java --version

# 4) Run from repo root
certoraRun certora/conf/Kernel.conf
```

The run uploads to Certora cloud and prints a job URL. Open it for the report.

## Property #1 — executeUserOp ↔ validateUserOp linkage

`conf/Kernel.conf` is wired for property #1 from `audit/fv-gap-audit.md`:

> `executeUserOp`'s inner delegatecall to `address(this)` cannot execute any
> privileged kernel function unless `validateUserOp` already authorised the
> outer UserOp under a validation that owns the inner selector.

### Results (FV Round 1, Phase C)

| Rule | Status | Notes |
|---|---|---|
| `validateUserOpEnforcesInnerSelectorAccess_naive` | **FAIL** | CEX surfaces the fast-path bypass implementation finding |
| `validateUserOpEnforcesInnerSelectorAccess_strict` | **PASS** | Property holds when the fast-path is explicitly excluded |
| `sanityValidateUserOpReachesSuccess` | **PASS** (satisfy) | Confirms the rule setup is not vacuous |

Last verified job: `d52ccad8f4964f21b2e025a64b9292d3` (~7.5 min prover time, 8.13.1).

### Implementation finding (from the naive CEX)

The fast-path branch in `_processUserOp` (Kernel.sol lines 172-176) bypasses the
inner-selector `require` when ALL of the following hold:

- `vType != ROOT`,
- `_allowedSelector(vId, outerSel)` is true with `outerSel == executeUserOp.selector`,
- `vInfo[vId].hook == HOOK_MODULE_INSTALLED_NO_HOOK`.

When this happens, `_setValidationHook` is never called, the transient hook
stays at 0, and `executeUserOp`'s inner delegatecall runs with NO selector
check — handing the validation the equivalent of root privileges.

The fast-path's design intent (per its inline comment) assumes the outer call
is the actual inner function. Granting a non-ROOT validation access to
`executeUserOp.selector` itself violates that assumption. The contract does
not enforce the assumption: `_grantAccess` accepts any selector list,
including `executeUserOp.selector`.

Suggested remediations (pick one):
1. In `_grantAccess`, reject `executeUserOp.selector`:
   `require(selector != this.executeUserOp.selector || vId == $.root, …)`.
2. In `_processUserOp`'s fast-path predicate, also require
   `outerSel != executeUserOp.selector` so a userOp wrapping executeUserOp
   always routes through the inner-selector require.

## Pitfalls baked in

- `optimistic_loop: true` + `loop_iter: 3`.
- `optimistic_hashing: true` + `hashing_length_bound: 512` — required because
  `_verifyInstallSignatureRaw` and `Lib4337.chainAgnosticUserOpHash` hash
  unbounded bytes.
- `solc_via_ir: false` — matches the project's `foundry.toml` (contract-size
  constraint).
- Internal summaries (`_validateUserOpValidator/Permission/Fallback`,
  `_verifyInstallSignatureRaw`, `Lib4337.chainAgnosticUserOpHash`,
  `Lib4337.intersectValidationData`) are NONDET — without them Certora OOMs
  on the full validateUserOp TAC graph (60GB+ memory).
- Rules constrain `vMode` bits 0x08 (enable mode) and 0x40 (replayable). The
  fast-path bypass is independent of those, so the finding stands.
- Remappings duplicate the project's `remappings.txt` via the `packages` array.
- Soldeer is used for deps — paths under `dependencies/`.

## Files

- `conf/Kernel.conf` — verifyer config (verifies `KernelHarness`).
- `specs/Kernel.spec` — CVL rules.
- `harnesses/KernelHarness.sol` — read-only accessors over namespaced storage
  and pure helpers; extends `KernelUUPS`. Does not modify production logic.
