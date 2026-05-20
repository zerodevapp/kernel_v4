/* SPDX-License-Identifier: MIT */

/**
 * Kernel v4 — Property #1: executeUserOp ↔ validateUserOp linkage
 *
 * SECURITY claim from src/Kernel.sol (executeUserOp comment):
 *   The safety of the inner delegatecall to address(this) rests entirely on
 *   validateUserOp having approved the outer UserOp under a validation that
 *   owns the inner selector.
 *
 * This file holds the rules and invariants that pin that claim down. Each
 * rule should be one focused property. Add multiple — Certora can verify
 * them in parallel.
 *
 * STATUS: scaffold. The harness + storage linkage is not yet wired.
 *         sc-fv-certora will author the actual rule(s).
 */

methods {
    // View / pure methods that don't need an env. Add as needed.
    // function entryPoint() external returns (address) envfree;
}

/// @title Placeholder — replace with the real rule once sc-fv-certora is dispatched
rule scaffoldPlaceholder() {
    assert true;
}
