// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

contract Counter {
    uint256 private _number;
    
    function number() external view returns (uint256) {
        return _number;
    }
    
    function setNumber(uint256 newNumber) external {
        _number = newNumber;
    }
    
    function increment() external {
        _number++;
    }
}