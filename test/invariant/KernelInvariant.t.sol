pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Kernel} from "src/Kernel.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {KernelImmutableECDSA} from "src/KernelImmutableECDSA.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {Install, SelectorConfig, ValidationInfo} from "src/types/Structs.sol";
import {ValidationId, CallType, PermissionId} from "src/types/Types.sol";
import {validatorToIdentifier, permissionToIdentifier} from "src/lib/Utils.sol";
import {CALLTYPE_DELEGATECALL, CALLTYPE_SINGLE} from "src/types/Constants.sol";
import {EntryPointLib} from "../utils/EntryPointLib.sol";
import {MockValidator} from "../mock/MockValidator.sol";
import {MockExecutor} from "../mock/MockExecutor.sol";
import {MockHook} from "../mock/MockHook.sol";
import {MockFallback} from "../mock/MockFallback.sol";
import {MockPolicy} from "../mock/MockPolicy.sol";
import {MockSigner} from "../mock/MockSigner.sol";

contract KernelInvariantHandler is Test {
    Kernel public immutable kernel;
    IEntryPoint public immutable ep;
    MockValidator public immutable rootValidator;

    MockValidator[] public validators;
    MockExecutor[] public executors;
    MockHook[] public hooks;
    MockFallback[] public fallbacks;
    MockPolicy[] public policies;
    MockSigner[] public signers;
    bytes4[] public selectors;
    address[] public policyStack;

    mapping(address => bool) public validatorInstalled;
    mapping(address => bool) public executorInstalled;
    mapping(address => bool) public hookInstalled;
    mapping(bytes4 => address) public selectorTarget;
    mapping(bytes4 => bytes1) public selectorCallType;
    mapping(address => bool) public policyInstalled;
    address public signerInstalled;
    bytes4 public permissionId;

    constructor(Kernel kernel_, IEntryPoint ep_, MockValidator rootValidator_) {
        kernel = kernel_;
        ep = ep_;
        rootValidator = rootValidator_;

        validatorInstalled[address(rootValidator_)] = true;

        for (uint256 i = 0; i < 3; i++) {
            validators.push(new MockValidator());
        }
        for (uint256 i = 0; i < 2; i++) {
            executors.push(new MockExecutor());
            hooks.push(new MockHook());
            fallbacks.push(new MockFallback());
            policies.push(new MockPolicy());
            signers.push(new MockSigner());
        }

        selectors.push(MockFallback.fallbackFunction.selector);
        selectors.push(MockFallback.forceRevert.selector);
        selectors.push(MockFallback.testFunction.selector);

        permissionId = bytes4(keccak256("permission"));
    }

    function installValidator(uint256 index) external {
        MockValidator validator = validators[index % validators.length];
        vm.startPrank(address(ep));
        kernel.installModule(1, address(validator), abi.encode(hex"deadbeef", hex""));
        vm.stopPrank();
        validatorInstalled[address(validator)] = true;
    }

    function uninstallValidator(uint256 index) external {
        MockValidator validator = validators[index % validators.length];
        if (address(validator) == address(rootValidator)) {
            return;
        }
        vm.startPrank(address(ep));
        kernel.uninstallModule(1, address(validator), abi.encode(hex"", hex""));
        vm.stopPrank();
        validatorInstalled[address(validator)] = false;
    }

    function installExecutor(uint256 index) external {
        MockExecutor executor = executors[index % executors.length];
        vm.startPrank(address(ep));
        kernel.installModule(2, address(executor), abi.encode(hex"deadbeef", hex""));
        vm.stopPrank();
        executorInstalled[address(executor)] = true;
    }

    function uninstallExecutor(uint256 index) external {
        MockExecutor executor = executors[index % executors.length];
        vm.startPrank(address(ep));
        kernel.uninstallModule(2, address(executor), abi.encode(hex"", hex""));
        vm.stopPrank();
        executorInstalled[address(executor)] = false;
    }

    function installHook(uint256 index) external {
        MockHook hook = hooks[index % hooks.length];
        vm.startPrank(address(ep));
        kernel.installModule(4, address(hook), abi.encode(hex"", hex""));
        vm.stopPrank();
        hookInstalled[address(hook)] = true;
    }

    function uninstallHook(uint256 index) external {
        MockHook hook = hooks[index % hooks.length];
        vm.startPrank(address(ep));
        kernel.uninstallModule(4, address(hook), abi.encode(hex"", hex""));
        vm.stopPrank();
        hookInstalled[address(hook)] = false;
    }

    function validatorCount() external view returns (uint256) {
        return validators.length;
    }

    function executorCount() external view returns (uint256) {
        return executors.length;
    }

    function hookCount() external view returns (uint256) {
        return hooks.length;
    }

    function fallbackCount() external view returns (uint256) {
        return fallbacks.length;
    }

    function selectorCount() external view returns (uint256) {
        return selectors.length;
    }

    function policyCount() external view returns (uint256) {
        return policies.length;
    }

    function signerCount() external view returns (uint256) {
        return signers.length;
    }

    function policyStackCount() external view returns (uint256) {
        return policyStack.length;
    }

    function installSelector(uint256 selectorIndex, uint256 targetIndex, bool delegatecall) external {
        bytes4 selector = selectors[selectorIndex % selectors.length];
        MockFallback target = fallbacks[targetIndex % fallbacks.length];
        bytes1 callType = delegatecall ? CallType.unwrap(CALLTYPE_DELEGATECALL) : CallType.unwrap(CALLTYPE_SINGLE);
        bytes memory internalData = abi.encodePacked(selector, callType, address(0));
        vm.startPrank(address(ep));
        kernel.installModule(3, address(target), abi.encode(hex"deadbeef", internalData));
        vm.stopPrank();
        selectorTarget[selector] = address(target);
        selectorCallType[selector] = callType;
    }

    function uninstallSelector(uint256 selectorIndex) external {
        bytes4 selector = selectors[selectorIndex % selectors.length];
        address target = selectorTarget[selector];
        if (target == address(0)) {
            target = address(fallbacks[0]);
        }
        vm.startPrank(address(ep));
        kernel.uninstallModule(3, target, abi.encode(hex"", abi.encodePacked(selector)));
        vm.stopPrank();
        selectorTarget[selector] = address(0);
        selectorCallType[selector] = bytes1(0);
    }

    function installPolicy(uint256 index) external {
        MockPolicy policy = policies[index % policies.length];
        if (policyInstalled[address(policy)]) {
            return;
        }
        vm.startPrank(address(ep));
        kernel.installModule(5, address(policy), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));
        vm.stopPrank();
        policyInstalled[address(policy)] = true;
        policyStack.push(address(policy));
    }

    function uninstallPolicy() external {
        uint256 len = policyStack.length;
        if (len == 0) {
            return;
        }
        address policy = policyStack[len - 1];
        vm.startPrank(address(ep));
        kernel.uninstallModule(5, policy, abi.encode(hex"", abi.encodePacked(permissionId)));
        vm.stopPrank();
        policyInstalled[policy] = false;
        policyStack.pop();
    }

    function installSigner(uint256 index) external {
        MockSigner signer = signers[index % signers.length];
        vm.startPrank(address(ep));
        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));
        vm.stopPrank();
        signerInstalled = address(signer);
    }

    function uninstallSigner() external {
        if (signerInstalled == address(0) || policyStack.length != 0) {
            return;
        }
        address signer = signerInstalled;
        vm.startPrank(address(ep));
        kernel.uninstallModule(6, signer, abi.encode(hex"", abi.encodePacked(permissionId)));
        vm.stopPrank();
        signerInstalled = address(0);
    }
}

