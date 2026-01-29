// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {KernelTestBase} from "../KernelTestBase.sol";

/// @title BTT Shared Modifiers
/// @notice Common modifiers used across BTT test contracts
/// @dev Inherit from this contract instead of defining modifiers in each BTT test
abstract contract BTTModifiers is KernelTestBase {
    /*//////////////////////////////////////////////////////////////
                        CALLER MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sets caller to a random address (not EntryPoint)
    modifier whenCallerIsNotEntryPoint() virtual {
        vm.stopPrank();
        vm.startPrank(makeAddr("randomCaller"));
        _;
    }

    /// @dev Empty modifier - used for documentation/tree structure
    modifier whenCallerIsNotAccountItself() virtual {
        _;
    }

    /// @dev Sets caller to EntryPoint
    modifier whenCallerIsEntryPointOrSelf() virtual {
        vm.stopPrank();
        vm.startPrank(address(ep));
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATION TYPE MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier givenValidationTypeIsRoot() virtual {
        _;
    }

    modifier givenValidationTypeIsValidator() virtual {
        _;
    }

    modifier givenValidationTypeIsPermission() virtual {
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATION MODE MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier givenValidationModeHasEnableFlagSet() virtual {
        _;
    }

    modifier givenEnableSignatureIsInvalid() virtual {
        _;
    }

    modifier givenEnableSignatureIsValidAndNonceUnused() virtual {
        _;
    }

    modifier givenValidationModeIsReplayable() virtual {
        _;
    }

    modifier givenValidationModeIsNotReplayable() virtual {
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    MODULE STATE MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier givenValidatorIsNotInstalled() virtual {
        _;
    }

    modifier givenValidatorIsInstalled() virtual {
        kernel.installModule(1, address(newValidator), abi.encode(hex"", hex""));
        _;
    }

    modifier givenPermissionIsNotInstalled() virtual {
        _;
    }

    modifier givenPermissionIsInstalled() virtual {
        kernel.installModule(5, address(policy), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));
        kernel.installModule(6, address(signer), abi.encode(hex"deadbeef", abi.encodePacked(permissionId)));
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    EXECUTION MODE MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier givenCallTypeIsSingle() virtual {
        _;
    }

    modifier givenCallTypeIsBatch() virtual {
        _;
    }

    modifier givenCallTypeIsDelegatecall() virtual {
        _;
    }

    modifier givenExecTypeIsDefault() virtual {
        _;
    }

    modifier givenExecTypeIsTry() virtual {
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    MODULE TYPE MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier givenModuleTypeIsValidator() virtual {
        _;
    }

    modifier givenModuleTypeIsExecutor() virtual {
        _;
    }

    modifier givenModuleTypeIsFallback() virtual {
        _;
    }

    modifier givenModuleTypeIsHook() virtual {
        _;
    }

    modifier givenModuleTypeIsPolicy() virtual {
        _;
    }

    modifier givenModuleTypeIsSigner() virtual {
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    SIGNATURE FORMAT MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier givenHashIsERC7739MagicHash() virtual {
        _;
    }

    modifier givenHashIsNotERC7739MagicHash() virtual {
        _;
    }

    modifier givenSignatureModeIndicatesEnableMode() virtual {
        _;
    }

    modifier givenSignatureFormatIsTypedDataSign() virtual {
        _;
    }

    modifier givenSignatureFormatIsPersonalSign() virtual {
        _;
    }
}
