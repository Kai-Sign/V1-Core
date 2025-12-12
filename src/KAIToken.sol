// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title KAIToken
 * @notice Native governance token for KaiSign arbitration system
 * @dev ERC20 with permit (gasless approvals via ERC20Votes), voting capabilities, and burning for slashing
 *      Uses OpenZeppelin v4.9.6 which has ERC20Votes inheriting from ERC20Permit
 */
contract KAIToken is ERC20, ERC20Burnable, ERC20Votes, AccessControl {

    // =============================================================================
    //                                   ROLES
    // =============================================================================
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // =============================================================================
    //                                CONSTANTS
    // =============================================================================
    string public constant VERSION = "1.0.0";

    // =============================================================================
    //                                  EVENTS
    // =============================================================================
    event TokensMinted(address indexed to, uint256 amount, address indexed minter);
    event TokensBurned(address indexed from, uint256 amount, address indexed burner);

    // =============================================================================
    //                              CUSTOM ERRORS
    // =============================================================================
    error ZeroAddress();
    error ZeroAmount();
    error NoAdmins();

    // =============================================================================
    //                               CONSTRUCTOR
    // =============================================================================
    /**
     * @notice Deploys the KAI token
     * @param name Token name (e.g., "Kai Token")
     * @param symbol Token symbol (e.g., "KAI")
     * @param initialAdmins Array of addresses to grant admin roles
     * @param initialSupply Initial token supply to mint to deployer (can be 0)
     */
    constructor(
        string memory name,
        string memory symbol,
        address[] memory initialAdmins,
        uint256 initialSupply
    ) ERC20(name, symbol) ERC20Permit(name) {
        if (initialAdmins.length == 0) revert NoAdmins();

        // Grant deployer the default admin role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Grant roles to initial admins
        for (uint256 i = 0; i < initialAdmins.length; i++) {
            if (initialAdmins[i] == address(0)) revert ZeroAddress();
            _grantRole(DEFAULT_ADMIN_ROLE, initialAdmins[i]);
            _grantRole(MINTER_ROLE, initialAdmins[i]);
        }

        // Mint initial supply to deployer if specified
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    // =============================================================================
    //                              MINTING FUNCTIONS
    // =============================================================================
    /**
     * @notice Mint new tokens to an address
     * @dev Only callable by addresses with MINTER_ROLE
     * @param to Recipient address
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _mint(to, amount);
        emit TokensMinted(to, amount, msg.sender);
    }

    // =============================================================================
    //                              BURNING FUNCTIONS
    // =============================================================================
    /**
     * @notice Burn tokens from an account (for slashing)
     * @dev Only callable by addresses with BURNER_ROLE (KAIArbitration contract)
     * @param account Account to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFromAccount(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _burn(account, amount);
        emit TokensBurned(account, amount, msg.sender);
    }

    // =============================================================================
    //                              ROLE MANAGEMENT
    // =============================================================================
    /**
     * @notice Grant burner role to an address (typically KAIArbitration contract)
     * @dev Only callable by admins
     * @param burner Address to grant burner role
     */
    function grantBurnerRole(address burner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (burner == address(0)) revert ZeroAddress();
        _grantRole(BURNER_ROLE, burner);
    }

    /**
     * @notice Grant minter role to an address
     * @dev Only callable by admins
     * @param minter Address to grant minter role
     */
    function grantMinterRole(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (minter == address(0)) revert ZeroAddress();
        _grantRole(MINTER_ROLE, minter);
    }

    /**
     * @notice Revoke burner role from an address
     * @dev Only callable by admins
     * @param burner Address to revoke burner role from
     */
    function revokeBurnerRole(address burner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BURNER_ROLE, burner);
    }

    /**
     * @notice Revoke minter role from an address
     * @dev Only callable by admins
     * @param minter Address to revoke minter role from
     */
    function revokeMinterRole(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, minter);
    }

    // =============================================================================
    //                          REQUIRED OVERRIDES
    // =============================================================================
    /**
     * @dev Override required by Solidity for multiple inheritance
     *      Called on mint, burn, and transfer
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}
