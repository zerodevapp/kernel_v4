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

## First property

`conf/Kernel.conf` is wired for property #1 from `audit/fv-gap-audit.md`:

> `executeUserOp`'s inner delegatecall to `address(this)` cannot execute any
> privileged kernel function unless `validateUserOp` already authorised the
> outer UserOp under a validation that owns the inner selector.

The current `specs/Kernel.spec` is a scaffold placeholder. `sc-fv-certora`
will be dispatched to author the actual rule (multi-step trace through
transient storage + `_allowedSelector`).

## Pitfalls baked in

- `optimistic_loop: true` + `loop_iter: 3` — start low. Raise only on counterexample.
- `solc_via_ir: false` — matches the project's `foundry.toml` (contract-size constraint).
- Remappings duplicate the project's `remappings.txt` via the `packages` array.
- Soldeer is used for deps — paths under `dependencies/`.
