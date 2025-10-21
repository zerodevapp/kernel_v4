pragma solidity ^0.8.0;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {EfficientHashLib} from "solady/utils/EfficientHashLib.sol";

contract Staker is Ownable, EIP712 {
    mapping(address => bool) public approved;

    error NotApprovedFactory();

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    function _domainNameAndVersion() internal view override returns (string memory, string memory) {
        return ("Staker", "0.0.1");
    }

    function deployWithFactory(address factory, bytes calldata createData) external payable returns (address) {
        if (!approved[factory]) {
            revert NotApprovedFactory();
        }
        (bool success, bytes memory ret) = factory.call(createData);
        return abi.decode(ret, (address));
    }

    function approveFactory(address _factory, bool approval) external payable onlyOwner {
        approved[_factory] = approval;
    }

    bytes32 APPROVE_FACTORY_STRUCT_HASH = 0x5f5d54a660883657f2f36565a4221ea47582afba62e38479852d3078c781c6e2;

    function approveFactoryWithSignature(address _factory, bool approval, bytes calldata signature)
        external
        payable
        onlyOwner
    {
        // struct :
        // {
        //   factory: address,
        //   approval: bool,
        // }
        bytes32 digest = _hashTypedDataSansChainId(
            EfficientHashLib.hash(
                uint256(APPROVE_FACTORY_STRUCT_HASH),
                uint256(uint160(_factory)),
                approval ? 1 : 0
            )
        );
        require(owner() == ECDSA.recover(digest, signature), "InvalidSignature");
        approved[_factory] = approval;
    }

    function stake(IEntryPoint entryPoint, uint32 unstakeDelay) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelay);
    }

    function unlockStake(IEntryPoint entryPoint) external payable onlyOwner {
        entryPoint.unlockStake();
    }

    function withdrawStake(IEntryPoint entryPoint, address payable recipient) external payable onlyOwner {
        entryPoint.withdrawStake(recipient);
    }
}
