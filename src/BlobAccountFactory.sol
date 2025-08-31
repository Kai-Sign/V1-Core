// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./BlobAccount.sol";

/**
 * @title BlobAccountFactory
 * @notice Factory for deploying BlobAccount smart accounts
 * @dev Uses CREATE2 for deterministic addresses
 */
contract BlobAccountFactory {
    BlobAccount public immutable accountImplementation;
    
    event AccountCreated(address indexed account, address indexed owner, uint256 salt);
    
    constructor(IEntryPoint _entryPoint) {
        accountImplementation = new BlobAccount(_entryPoint);
    }
    
    /**
     * @notice Create a new BlobAccount for a user
     * @param owner The owner of the new account
     * @param salt A salt for CREATE2 address generation
     */
    function createAccount(address owner, uint256 salt) public returns (BlobAccount) {
        address addr = getAddress(owner, salt);
        uint256 codeSize = addr.code.length;
        
        if (codeSize > 0) {
            return BlobAccount(payable(addr));
        }
        
        bytes memory initData = abi.encodeCall(BlobAccount.initialize, (owner));
        
        ERC1967Proxy proxy = new ERC1967Proxy{salt: bytes32(salt)}(
            address(accountImplementation),
            initData
        );
        
        emit AccountCreated(address(proxy), owner, salt);
        return BlobAccount(payable(address(proxy)));
    }
    
    /**
     * @notice Get the address of a BlobAccount
     * @param owner The owner of the account
     * @param salt The salt used for CREATE2
     */
    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes memory initData = abi.encodeCall(BlobAccount.initialize, (owner));
        
        bytes memory proxyConstructor = abi.encode(
            address(accountImplementation),
            initData
        );
        
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            proxyConstructor
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                bytes32(salt),
                keccak256(bytecode)
            )
        );
        
        return address(uint160(uint256(hash)));
    }
}