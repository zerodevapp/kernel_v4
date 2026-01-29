# Branching Tree Technique (BTT) Test Suite

This directory contains tests following the **Branching Tree Technique (BTT)**, a structured approach to test case design that ensures comprehensive coverage of all possible scenarios and edge cases.

## What is BTT?

BTT organizes test cases in a tree-like structure where:
- **Branches** represent different conditions or states
- **Leaves** represent specific test cases or assertions

### Keywords

| Keyword | Purpose | Example |
|---------|---------|---------|
| `given` | Contract state conditions (setup) | `given the validator is installed` |
| `when` | Function parameters, execution modes | `when the caller is not the EntryPoint` |
| `it` | Test assertions/expected behaviors | `it should revert with Unauthorized error` |

## Directory Structure

```
test/btt/
├── README.md                           # This file
├── *.tree                              # BTT specification files
├── *.t.sol                             # BTT test implementations
├── KernelBTT.t.sol                     # Abstract base combining all BTT tests
└── KernelBTTConcrete.t.sol             # Concrete test implementation
```

## Tree Files

Each function has a corresponding `.tree` file that specifies the complete branching structure:

| File | Function Tested |
|------|-----------------|
| `Kernel.validateUserOp.tree` | `validateUserOp()` |
| `Kernel.executeUserOp.tree` | `executeUserOp()` |
| `Kernel.execute.tree` | `execute()` |
| `Kernel.executeFromExecutor.tree` | `executeFromExecutor()` |
| `Kernel.installModule.tree` | `installModule()` |
| `Kernel.uninstallModule.tree` | `uninstallModule()` |
| `Kernel.isValidSignature.tree` | `isValidSignature()` |
| `Kernel.setRoot.tree` | `setRoot()` |
| `Kernel.fallback.tree` | `fallback()` |
| `Kernel.initialize.tree` | `initialize()` |
| `Kernel.supportsExecutionMode.tree` | `supportsExecutionMode()` / `supportsModule()` |
| `Kernel.nonce.tree` | `setNonce()` / nonce encoding |
| `Kernel.installModuleWithSignature.tree` | `installModule()` with signature |
| `KernelFactory.deploy.tree` | Factory deployment functions |
| `Staker.tree` | Staker contract functions |

## Naming Conventions

### Modifiers
- `whenXxx()` - Modifiers for "when" conditions
- `givenXxx()` - Modifiers for "given" state conditions

### Test Functions
- `test_WhenXxx()` - Test for successful path
- `test_RevertWhen_Xxx()` - Test for expected revert
- `test_WhenXxx_Description()` - Test with additional context

## Running Tests

```bash
# Run all BTT tests
forge test --match-path "test/btt/*.t.sol"

# Run specific BTT test file
forge test --match-path "test/btt/KernelBTTConcrete.t.sol"

# Run with verbosity
forge test --match-path "test/btt/*.t.sol" -vvv

# Run specific test function
forge test --match-test "test_WhenRootSignatureIsValid" -vvv
```

## Using Bulloak (Optional)

[Bulloak](https://github.com/alexfertel/bulloak) can scaffold Solidity tests from `.tree` files:

```bash
# Install bulloak
cargo install bulloak

# Generate tests from tree file
bulloak scaffold Kernel.validateUserOp.tree

# Check if tests match specification
bulloak check Kernel.validateUserOp.tree

# Auto-fix missing tests
bulloak check --fix Kernel.validateUserOp.tree
```

## Example Tree Structure

```
Kernel_validateUserOp
├── when the caller is not the EntryPoint
│   └── when the caller is not the account itself
│       └── it should revert with Unauthorized error.
├── when the caller is the EntryPoint or self
│   ├── given the validation type is ROOT (0x00)
│   │   ├── when the signature is valid
│   │   │   └── it should return 0 (success).
│   │   └── when the signature is invalid
│   │       └── it should return SIG_VALIDATION_FAILED (1).
│   └── given the validation type is VALIDATOR (0x01)
│       ├── given the validator is not installed
│       │   └── it should revert with InvalidValidator error.
│       └── given the validator is installed
│           └── ...
```

## Example Test Implementation

```solidity
abstract contract Kernel_validateUserOp_Test is KernelTestBase {
    // Modifiers map to tree branches
    modifier whenCallerIsNotEntryPoint() {
        vm.stopPrank();
        vm.startPrank(makeAddr("randomCaller"));
        _;
    }

    modifier givenValidationTypeIsRoot() {
        _;
    }

    // Tests map to leaves
    /// @notice it should revert with Unauthorized error
    function test_RevertWhen_CallerIsNotEntryPointAndNotSelf()
        external
        unitTest
        whenCallerIsNotEntryPoint
    {
        PackedUserOperation memory op = _createBasicUserOp();
        bytes32 userOpHash = ep.getUserOpHash(op);

        vm.expectRevert(Unauthorized.selector);
        kernel.validateUserOp(op, userOpHash, 0);
    }
}
```

## Benefits of BTT

1. **Comprehensive Coverage** - Forces consideration of all code paths
2. **Clear Documentation** - Tree files serve as readable specifications
3. **Structured Approach** - Systematic test organization
4. **Auditor-Friendly** - Easy to verify test completeness
5. **Maintainable** - Clear mapping between spec and implementation

## References

- [BTT Examples by Paul R. Berg](https://github.com/PaulRBerg/btt-examples)
- [Bulloak Tool](https://github.com/alexfertel/bulloak)
- [Sablier BTT Best Practices](https://github.com/sablier-labs/lockup/discussions/647)
