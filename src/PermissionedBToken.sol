// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Whitelistable.sol";

/**
 * @title PermissionedBToken
 * @notice Bond token with transfer restrictions using Circle/USDC pattern
 * @dev Based on Circle's Blacklistable pattern (inverted to whitelist)
 *      https://github.com/circlefin/stablecoin-evm
 *
 *      Transfer rules:
 *      - Owner can transfer to anyone
 *      - Anyone can transfer TO whitelisted addresses (e.g., Reality.eth)
 *      - Whitelisted addresses can transfer to anyone (e.g., Reality.eth returning winnings)
 *      - Other transfers blocked
 */
contract PermissionedBToken is ERC20, Whitelistable {
    /**
     * @param _owner Initial owner and whitelister
     */
    constructor(address _owner) ERC20("Permissioned Bond Token", "pBTOKEN") {
        _transferOwnership(_owner);
        whitelister = _owner;
    }

    /// @notice Mint tokens to recipient
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Batch mint to multiple recipients
    function batchMint(address[] calldata recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amount);
        }
    }

    /**
     * @notice Hook that restricts transfers
     * @dev Allowed transfers:
     *      - Minting (from == address(0))
     *      - Owner initiated transfers
     *      - Transfers TO whitelisted addresses (user -> Reality.eth)
     *      - Transfers FROM whitelisted addresses (Reality.eth -> user on finalize)
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        // Allow minting
        if (from == address(0)) return;

        // Allow owner to transfer anywhere
        if (msg.sender == owner()) return;

        // Allow whitelisted addresses to transfer anywhere (Reality.eth returning winnings)
        if (_isWhitelisted(msg.sender)) return;

        // Allow transfers TO whitelisted addresses (user bonding in Reality.eth)
        require(_isWhitelisted(to), "PermissionedBToken: transfer not allowed");
    }
}