contract KernelInvariant is StdInvariant, Test {
    Kernel private kernel;
    IEntryPoint private ep;
    MockValidator private rootValidator;
    KernelInvariantHandler private handler;

    function setUp() external {
        ep = EntryPointLib.deploy();

        KernelUUPS uups = new KernelUUPS(ep);
        KernelImmutableECDSA immutableEcdsa = new KernelImmutableECDSA(ep);
        KernelFactory factory = new KernelFactory(uups, immutableEcdsa);

        rootValidator = new MockValidator();
        Install[] memory pkgs = new Install[](1);
        pkgs[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});
        kernel = factory.deploy(pkgs, 0);

        handler = new KernelInvariantHandler(kernel, ep, rootValidator);
        targetContract(address(handler));
    }

    function invariant_root_is_installed() external {
        assertEq(ValidationId.unwrap(kernel.root()), ValidationId.unwrap(validatorToIdentifier(rootValidator)));
        assertTrue(kernel.isModuleInstalled(1, address(rootValidator), hex""));
    }

    function invariant_validator_install_state_matches_handler() external {
        uint256 count = handler.validatorCount();
        for (uint256 i = 0; i < count; i++) {
            address validator = address(handler.validators(i));
            assertEq(
                kernel.isModuleInstalled(1, validator, hex""),
                handler.validatorInstalled(validator),
                "validator install state mismatch"
            );
            if (validator != address(rootValidator)) {
                ValidationId vId = validatorToIdentifier(MockValidator(validator));
                bool installed = handler.validatorInstalled(validator);
                assertEq(kernel.validationInfo(vId).hook != address(0), installed, "validator hook mismatch");
            }
        }
    }

    function invariant_executor_install_state_matches_handler() external {
        uint256 count = handler.executorCount();
        for (uint256 i = 0; i < count; i++) {
            address executor = address(handler.executors(i));
            assertEq(
                kernel.isModuleInstalled(2, executor, hex""),
                handler.executorInstalled(executor),
                "executor install state mismatch"
            );
            bool installed = handler.executorInstalled(executor);
            assertEq(address(kernel.executorConfig(executor).hook) != address(0), installed, "executor hook mismatch");
        }
    }

    function invariant_hook_install_state_matches_handler() external {
        uint256 count = handler.hookCount();
        for (uint256 i = 0; i < count; i++) {
            address hook = address(handler.hooks(i));
            assertEq(
                kernel.isModuleInstalled(4, hook, hex""), handler.hookInstalled(hook), "hook install state mismatch"
            );
        }
    }

    function invariant_selector_state_matches_handler() external {
        uint256 count = handler.selectorCount();
        for (uint256 i = 0; i < count; i++) {
            bytes4 selector = handler.selectors(i);
            address target = handler.selectorTarget(selector);
            bytes1 callType = handler.selectorCallType(selector);
            bool installed = target != address(0);
            if (installed) {
                assertTrue(
                    kernel.isModuleInstalled(3, target, abi.encodePacked(selector)), "selector installed mismatch"
                );
            } else {
                assertFalse(
                    kernel.isModuleInstalled(3, address(0xdead), abi.encodePacked(selector)),
                    "selector should be uninstalled"
                );
            }
            SelectorConfig memory cfg = kernel.selectorConfig(selector);
            assertEq(cfg.target, target, "selector target mismatch");
            assertEq(CallType.unwrap(cfg.callType), callType, "selector callType mismatch");
        }
    }

    function invariant_permission_state_matches_handler() external {
        PermissionId permId = PermissionId.wrap(handler.permissionId());
        ValidationId vId = permissionToIdentifier(permId);
        ValidationInfo memory vInfo = kernel.validationInfo(vId);
        assertEq(vInfo.policies.length, handler.policyStackCount(), "policy length mismatch");
        for (uint256 i = 0; i < handler.policyStackCount(); i++) {
            address policy = handler.policyStack(i);
            assertTrue(kernel.isModuleInstalled(5, policy, abi.encodePacked(handler.permissionId())));
            assertTrue(handler.policyInstalled(policy));
        }
        address signer = handler.signerInstalled();
        assertEq(vInfo.signer, signer, "signer mismatch");
        if (signer != address(0)) {
            assertTrue(kernel.isModuleInstalled(6, signer, abi.encodePacked(handler.permissionId())));
        }
    }
}
