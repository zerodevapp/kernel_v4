pragma solidity ^0.8.0;

import {KernelTestBase} from "./KernelTestBase.sol";

abstract contract KernelHookTest is KernelTestBase {
    function test_install_hook() external unitTest {
        assertTrue(kernel.supportsModule(4));
        kernel.installModule(4, address(mockHook), abi.encode(hex"", ""));
        assertTrue(kernel.isModuleInstalled(4, address(mockHook), hex""));
        assertTrue(kernel.globalHook() == address(mockHook));
    }

    function test_uninstall_hook() external unitTest {
        kernel.installModule(4, address(mockHook), abi.encode(hex"", ""));
        kernel.uninstallModule(4, address(mockHook), abi.encode(hex"", ""));
    }

    function test_global_hook_validate_user_op() external unitTest {
        kernel.installModule(4, address(mockHook), abi.encode(hex"", ""));
        assertTrue(kernel.globalHook() == address(mockHook));

        _sendUserOpValidator(true, true);
    }

    function test_global_hook_execute() external unitTest {
    }

    function test_global_hook_execute_from_executor() external unitTest {
    }

    function test_global_hook_selector() external unitTest {
    }

    function test_hook_validate_user_op() external unitTest {
    }

    function test_hook_execute() external unitTest {
    }

    function test_hook_execute_from_executor() external unitTest {
    }

    function test_hook_selector() external unitTest {
    }

    function test_hook_with_global_hook_validate_user_op() external unitTest {
    }

    function test_hook_with_global_hook_execute() external unitTest {
    }

    function test_hook_with_global_hook_execute_from_executor() external unitTest {
    }

    function test_hook_with_global_hook_selector() external unitTest {
    }    
}
