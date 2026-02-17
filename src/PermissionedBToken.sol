// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PermissionedBToken
 * @notice Bond token where only the owner (minter) can transfer tokens
 * @dev Uses OpenZeppelin's _beforeTokenTransfer hook pattern for transfer restrictions
 *      Reference: https://docs.openzeppelin.com/contracts/4.x/api/token/erc20
 *      Forum: https://forum.openzeppelin.com/t/how-to-prevent-erc20-transfer-until-a-specific-block-and-only-allow-the-contract-creator-to-transfer/4236
 */
contract PermissionedBToken is ERC20, Ownable {
    error OnlyOwnerCanTransfer();

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

    /**
     * @notice Hook that restricts all transfers to owner only
     * @dev Called before any transfer including mint/burn
     *      - from == address(0): minting (allowed, onlyOwner enforced in mint())
     *      - to == address(0): burning (blocked for non-owner)
     *      - otherwise: transfer (only owner can initiate)
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        // Allow minting (from == address(0)) - already restricted by onlyOwner
        if (from == address(0)) return;

        // All other transfers (including burns) require owner
        if (msg.sender != owner()) revert OnlyOwnerCanTransfer();
    }
}
