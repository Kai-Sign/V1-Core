// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IncentivePool
 * @notice Bounty system for ERC7730 spec submissions
 * @dev Dual-mode: ETH (Phase 1) or bToken (Phase 2)
 *
 * Phase 1: ETH incentives - Anyone can post ETH bounties for specific bytecodes
 * Phase 2: bToken incentives - Users buy bToken to create incentives
 *
 * When a spec is accepted, the creator claims the incentive pool for that bytecode
 */
contract IncentivePool is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== CUSTOM ERRORS ==========
    error InvalidBytecode();
    error NoValue();
    error InvalidDuration();
    error NotClaimable();
    error TooEarlyToClawback();
    error NotCreator();
    error Unauthorized();
    error TransferFailed();
    error UseCreateIncentiveToken();
    error UseCreateIncentiveETH();

    // ========== CONSTANTS ==========
    uint256 public constant PLATFORM_FEE_PERCENT = 5;
    uint256 public constant INCENTIVE_CLAWBACK_PERIOD = 90 days;
    uint256 public constant MAX_DURATION = 30 days;

    // ========== STATE ==========
    address public immutable registry;
    address public immutable treasury;
    IERC20 public incentiveToken;         // address(0) = ETH mode (Phase 1), bToken = ERC20 mode (Phase 2)

    struct Incentive {
        address creator;
        uint80 amount;
        uint64 deadline;
        uint64 createdAt;
        bytes32 extcodehash;    // Target bytecode
        bool isClaimed;
        bool isActive;
        bool isToken;           // true = ERC20, false = ETH
        string description;
    }

    mapping(bytes32 => Incentive) public incentives;
    mapping(bytes32 => uint256) public poolByBytecode;        // extcodehash => total pool
    mapping(bytes32 => uint256) public contributorCount;      // extcodehash => count
    mapping(address => bytes32[]) public userIncentives;

    // ========== EVENTS ==========
    event IncentiveCreated(
        bytes32 indexed incentiveId,
        address indexed creator,
        bytes32 indexed extcodehash,
        uint256 amount,
        uint64 deadline,
        bool isToken,
        string description
    );
    event IncentiveClaimed(
        bytes32 indexed incentiveId,
        address indexed claimer,
        bytes32 indexed uid,
        uint256 amount
    );
    event IncentiveClawback(
        bytes32 indexed incentiveId,
        address indexed creator,
        uint256 amount
    );
    event IncentiveTokenSet(address indexed token);

    // ========== CONSTRUCTOR ==========
    /**
     * @notice Deploy IncentivePool
     * @param _registry ERC7730Registry address
     * @param _treasury Treasury address for platform fees
     * @param _initialOwner Initial owner (multisig for Phase 1)
     */
    constructor(
        address _registry,
        address _treasury,
        address _initialOwner
    ) {
        require(_registry != address(0), "Invalid registry");
        require(_treasury != address(0), "Invalid treasury");

        registry = _registry;
        treasury = _treasury;
        // incentiveToken = address(0) by default = ETH mode (Phase 1)

        // Transfer ownership to initial owner
        if (_initialOwner != msg.sender) {
            _transferOwnership(_initialOwner);
        }
    }

    // ========== ADMIN ==========

    /**
     * @notice Set incentive token for Phase 2
     * @dev Called when transitioning to token governance
     * @param _token The bToken address (set to address(0) for ETH mode)
     */
    function setIncentiveToken(address _token) external onlyOwner {
        incentiveToken = IERC20(_token);
        emit IncentiveTokenSet(_token);
    }

    // ========== INCENTIVE CREATION ==========

    /**
     * @notice Create incentive with ETH (Phase 1)
     * @param extcodehash Target contract bytecode hash
     * @param duration How long the incentive is valid
     * @param description Human-readable description
     * @return incentiveId Unique identifier for the incentive
     */
    function createIncentiveETH(
        bytes32 extcodehash,
        uint64 duration,
        string calldata description
    ) external payable nonReentrant returns (bytes32 incentiveId) {
        if (address(incentiveToken) != address(0)) revert UseCreateIncentiveToken();
        if (extcodehash == bytes32(0)) revert InvalidBytecode();
        if (msg.value == 0) revert NoValue();
        if (duration == 0 || duration > MAX_DURATION) revert InvalidDuration();

        incentiveId = _createIncentive(extcodehash, msg.value, duration, description, false);
    }

    /**
     * @notice Create incentive with bToken (Phase 2)
     * @dev User must approve bToken first
     * @param extcodehash Target contract bytecode hash
     * @param amount Amount of bToken
     * @param duration How long the incentive is valid
     * @param description Human-readable description
     * @return incentiveId Unique identifier for the incentive
     */
    function createIncentiveToken(
        bytes32 extcodehash,
        uint256 amount,
        uint64 duration,
        string calldata description
    ) external nonReentrant returns (bytes32 incentiveId) {
        if (address(incentiveToken) == address(0)) revert UseCreateIncentiveETH();
        if (extcodehash == bytes32(0)) revert InvalidBytecode();
        if (amount == 0) revert NoValue();
        if (duration == 0 || duration > MAX_DURATION) revert InvalidDuration();

        // Transfer bToken from user
        incentiveToken.safeTransferFrom(msg.sender, address(this), amount);

        incentiveId = _createIncentive(extcodehash, amount, duration, description, true);
    }

    function _createIncentive(
        bytes32 extcodehash,
        uint256 amount,
        uint64 duration,
        string calldata description,
        bool isToken
    ) internal returns (bytes32 incentiveId) {
        incentiveId = keccak256(abi.encodePacked(
            msg.sender,
            extcodehash,
            amount,
            block.timestamp,
            description
        ));

        incentives[incentiveId] = Incentive({
            creator: msg.sender,
            amount: uint80(amount),
            deadline: uint64(block.timestamp + duration),
            createdAt: uint64(block.timestamp),
            extcodehash: extcodehash,
            isClaimed: false,
            isActive: true,
            isToken: isToken,
            description: description
        });

        userIncentives[msg.sender].push(incentiveId);
        poolByBytecode[extcodehash] += amount;
        contributorCount[extcodehash]++;

        emit IncentiveCreated(
            incentiveId,
            msg.sender,
            extcodehash,
            amount,
            uint64(block.timestamp + duration),
            isToken,
            description
        );
    }

    // ========== INCENTIVE CLAIMING ==========

    /**
     * @notice Claim incentive pool for a bytecode
     * @dev Called by registry when attestation is accepted
     * @param extcodehash The bytecode hash
     * @param uid The attestation UID
     * @param claimer Who receives the reward (spec creator)
     */
    function claimPool(
        bytes32 extcodehash,
        bytes32 uid,
        address claimer
    ) external nonReentrant {
        if (msg.sender != registry) revert Unauthorized();

        uint256 poolAmount = poolByBytecode[extcodehash];
        if (poolAmount == 0) return;

        poolByBytecode[extcodehash] = 0;

        uint256 platformFee = (poolAmount * PLATFORM_FEE_PERCENT) / 100;
        uint256 claimerAmount = poolAmount - platformFee;

        if (address(incentiveToken) == address(0)) {
            // ETH mode
            (bool success1, ) = payable(claimer).call{value: claimerAmount}("");
            if (!success1) revert TransferFailed();

            (bool success2, ) = treasury.call{value: platformFee}("");
            if (!success2) revert TransferFailed();
        } else {
            // Token mode
            incentiveToken.safeTransfer(claimer, claimerAmount);
            incentiveToken.safeTransfer(treasury, platformFee);
        }

        emit IncentiveClaimed(bytes32(0), claimer, uid, claimerAmount);
    }

    /**
     * @notice Claim a specific incentive
     * @dev Called by registry when attestation for specific incentive is accepted
     * @param incentiveId The incentive ID
     * @param uid The attestation UID
     * @param claimer Who receives the reward
     */
    function claimIncentive(
        bytes32 incentiveId,
        bytes32 uid,
        address claimer
    ) external nonReentrant {
        if (msg.sender != registry) revert Unauthorized();

        Incentive storage incentive = incentives[incentiveId];

        if (incentive.isClaimed || !incentive.isActive) revert NotClaimable();
        if (block.timestamp > incentive.deadline) revert NotClaimable();

        incentive.isClaimed = true;
        incentive.isActive = false;

        uint256 amount = incentive.amount;
        uint256 platformFee = (amount * PLATFORM_FEE_PERCENT) / 100;
        uint256 claimerAmount = amount - platformFee;

        // Update pool
        poolByBytecode[incentive.extcodehash] -= amount;
        contributorCount[incentive.extcodehash]--;

        if (incentive.isToken) {
            incentiveToken.safeTransfer(claimer, claimerAmount);
            incentiveToken.safeTransfer(treasury, platformFee);
        } else {
            (bool success1, ) = payable(claimer).call{value: claimerAmount}("");
            if (!success1) revert TransferFailed();

            (bool success2, ) = treasury.call{value: platformFee}("");
            if (!success2) revert TransferFailed();
        }

        emit IncentiveClaimed(incentiveId, claimer, uid, claimerAmount);
    }

    // ========== CLAWBACK ==========

    /**
     * @notice Clawback unclaimed incentive after 90 days
     * @param incentiveId The incentive ID to clawback
     */
    function clawbackIncentive(bytes32 incentiveId) external nonReentrant {
        Incentive storage incentive = incentives[incentiveId];

        if (incentive.creator != msg.sender) revert NotCreator();
        if (incentive.isClaimed || !incentive.isActive) revert NotClaimable();
        if (block.timestamp < incentive.createdAt + INCENTIVE_CLAWBACK_PERIOD) {
            revert TooEarlyToClawback();
        }

        incentive.isClaimed = true;
        incentive.isActive = false;

        uint256 amount = incentive.amount;
        poolByBytecode[incentive.extcodehash] -= amount;
        contributorCount[incentive.extcodehash]--;

        if (incentive.isToken) {
            incentiveToken.safeTransfer(msg.sender, amount);
        } else {
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        }

        emit IncentiveClawback(incentiveId, msg.sender, amount);
    }

    // ========== QUERIES ==========

    /**
     * @notice Get pool info for a bytecode
     * @param extcodehash Bytecode hash
     * @return amount Total pool amount
     * @return count Number of contributors
     */
    function getPool(bytes32 extcodehash) external view returns (uint256 amount, uint256 count) {
        return (poolByBytecode[extcodehash], contributorCount[extcodehash]);
    }

    /**
     * @notice Get user's incentives
     * @param user User address
     * @return Array of incentive IDs
     */
    function getUserIncentives(address user) external view returns (bytes32[] memory) {
        return userIncentives[user];
    }

    /**
     * @notice Get incentive details
     * @param incentiveId Incentive ID
     * @return Incentive struct
     */
    function getIncentive(bytes32 incentiveId) external view returns (Incentive memory) {
        return incentives[incentiveId];
    }

    /**
     * @notice Check if using token mode
     * @return True if in token mode (Phase 2)
     */
    function isTokenMode() external view returns (bool) {
        return address(incentiveToken) != address(0);
    }

    /**
     * @notice Get pool for a contract address
     * @param target Contract address
     * @return amount Pool amount
     * @return count Contributor count
     */
    function getPoolForAddress(address target) external view returns (uint256 amount, uint256 count) {
        bytes32 codehash;
        assembly {
            codehash := extcodehash(target)
        }
        return (poolByBytecode[codehash], contributorCount[codehash]);
    }

    // ========== EMERGENCY ==========

    /**
     * @notice Emergency withdraw stuck funds
     * @dev Only owner, only for emergencies
     * @param token Token address (address(0) for ETH)
     * @param to Recipient
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // ========== RECEIVE ==========
    receive() external payable {}
}
