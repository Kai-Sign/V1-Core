// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {KAIToken} from "./KAIToken.sol";
import {KAIArbitration} from "./KAIArbitration.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title KAISlashing
 * @notice Fork-based slashing system for KaiSign (EIGEN-style intersubjective slashing)
 * @dev Allows community to challenge malicious actors via fork voting mechanism
 *
 * Slashing is NOT for voting with minority. Slashing is for PROVABLY BAD BEHAVIOR:
 * - Spam submissions (garbage specs)
 * - Bad disputes (disputing clearly valid specs)
 * - Gaming/collusion (coordinated attacks)
 *
 * Challenge Flow:
 * 1. Anyone can challenge an actor within CHALLENGE_WINDOW after voting finalizes
 * 2. Challenger stakes CHALLENGE_BOND
 * 3. New voting round: "Was this behavior malicious?"
 * 4. If challenge succeeds: Actor slashed, challenger rewarded
 * 5. If challenge fails: Challenger loses bond
 */
contract KAISlashing is ReentrancyGuard, AccessControl, Pausable {

    // =============================================================================
    //                                CUSTOM ERRORS
    // =============================================================================
    error InvalidContract();
    error ChallengeWindowClosed();
    error ChallengeWindowNotClosed();
    error InsufficientBond();
    error ChallengeNotFound();
    error ChallengeAlreadyResolved();
    error ChallengeVotingNotFinalized();
    error ActorNotInVoting();
    error AlreadyChallenged();
    error TransferFailed();
    error Unauthorized();
    error ZeroAddress();
    error InvalidChallengeType();
    error SelfChallenge();

    // =============================================================================
    //                                   ROLES
    // =============================================================================
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // =============================================================================
    //                                CONSTANTS
    // =============================================================================
    string public constant VERSION = "1.0.0";
    uint256 public constant CHALLENGE_WINDOW = 7 days;
    uint256 public constant CHALLENGE_BOND = 500 * 1e18;    // 500 KAI
    uint256 public constant SLASH_PERCENT = 50;             // 50% of stake slashed
    uint256 public constant CHALLENGER_REWARD_PERCENT = 25; // 25% of slashed to challenger
    uint32 public constant CHALLENGE_VOTING_PERIOD = 48 hours;
    uint16 public constant CHALLENGE_REWARD_RATE_BPS = 0;   // No inflation rewards for challenge votes

    // =============================================================================
    //                                  ENUMS
    // =============================================================================
    enum ChallengeType {
        SpamSubmission,    // Garbage spec submission
        BadDispute,        // Frivolous dispute of valid spec
        Collusion          // Coordinated attack on voting
    }

    enum ChallengeStatus {
        Pending,           // Challenge submitted, waiting for voting to start
        Voting,            // Challenge voting in progress
        Succeeded,         // Challenge won - target slashed
        Failed,            // Challenge lost - challenger loses bond
        Expired            // Challenge window passed without resolution
    }

    // =============================================================================
    //                                 STRUCTS
    // =============================================================================
    struct Challenge {
        bytes32 targetVotingID;     // Original voting being challenged
        address targetActor;         // Who is being challenged
        address challenger;          // Who initiated the challenge
        ChallengeType challengeType;
        ChallengeStatus status;
        uint96 challengerBond;       // KAI staked by challenger
        uint96 targetStake;          // Target's stake at risk
        bytes32 challengeVotingID;   // Voting ID for challenge resolution
        uint64 createdAt;
        uint64 resolvedAt;
        string evidence;             // IPFS hash or description of evidence
    }

    // =============================================================================
    //                              STATE VARIABLES
    // =============================================================================
    KAIToken public immutable kaiToken;
    KAIArbitration public kaiArbitration;

    // Challenge tracking
    mapping(bytes32 => Challenge) public challenges;
    mapping(bytes32 => mapping(address => bytes32)) public actorChallenges; // votingID => actor => challengeID
    mapping(address => bytes32[]) public userChallengesInitiated;
    mapping(address => bytes32[]) public userChallengesReceived;

    uint256 public totalChallenges;
    uint256 public successfulChallenges;
    uint256 public failedChallenges;

    // =============================================================================
    //                                  EVENTS
    // =============================================================================
    event ChallengeInitiated(
        bytes32 indexed challengeID,
        bytes32 indexed targetVotingID,
        address indexed targetActor,
        address challenger,
        ChallengeType challengeType,
        uint256 bond,
        string evidence
    );

    event ChallengeVotingStarted(
        bytes32 indexed challengeID,
        bytes32 indexed challengeVotingID
    );

    event ChallengeResolved(
        bytes32 indexed challengeID,
        ChallengeStatus status,
        uint256 slashedAmount,
        uint256 challengerReward
    );

    event StakeSlashed(
        bytes32 indexed challengeID,
        address indexed actor,
        uint256 amount,
        uint256 burnedAmount
    );

    // =============================================================================
    //                                MODIFIERS
    // =============================================================================
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    // =============================================================================
    //                               CONSTRUCTOR
    // =============================================================================
    /**
     * @notice Deploys the KAI Slashing contract
     * @param _kaiToken Address of the KAI token contract
     * @param _kaiArbitration Address of the KAI Arbitration contract
     * @param _initialAdmins Array of admin addresses
     */
    constructor(
        address _kaiToken,
        address _kaiArbitration,
        address[] memory _initialAdmins
    ) {
        if (_kaiToken == address(0)) revert InvalidContract();
        if (_kaiArbitration == address(0)) revert InvalidContract();
        if (_initialAdmins.length == 0) revert Unauthorized();

        kaiToken = KAIToken(_kaiToken);
        kaiArbitration = KAIArbitration(_kaiArbitration);

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i = 0; i < _initialAdmins.length; i++) {
            _grantRole(ADMIN_ROLE, _initialAdmins[i]);
        }
    }

    // =============================================================================
    //                           CHALLENGE INITIATION
    // =============================================================================
    /**
     * @notice Initiate a challenge against an actor's behavior in a voting round
     * @param targetVotingID The voting ID where the malicious behavior occurred
     * @param targetActor The address being challenged
     * @param challengeType Type of malicious behavior being alleged
     * @param evidence IPFS hash or description of evidence supporting the challenge
     * @return challengeID Unique identifier for this challenge
     */
    function initiateChallenge(
        bytes32 targetVotingID,
        address targetActor,
        ChallengeType challengeType,
        string calldata evidence
    ) external nonReentrant whenNotPaused returns (bytes32 challengeID) {
        if (targetActor == address(0)) revert ZeroAddress();
        if (targetActor == msg.sender) revert SelfChallenge();

        // Verify voting exists and is finalized
        (bool finalized, , , , uint256 endTime, , ) = kaiArbitration.getVotingDetails(targetVotingID);
        if (!finalized) revert ChallengeWindowNotClosed();

        // Verify within challenge window
        if (block.timestamp > endTime + CHALLENGE_WINDOW) revert ChallengeWindowClosed();

        // Verify actor participated in the voting
        (, uint96 targetStake, ) = kaiArbitration.getUserVoteRecord(targetVotingID, targetActor);
        if (targetStake == 0) revert ActorNotInVoting();

        // Check if actor already challenged for this voting
        if (actorChallenges[targetVotingID][targetActor] != bytes32(0)) revert AlreadyChallenged();

        // Transfer challenge bond from challenger
        bool success = kaiToken.transferFrom(msg.sender, address(this), CHALLENGE_BOND);
        if (!success) revert TransferFailed();

        // Generate challenge ID
        challengeID = keccak256(abi.encodePacked(
            targetVotingID,
            targetActor,
            msg.sender,
            block.timestamp
        ));

        // Lock the target's stake in KAIArbitration
        kaiArbitration.lockStakeForChallenge(targetVotingID, targetActor);

        // Create challenge
        challenges[challengeID] = Challenge({
            targetVotingID: targetVotingID,
            targetActor: targetActor,
            challenger: msg.sender,
            challengeType: challengeType,
            status: ChallengeStatus.Pending,
            challengerBond: uint96(CHALLENGE_BOND),
            targetStake: targetStake,
            challengeVotingID: bytes32(0),
            createdAt: uint64(block.timestamp),
            resolvedAt: 0,
            evidence: evidence
        });

        // Track challenge
        actorChallenges[targetVotingID][targetActor] = challengeID;
        userChallengesInitiated[msg.sender].push(challengeID);
        userChallengesReceived[targetActor].push(challengeID);
        totalChallenges++;

        emit ChallengeInitiated(
            challengeID,
            targetVotingID,
            targetActor,
            msg.sender,
            challengeType,
            CHALLENGE_BOND,
            evidence
        );

        // Immediately start challenge voting
        _startChallengeVoting(challengeID);

        return challengeID;
    }

    /**
     * @notice Start voting for a challenge
     * @param challengeID The challenge to start voting for
     */
    function _startChallengeVoting(bytes32 challengeID) internal {
        Challenge storage challenge = challenges[challengeID];

        // Initiate voting in KAIArbitration
        // The specID for challenges is the challengeID itself
        bytes32 challengeVotingID = kaiArbitration.initiateVotingForChallenge(
            challengeID,
            CHALLENGE_VOTING_PERIOD,
            CHALLENGE_REWARD_RATE_BPS
        );

        challenge.challengeVotingID = challengeVotingID;
        challenge.status = ChallengeStatus.Voting;

        emit ChallengeVotingStarted(challengeID, challengeVotingID);
    }

    // =============================================================================
    //                           CHALLENGE RESOLUTION
    // =============================================================================
    /**
     * @notice Resolve a challenge after voting has finalized
     * @param challengeID The challenge to resolve
     */
    function resolveChallenge(bytes32 challengeID) external nonReentrant whenNotPaused {
        Challenge storage challenge = challenges[challengeID];

        if (challenge.createdAt == 0) revert ChallengeNotFound();
        if (challenge.status != ChallengeStatus.Voting) revert ChallengeAlreadyResolved();

        // Get challenge voting result
        // TRUE = malicious behavior confirmed, FALSE = not malicious
        (bool finalized, bool isMalicious) = kaiArbitration.getVotingResult(challenge.challengeVotingID);
        if (!finalized) revert ChallengeVotingNotFinalized();

        challenge.resolvedAt = uint64(block.timestamp);

        uint256 slashedAmount = 0;
        uint256 challengerReward = 0;

        if (isMalicious) {
            // CHALLENGE SUCCEEDED - Slash the actor
            challenge.status = ChallengeStatus.Succeeded;
            successfulChallenges++;

            // Calculate slash amount
            slashedAmount = (uint256(challenge.targetStake) * SLASH_PERCENT) / 100;
            challengerReward = (slashedAmount * CHALLENGER_REWARD_PERCENT) / 100;
            uint256 burnAmount = slashedAmount - challengerReward;

            // Execute slash via KAIArbitration
            kaiArbitration.executeSlash(
                challenge.targetVotingID,
                challenge.targetActor,
                slashedAmount
            );

            // Return challenger's bond + reward
            bool transferSuccess = kaiToken.transfer(
                challenge.challenger,
                challenge.challengerBond + challengerReward
            );
            if (!transferSuccess) revert TransferFailed();

            // Burn the remainder
            if (burnAmount > 0) {
                kaiToken.burnFromAccount(address(this), burnAmount);
            }

            emit StakeSlashed(
                challengeID,
                challenge.targetActor,
                slashedAmount,
                burnAmount
            );

        } else {
            // CHALLENGE FAILED - Challenger loses bond
            challenge.status = ChallengeStatus.Failed;
            failedChallenges++;

            // Burn challenger's bond
            kaiToken.burnFromAccount(address(this), challenge.challengerBond);

            // Unlock target's stake
            kaiArbitration.unlockStake(challenge.targetVotingID, challenge.targetActor);
        }

        emit ChallengeResolved(
            challengeID,
            challenge.status,
            slashedAmount,
            challengerReward
        );
    }

    // =============================================================================
    //                              VIEW FUNCTIONS
    // =============================================================================
    /**
     * @notice Check if a voting is within the challenge window
     * @param votingID The voting ID to check
     * @return True if challenges can still be initiated
     */
    function isWithinChallengeWindow(bytes32 votingID) external view returns (bool) {
        (bool finalized, , , , uint256 endTime, , ) = kaiArbitration.getVotingDetails(votingID);
        if (!finalized) return false;
        return block.timestamp <= endTime + CHALLENGE_WINDOW;
    }

    /**
     * @notice Get challenge details
     * @param challengeID The challenge ID
     */
    function getChallenge(bytes32 challengeID) external view returns (
        bytes32 targetVotingID,
        address targetActor,
        address challenger,
        ChallengeType challengeType,
        ChallengeStatus status,
        uint256 challengerBond,
        uint256 targetStake,
        bytes32 challengeVotingID,
        uint64 createdAt,
        uint64 resolvedAt
    ) {
        Challenge storage c = challenges[challengeID];
        return (
            c.targetVotingID,
            c.targetActor,
            c.challenger,
            c.challengeType,
            c.status,
            c.challengerBond,
            c.targetStake,
            c.challengeVotingID,
            c.createdAt,
            c.resolvedAt
        );
    }

    /**
     * @notice Get challenges initiated by a user
     * @param user The user address
     */
    function getUserChallengesInitiated(address user) external view returns (bytes32[] memory) {
        return userChallengesInitiated[user];
    }

    /**
     * @notice Get challenges received by a user
     * @param user The user address
     */
    function getUserChallengesReceived(address user) external view returns (bytes32[] memory) {
        return userChallengesReceived[user];
    }

    /**
     * @notice Check if an actor has been challenged for a specific voting
     * @param votingID The voting ID
     * @param actor The actor address
     * @return challengeID The challenge ID if exists, bytes32(0) otherwise
     */
    function getActorChallenge(bytes32 votingID, address actor) external view returns (bytes32) {
        return actorChallenges[votingID][actor];
    }

    /**
     * @notice Get statistics about challenges
     */
    function getChallengeStats() external view returns (
        uint256 total,
        uint256 successful,
        uint256 failed,
        uint256 pending
    ) {
        return (
            totalChallenges,
            successfulChallenges,
            failedChallenges,
            totalChallenges - successfulChallenges - failedChallenges
        );
    }

    // =============================================================================
    //                              ADMIN FUNCTIONS
    // =============================================================================
    /**
     * @notice Update the KAI Arbitration contract reference
     * @param _kaiArbitration New KAI Arbitration contract address
     */
    function setKaiArbitration(address _kaiArbitration) external onlyAdmin {
        if (_kaiArbitration == address(0)) revert ZeroAddress();
        kaiArbitration = KAIArbitration(_kaiArbitration);
    }

    /**
     * @notice Pause all operations
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyAdmin {
        _unpause();
    }
}
