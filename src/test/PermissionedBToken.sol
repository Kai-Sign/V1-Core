// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PermissionedBToken
 * @notice Placeholder bToken for permissioned Reality.eth participation
 * @dev Owner mints to approved participants. No public mint.
 */
contract PermissionedBToken is ERC20, Ownable {
    constructor(address _owner) ERC20("Permissioned Bond Token", "pBTOKEN") {
        _transferOwnership(_owner);
    }

    /// @notice Mint tokens to approved participant
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Batch mint to multiple participants
    function batchMint(address[] calldata recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amount);
        }
    }
}
