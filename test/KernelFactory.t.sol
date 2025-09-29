pragma solidity ^0.8.0;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {EntryPointLib} from "./utils/EntryPointLib.sol";
import {Lib4337} from "src/lib/Lib4337.sol";
import {Kernel} from "src/Kernel.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {KernelHelper} from "src/KernelHelper.sol";
import {KernelFactory} from "src/KernelFactory.sol";
import {KernelUUPS} from "src/KernelUUPS.sol";
import {KernelImmutableECDSA} from "src/KernelImmutableECDSA.sol";
import {Install, ValidationInfo} from "src/types/Structs.sol";
import {VALIDATION_TYPE_VALIDATOR} from "src/types/Constants.sol";
import {ValidationId} from "src/types/Types.sol";
import {MockFallback} from "./mock/MockFallback.sol";
import {MockValidator} from "./mock/MockValidator.sol";
import {MockPolicy} from "./mock/MockPolicy.sol";
import {MockSigner} from "./mock/MockSigner.sol";
import {MockCallee} from "./mock/MockCallee.sol";
import {InvalidRootValidation} from "src/types/Error.sol";
import {KernelTestBase} from "./KernelTestBase.sol";

contract KernelFactoryTest is KernelTestBase {
    address owner;
    uint256 ownerKey;

    function setUp() external {
        ep = EntryPointLib.deploy();

        KernelUUPS uups = new KernelUUPS(ep);
        KernelImmutableECDSA immutableEcdsa = new KernelImmutableECDSA(ep);
        factory = new KernelFactory(uups, immutableEcdsa);
        helper = new KernelHelper();
        newValidator = new MockValidator();
        callee = new MockCallee();
        executor = makeAddr("Executor");
        mockFallback = new MockFallback();
        beneficiary = payable(makeAddr("Beneficiary"));
        policy = new MockPolicy();
        permissionId = bytes20(keccak256(abi.encodePacked("Hello world")));
        vm.txGasPrice(1);
        _initialize();
    }

    function _initialize() internal virtual override {
        (owner, ownerKey) = makeAddrAndKey("Owner");
        rootValidator = new MockValidator();
        rootValidatorData = hex"";
        Install[] memory pkgs = new Install[](1);
        pkgs[0] = Install({moduleType: 1, module: address(rootValidator), moduleData: hex"", internalData: hex""});
        kernel = factory.deploy(pkgs, 0);
        vm.deal(address(kernel), 1e18);

        vm.startPrank(address(ep));
        kernel.installModule(2, executor, abi.encode(hex"", ""));
        vm.stopPrank();
    }

    function test_deploy_root_validator() external unitTest {
        Install[] memory pkgs = new Install[](1);
        pkgs[0] =
            Install({moduleType: 1, module: address(rootValidator), moduleData: rootValidatorData, internalData: hex""});
        vm.startSnapshotGas("Mock - deploy()");
        Kernel k = factory.deploy(pkgs, 1);
        vm.stopSnapshotGas();
    }

    function test_deploy_root_permission() external unitTest {
        Install[] memory pkgs = new Install[](2);
        pkgs[0] = Install({
            moduleType: 5,
            module: address(policy),
            internalData: abi.encodePacked(permissionId),
            moduleData: hex""
        });
        pkgs[1] = Install({moduleType: 1, module: address(newValidator), internalData: hex"", moduleData: hex""});
        Kernel k = factory.deploy(pkgs, 1);
        assertEq(k.accountId(), "kernel.v0.4");
        assertEq(k.registry(), address(0));
    }

    function test_deploy_root_fail_invalid_root() external unitTest {
        Install[] memory pkgs = new Install[](2);
        pkgs[0] = Install({moduleType: 2, module: address(executor), internalData: hex"", moduleData: hex""});
        pkgs[1] = Install({moduleType: 1, module: address(newValidator), internalData: hex"", moduleData: hex""});
        vm.expectRevert(InvalidRootValidation.selector);
        Kernel k = factory.deploy(pkgs, 1);
    }

    function test_deploy_existing() external {
        Install[] memory pkgs = new Install[](1);
        pkgs[0] =
            Install({moduleType: 1, module: address(rootValidator), moduleData: rootValidatorData, internalData: hex""});
        Kernel k = factory.deploy(pkgs, 1);
        assertEq(address(k), address(factory.deploy(pkgs, 1)));
    }

    function test_deploy_with_call() external unitTest {
        Install[] memory initPkgs = new Install[](1);
        initPkgs[0] =
            Install({moduleType: 1, module: address(rootValidator), moduleData: rootValidatorData, internalData: hex""});
        Install[] memory pkgs = new Install[](1);
        pkgs[0] = Install({moduleType: 1, module: address(newValidator), moduleData: hex"", internalData: hex""});
        kernel = Kernel(payable(factory.getAddress(initPkgs, 1)));
        bytes memory sig = enableSig(0, true, false, pkgs, _rootSignHash);
        Kernel k = factory.deployWithCall(initPkgs, 1, abi.encodeWithSelector(0xa706cd33, false, 0, pkgs, sig));
        assertEq(address(k), address(kernel));
        ValidationInfo memory vInfo = k.validationInfo(ValidationId.wrap(bytes20(address(newValidator))));
        assertTrue(vInfo.vType == VALIDATION_TYPE_VALIDATOR);
    }

    function test_deploy_with_call_existing() external unitTest {
        Install[] memory initPkgs = new Install[](1);
        initPkgs[0] =
            Install({moduleType: 1, module: address(rootValidator), moduleData: rootValidatorData, internalData: hex""});
        factory.deploy(initPkgs, 1);
        Install[] memory pkgs = new Install[](1);
        pkgs[0] = Install({moduleType: 1, module: address(newValidator), moduleData: hex"", internalData: hex""});
        kernel = Kernel(payable(factory.getAddress(initPkgs, 1)));
        bytes memory sig = enableSig(0, true, false, pkgs, _rootSignHash);
        Kernel k = factory.deployWithCall(initPkgs, 1, abi.encodeWithSelector(0xa706cd33, false, 0, pkgs, sig));
        assertEq(address(k), address(kernel));
        ValidationInfo memory vInfo = k.validationInfo(ValidationId.wrap(bytes20(address(newValidator))));
        assertTrue(vInfo.vType == VALIDATION_TYPE_VALIDATOR);
    }

    function _ecdsaSignUserOp(PackedUserOperation memory op, bool success, bool replay)
        internal
        returns (bytes memory sig)
    {
        bytes32 hash = replay ? Lib4337.chainAgnosticUserOpHash(address(ep), op) : ep.getUserOpHash(op);
        return _ecdsaRootSignHash(hash, success);
    }

    function _ecdsaRootSignHash(bytes32 hash, bool success) internal returns (bytes memory sig) {
        if (!success) {
            hash = keccak256(abi.encodePacked(hash));
        }
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function test_deploy_ecdsa() external {
        Install[] memory pkgs = new Install[](0);
        Kernel k = factory.deployECDSA(owner, pkgs, 1);
        assertEq(address(k), address(factory.getECDSAAddress(owner, pkgs, 1)));
    }

    function test_deploy_ecdsa_msg_value() external {
        Install[] memory pkgs = new Install[](0);
        Kernel k = factory.deployECDSA{value: 1}(owner, pkgs, 1);
        assertEq(address(k), address(factory.getECDSAAddress(owner, pkgs, 1)));
        assertEq(address(k).balance, 1);
    }

    function test_deploy_ecdsa_with_call() external unitTest {
        Install[] memory initPkgs = new Install[](0);

        Install[] memory pkgs = new Install[](1);
        pkgs[0] = Install({moduleType: 1, module: address(newValidator), moduleData: hex"", internalData: hex""});
        kernel = Kernel(payable(factory.getECDSAAddress(owner, initPkgs, 1)));
        bytes memory sig = enableSig(0, true, false, pkgs, _ecdsaRootSignHash);

        Kernel k =
            factory.deployECDSAWithCall(owner, initPkgs, 1, abi.encodeWithSelector(0xa706cd33, false, 0, pkgs, sig));
        assertEq(address(k), address(kernel));
        ValidationInfo memory vInfo = k.validationInfo(ValidationId.wrap(bytes20(address(newValidator))));
        assertTrue(vInfo.vType == VALIDATION_TYPE_VALIDATOR);
    }

    function test_deploy_ecdsa_with_call_existing() external unitTest {
        Install[] memory initPkgs = new Install[](0);
        factory.deployECDSA(owner, initPkgs, 1);

        Install[] memory pkgs = new Install[](1);
        pkgs[0] = Install({moduleType: 1, module: address(newValidator), moduleData: hex"", internalData: hex""});
        kernel = Kernel(payable(factory.getECDSAAddress(owner, initPkgs, 1)));
        bytes memory sig = enableSig(0, true, false, pkgs, _ecdsaRootSignHash);

        Kernel k =
            factory.deployECDSAWithCall(owner, initPkgs, 1, abi.encodeWithSelector(0xa706cd33, false, 0, pkgs, sig));
        assertEq(address(k), address(kernel));
        ValidationInfo memory vInfo = k.validationInfo(ValidationId.wrap(bytes20(address(newValidator))));
        assertTrue(vInfo.vType == VALIDATION_TYPE_VALIDATOR);
    }
}
