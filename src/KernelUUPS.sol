// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Kernel} from "./Kernel.sol";
import {Install} from "./types/Structs.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";

contract KernelUUPS is Kernel, UUPSUpgradeable, Initializable {
    constructor(IEntryPoint _entryPoint) Kernel(_entryPoint) {
        _disableInitializers();
    }

    function initialize(Install[] calldata packages) external payable override initializer {
        // first package will be used as root validation (validator type 1, or permission type 5/6)
        _initialize(packages);
    }

    function _authorizeUpgrade(address) internal view override {
        _onlyEntryPointOrSelf();
    }
}
