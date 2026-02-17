// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IKaiSignRegistry} from "../interfaces/IKaiSignRegistry.sol";

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
    error NotFinalized();
    error NotApproved();
    error AlreadyClaimed();
    error NotRevoked();
    error NoRevokeReward();

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

    // Pull model: track claimed UIDs
    mapping(bytes32 => bool) public claimedUids;              // uid => claimed for spec
    mapping(bytes32 => bool) public claimedRevokeUids;        // uid => claimed for revoke
    mapping(bytes32 => uint256) public revokeRewardPool;      // extcodehash => revoke reward pool

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
    event SpecRewardClaimed(
        bytes32 indexed uid,
        address indexed claimer,
        bytes32 indexed extcodehash,
        uint256 amount
    );
    event RevokeRewardClaimed(
        bytes32 indexed uid,
        address indexed claimer,
        bytes32 indexed extcodehash,
        uint256 amount
    );
    event RevokeRewardDeposited(
        bytes32 indexed extcodehash,
        address indexed depositor,
        uint256 amount
    );

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

    // ========== INTERNAL HELPERS ==========

    /**
     * @notice Calculate platform fee and claimer amount
     * @param amount Total amount
     * @return platformFee Fee for treasury
     * @return claimerAmount Amount for claimer
     */
    function _calculateFees(uint256 amount) internal pure returns (uint256 platformFee, uint256 claimerAmount) {
        platformFee = (amount * PLATFORM_FEE_PERCENT) / 100;
        claimerAmount = amount - platformFee;
    }

    /**
     * @notice Transfer funds with platform fee split
     * @param amount Total amount to distribute
     * @param claimer Recipient of claimer portion
     * @param isToken True for ERC20, false for ETH
     */
    function _transferWithFee(uint256 amount, address claimer, bool isToken) internal {
        (uint256 platformFee, uint256 claimerAmount) = _calculateFees(amount);

        if (isToken) {
            incentiveToken.safeTransfer(claimer, claimerAmount);
            incentiveToken.safeTransfer(treasury, platformFee);
        } else {
            (bool success1, ) = payable(claimer).call{value: claimerAmount}("");
            if (!success1) revert TransferFailed();

            (bool success2, ) = treasury.call{value: platformFee}("");
            if (!success2) revert TransferFailed();
        }
    }

    /**
     * @notice Transfer funds without fee (for clawback/emergency)
     * @param to Recipient
     * @param amount Amount to transfer
     * @param isToken True for ERC20, false for ETH
     */
    function _transfer(address to, uint256 amount, bool isToken) internal {
        if (isToken) {
            incentiveToken.safeTransfer(to, amount);
        } else {
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) revert TransferFailed();
        }
    }

    // ========== PULL MODEL: SPEC REWARD CLAIMING ==========

    /**
     * @notice Claim spec reward for an approved attestation (pull model)
     * @dev Reads attestation state from registry - can be batched with finalize()
     * @param uid The attestation UID
     */
    function claimForSpec(bytes32 uid) external nonReentrant {
        if (claimedUids[uid]) revert AlreadyClaimed();

        IKaiSignRegistry.Attestation memory att = IKaiSignRegistry(registry).getAttestation(uid);

        if (att.finalizedAt == 0) revert NotFinalized();
        if (att.revoked) revert NotApproved();

        claimedUids[uid] = true;

        uint256 poolAmount = poolByBytecode[att.extcodehash];
        if (poolAmount == 0) return;

        poolByBytecode[att.extcodehash] = 0;

        bool isToken = address(incentiveToken) != address(0);
        _transferWithFee(poolAmount, att.attester, isToken);

        (, uint256 claimerAmount) = _calculateFees(poolAmount);
        emit SpecRewardClaimed(uid, att.attester, att.extcodehash, claimerAmount);
    }

    // ========== PULL MODEL: REVOKE REWARD CLAIMING ==========

    /**
     * @notice Deposit ETH to revoke reward pool for a bytecode
     * @param extcodehash Target contract bytecode hash
     */
    function depositRevokeRewardETH(bytes32 extcodehash) external payable nonReentrant {
        if (address(incentiveToken) != address(0)) revert UseCreateIncentiveToken();
        if (extcodehash == bytes32(0)) revert InvalidBytecode();
        if (msg.value == 0) revert NoValue();

        revokeRewardPool[extcodehash] += msg.value;
        emit RevokeRewardDeposited(extcodehash, msg.sender, msg.value);
    }

    /**
     * @notice Deposit tokens to revoke reward pool for a bytecode
     * @param extcodehash Target contract bytecode hash
     * @param amount Amount of tokens
     */
    function depositRevokeRewardToken(bytes32 extcodehash, uint256 amount) external nonReentrant {
        if (address(incentiveToken) == address(0)) revert UseCreateIncentiveETH();
        if (extcodehash == bytes32(0)) revert InvalidBytecode();
        if (amount == 0) revert NoValue();

        incentiveToken.safeTransferFrom(msg.sender, address(this), amount);
        revokeRewardPool[extcodehash] += amount;
        emit RevokeRewardDeposited(extcodehash, msg.sender, amount);
    }

    /**
     * @notice Claim revoke reward for a successful revocation (pull model)
     * @dev Reads attestation state from registry - can be batched with finalizeRevoke()
     * @param uid The attestation UID that was revoked
     */
    function claimRevokeReward(bytes32 uid) external nonReentrant {
        if (claimedRevokeUids[uid]) revert AlreadyClaimed();

        IKaiSignRegistry.Attestation memory att = IKaiSignRegistry(registry).getAttestation(uid);

        if (!att.revoked) revert NotRevoked();

        address revoker = IKaiSignRegistry(registry).revokeProposers(uid);
        if (revoker == address(0)) revert NoRevokeReward();

        claimedRevokeUids[uid] = true;

        uint256 rewardAmount = revokeRewardPool[att.extcodehash];
        if (rewardAmount == 0) return;

        revokeRewardPool[att.extcodehash] = 0;

        bool isToken = address(incentiveToken) != address(0);
        _transferWithFee(rewardAmount, revoker, isToken);

        (, uint256 claimerAmount) = _calculateFees(rewardAmount);
        emit RevokeRewardClaimed(uid, revoker, att.extcodehash, claimerAmount);
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

        _transfer(msg.sender, amount, incentive.isToken);

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
     * @notice Get revoke reward pool for a bytecode
     * @param extcodehash Bytecode hash
     * @return amount Revoke reward pool amount
     */
    function getRevokeRewardPool(bytes32 extcodehash) external view returns (uint256 amount) {
        return revokeRewardPool[extcodehash];
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
            _transfer(to, amount, false);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // ========== RECEIVE ==========
    receive() external payable {}
}
