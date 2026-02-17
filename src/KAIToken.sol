// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title KAIToken
 * @notice Native governance token for KaiSign with EIGEN-style intersubjective forking
 * @dev ERC20 with permit, voting, burning, and fork capability for intersubjective disputes
 *
 * Fork Mechanism:
 * - On intersubjective dispute, use KAITokenFactory to fork the token
 * - Fork creates a new KAIToken with same balances at fork time
 * - Each fork operates independently (separate ERC20)
 * - Community chooses which fork to use (market decides value)
 * - KaiSignRegistry universes can use different forks as bondToken
 */
contract KAIToken is ERC20, ERC20Burnable, ERC20Votes, AccessControl {

    // =============================================================================
    //                                   ROLES
    // =============================================================================
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // =============================================================================
    //                                CONSTANTS
    // =============================================================================
    string public constant VERSION = "2.0.0";

    // =============================================================================
    //                              FORK TRACKING
    // =============================================================================
    /// @notice This token's fork ID (0 for original, increments for each fork)
    uint256 public immutable forkId;

    /// @notice Parent fork address (address(0) for original token)
    address public immutable parentFork;

    /// @notice Timestamp when this fork was created (0 for original)
    uint256 public immutable forkTimestamp;

    /// @notice Number of child forks created from this token
    uint256 public forkCount;

    /// @notice Addresses of child forks
    address[] public childForks;

    /// @notice Whether this token has been forked (for tracking purposes)
    bool public hasForked;

    // =============================================================================
    //                                  EVENTS
    // =============================================================================
    event TokensMinted(address indexed to, uint256 amount, address indexed minter);
    event TokensBurned(address indexed from, uint256 amount, address indexed burner);
    event MarkedAsForked(uint256 timestamp);
    event ChildForkRegistered(address indexed childFork, uint256 forkCount);

    // =============================================================================
    //                              CUSTOM ERRORS
    // =============================================================================
    error ZeroAddress();
    error ZeroAmount();
    error NoAdmins();
    error AlreadyForked();

    // =============================================================================
    //                               CONSTRUCTOR
    // =============================================================================
    /**
     * @notice Deploys the KAI token (original or fork)
     * @param name Token name (e.g., "Kai Token" or "Kai Token Fork 1")
     * @param symbol Token symbol (e.g., "KAI" or "KAI-F1")
     * @param initialAdmins Array of addresses to grant admin roles
     * @param initialSupply Initial token supply to mint to deployer (can be 0, ignored for forks)
     * @param _forkId Fork ID (0 for original)
     * @param _parentFork Parent fork address (address(0) for original)
     */
    constructor(
        string memory name,
        string memory symbol,
        address[] memory initialAdmins,
        uint256 initialSupply,
        uint256 _forkId,
        address _parentFork
    ) ERC20(name, symbol) ERC20Permit(name) {
        if (initialAdmins.length == 0) revert NoAdmins();

        forkId = _forkId;
        parentFork = _parentFork;
        forkTimestamp = _forkId > 0 ? block.timestamp : 0;

        // Grant deployer the default admin role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Grant roles to initial admins
        for (uint256 i = 0; i < initialAdmins.length; i++) {
            if (initialAdmins[i] == address(0)) revert ZeroAddress();
            _grantRole(DEFAULT_ADMIN_ROLE, initialAdmins[i]);
            _grantRole(MINTER_ROLE, initialAdmins[i]);
        }

        // Mint initial supply to deployer if specified (only for original, not forks)
        if (initialSupply > 0 && _forkId == 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    // =============================================================================
    //                              FORK FUNCTIONS
    // =============================================================================
    /**
     * @notice Mark this token as forked (called by factory)
     * @dev Only callable by addresses with FACTORY_ROLE or DEFAULT_ADMIN_ROLE
     */
    function markAsForked() external {
        if (!hasRole(FACTORY_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert ZeroAddress(); // Reusing error for unauthorized
        }
        hasForked = true;
        emit MarkedAsForked(block.timestamp);
    }

    /**
     * @notice Register a child fork (called by factory)
     * @dev Only callable by addresses with FACTORY_ROLE or DEFAULT_ADMIN_ROLE
     * @param childFork Address of the child fork token
     */
    function registerChildFork(address childFork) external {
        if (!hasRole(FACTORY_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert ZeroAddress(); // Reusing error for unauthorized
        }
        if (childFork == address(0)) revert ZeroAddress();

        forkCount++;
        childForks.push(childFork);
        emit ChildForkRegistered(childFork, forkCount);
    }

    /**
     * @notice Grant factory role to an address (typically KAITokenFactory)
     * @dev Only callable by admins
     * @param factory Address to grant factory role
     */
    function grantFactoryRole(address factory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (factory == address(0)) revert ZeroAddress();
        _grantRole(FACTORY_ROLE, factory);
    }

    /**
     * @notice Revoke factory role from an address
     * @dev Only callable by admins
     * @param factory Address to revoke factory role from
     */
    function revokeFactoryRole(address factory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(FACTORY_ROLE, factory);
    }

    /**
     * @notice Get all child fork addresses
     * @return Array of child fork token addresses
     */
    function getChildForks() external view returns (address[] memory) {
        return childForks;
    }

    /**
     * @notice Check if an address is a child fork of this token
     * @param token Address to check
     * @return True if token is a child fork
     */
    function isChildFork(address token) external view returns (bool) {
        for (uint256 i = 0; i < childForks.length; i++) {
            if (childForks[i] == token) return true;
        }
        return false;
    }

    /**
     * @notice Get fork lineage (trace back to original)
     * @return forkIds Array of fork IDs from this token back to original
     * @return forkAddresses Array of fork addresses from this token back to original
     */
    function getForkLineage() external view returns (uint256[] memory forkIds, address[] memory forkAddresses) {
        // Count depth
        uint256 depth = 1;
        address current = address(this);
        while (KAIToken(current).parentFork() != address(0)) {
            depth++;
            current = KAIToken(current).parentFork();
        }

        forkIds = new uint256[](depth);
        forkAddresses = new address[](depth);

        current = address(this);
        for (uint256 i = 0; i < depth; i++) {
            forkIds[i] = KAIToken(current).forkId();
            forkAddresses[i] = current;
            if (KAIToken(current).parentFork() != address(0)) {
                current = KAIToken(current).parentFork();
            }
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
