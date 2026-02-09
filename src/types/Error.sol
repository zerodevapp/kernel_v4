// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ValidationId} from "./Types.sol";

error ImplementationNotDeployed();

error ModuleInstallFailed();
error ModuleUninstallFailed();

error InvalidValidator();

error NotImplemented();

error NotInstalled();

error InstallSignatureVerificationFailed();

error InvalidRootValidation();
error InvalidCallType();
error InvalidExecType();

error InvalidSelector();
error InvalidEnableSignature();

error Unauthorized();

error InvalidValidationType();
error OccupiedValidationId();

error InvalidPermissionUninstallOrder();
error InvalidPermissionId();
error InvalidNonce();
error InvalidInitialization();
error InvalidDataLength();
error CannotUninstallRoot();
error InvalidSignature();
error InvalidVid(ValidationId vId);

error UnauthorizedCallData();
error PermissionInstallNotFinished();
error InvalidPermissionInstall();
error LastSignatureShouldBeSigner();

error InvalidSigner();

error NotApprovedFactory();

error DeployFailed();

error InvalidOwner();

error NotExecutor();

error AlreadyInitialized(address smartAccount);

error NotInitialized(address smartAccount);

error InvalidTargetAddress(address target);

error ValidityFormatMismatch();
