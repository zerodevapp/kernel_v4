// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    EXECUTOR_MANAGER_STORAGE_SLOT,
    HOOK_MODULE_NOT_INSTALLED,
    HOOK_MODULE_INSTALLED_NO_HOOK
} from "../types/Constants.sol";
import {IExecutor, IHook} from "../interfaces/IERC7579Modules.sol";
import {ExecutorStorage, ExecutorConfig} from "../types/Structs.sol";
import {NotExecutor, NotInstalled} from "../types/Error.sol";

abstract contract ExecutorManager {
    function _hookEnabled(IHook _hook) internal view virtual returns (bool);

    function _executorStorage() internal pure returns (ExecutorStorage storage $) {
        assembly {
            $.slot := EXECUTOR_MANAGER_STORAGE_SLOT
        }
    }

    function executorConfig(address executor) external view returns (ExecutorConfig memory) {
        return _executorConfig(IExecutor(executor));
    }

    function _executorConfig(IExecutor executor) internal view returns (ExecutorConfig storage config) {
        config = _executorStorage().executorConfig[executor];
    }

    function _installExecutor(address _executor, bytes calldata _internalData, bool) internal {
        // NOTE: we don't care if install was successful
        address hook = _internalData.length >= 20 ? address(bytes20(_internalData[0:20])) : HOOK_MODULE_NOT_INSTALLED;
        if (hook == HOOK_MODULE_NOT_INSTALLED) {
            hook = HOOK_MODULE_INSTALLED_NO_HOOK; // address(1) indicates it is installed and does not require any hook
        } else {
            require(hook == HOOK_MODULE_INSTALLED_NO_HOOK || _hookEnabled(IHook(hook)), NotInstalled());
        }
        _executorConfig(IExecutor(_executor)).hook = IHook(hook);
    }

    function _uninstallExecutor(address _executor, bytes calldata, bool) internal {
        _executorConfig(IExecutor(_executor)).hook = IHook(HOOK_MODULE_NOT_INSTALLED);
    }
}
