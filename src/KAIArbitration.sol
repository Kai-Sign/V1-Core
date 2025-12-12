// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {KAIToken} from "./KAIToken.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title KAIArbitration
 * @notice Per-spec staking and voting system for KaiSign using inflation-based rewards
 * @dev Replaces Reality.eth as the arbitrator with native KAI token-based voting
 *
 * Economic Model (like Ethereum staking):
 * - Winners receive NEWLY MINTED tokens as rewards (~10% APR)
 * - Losers get their full stake back (no slashing)
 * - Opportunity cost is the only "punishment" for minority voters
 *
 * Voting Flow:
 * 1. COMMIT PHASE (0 to commitRevealWindow): Voters commit hash(vote + salt) with stake
 * 2. REVEAL PHASE (commitRevealWindow to endTime): Voters reveal their votes
 * 3. FINALIZATION (after endTime): Anyone can finalize, majority wins
 * 4. CLAIMS: Winners claim stake + minted rewards, losers claim just their stake
 */
contract KAIArbitration is ReentrancyGuard, AccessControl, Pausable {

    // =============================================================================
    //                                CUSTOM ERRORS
    // =============================================================================
    error InvalidContract();
    error InvalidDuration();
    error InvalidRewardRate();
    error InsufficientStake();
    error CommitPhaseEnded();
    error RevealPhaseNotStarted();
    error VotingEnded();
    error VotingNotEnded();
    error AlreadyCommitted();
    error AlreadyRevealed();
    error NoCommitmentFound();
    error InvalidReveal();
    error AlreadyFinalized();
    error NotFinalized();
    error NoStake();
    error AlreadyClaimed();
    error VotedWithMinority();
    error VotedWithMajority();
    error InsufficientTotalStake();
    error TransferFailed();
    error MintFailed();
    error Unauthorized();
    error VotingNotFound();
    error ZeroAddress();
    error StakeLocked();
    error StakeNotLocked();
    error ChallengeWindowNotPassed();

    // =============================================================================
    //                                   ROLES
    // =============================================================================
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KAISIGN_ROLE = keccak256("KAISIGN_ROLE");
    bytes32 public constant SLASHING_ROLE = keccak256("SLASHING_ROLE");

    // =============================================================================
    //                                CONSTANTS
    // =============================================================================
    string public constant VERSION = "2.1.0";
    uint32 public constant MIN_VOTING_PERIOD = 24 hours;
    uint32 public constant MAX_VOTING_PERIOD = 7 days;
    uint32 public constant MIN_COMMIT_WINDOW = 6 hours;
    uint32 public constant MAX_COMMIT_WINDOW = 24 hours;
    uint16 public constant MAX_REWARD_RATE_BPS = 1000; // 10% max per cycle
    uint16 public constant DEFAULT_REWARD_RATE_BPS = 55; // ~0.055% per cycle → ~10% APR
    uint256 public constant CHALLENGE_WINDOW = 7 days; // Time after finalization to challenge

    // =============================================================================
    //                              STATE VARIABLES
    // =============================================================================
    KAIToken public immutable kaiToken;

    // Configurable parameters
    uint32 public defaultVotingPeriod;
    uint32 public commitRevealWindow;
    uint16 public defaultRewardRateBps;
    uint256 public minStakePerVote;
    uint256 public minTotalStakeThreshold;

    // Voting tracking
    mapping(bytes32 => SpecVoting) public specVotings;
    mapping(bytes32 => mapping(address => VoteCommitment)) public voteCommitments;
    mapping(bytes32 => mapping(address => VoterRecord)) public voterRecords;

    // User tracking
    mapping(address => uint256) public userTotalStake;
    mapping(address => bytes32[]) public userActiveVotes;

    // Slashing integration - stake locking for challenges
    mapping(bytes32 => mapping(address => bool)) public stakeLocked;

    // =============================================================================
    //                                 STRUCTS
    // =============================================================================
    struct SpecVoting {
        uint64 startTime;           // When voting started
        uint64 endTime;             // When voting ends
        uint96 totalStakeFor;       // Total stake voting TRUE (spec valid)
        uint96 totalStakeAgainst;   // Total stake voting FALSE (spec invalid)
        uint16 rewardRateBps;       // Reward rate in basis points (e.g., 55 = 0.055%)
        bool finalized;             // Whether voting has been finalized
        bool result;                // TRUE if spec accepted, FALSE if rejected
        uint32 voterCount;          // Total number of voters who revealed
        bytes32 specID;             // Reference to KaiSign spec
    }

    struct VoteCommitment {
        bytes32 commitHash;         // Keccak256(vote, salt)
        uint64 commitTime;          // When commitment was made
        bool revealed;              // Whether vote has been revealed
        uint96 stake;               // Amount staked on this vote
    }

    struct VoterRecord {
        bool vote;                  // TRUE (valid) or FALSE (invalid)
        uint96 stake;               // Amount staked
        bool claimed;               // Whether rewards/stake have been claimed
    }

    // =============================================================================
    //                                  EVENTS
    // =============================================================================
    event VotingInitiated(
        bytes32 indexed votingID,
        bytes32 indexed specID,
        uint64 endTime,
        uint16 rewardRateBps
    );

    event VoteCommitted(
        bytes32 indexed votingID,
        address indexed voter,
        uint256 stake
    );

    event VoteRevealed(
        bytes32 indexed votingID,
        address indexed voter,
        bool vote,
        uint256 stake
    );

    event VotingFinalized(
        bytes32 indexed votingID,
        bool result,
        uint256 totalStakeFor,
        uint256 totalStakeAgainst,
        uint32 voterCount
    );

    event RewardsClaimed(
        bytes32 indexed votingID,
        address indexed voter,
        uint256 originalStake,
        uint256 mintedReward,
        uint256 totalPayout
    );

    event StakeWithdrawn(
        bytes32 indexed votingID,
        address indexed voter,
        uint256 amount
    );

    event VotingExtended(
        bytes32 indexed votingID,
        uint32 extension
    );

    event ParameterUpdated(
        string parameterName,
        uint256 oldValue,
        uint256 newValue
    );

    event StakeLockedForChallenge(
        bytes32 indexed votingID,
        address indexed actor
    );

    event StakeUnlocked(
        bytes32 indexed votingID,
        address indexed actor
    );

    event StakeSlashed(
        bytes32 indexed votingID,
        address indexed actor,
        uint256 amount
    );

    // =============================================================================
    //                                MODIFIERS
    // =============================================================================
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    modifier onlyKaiSign() {
        if (!hasRole(KAISIGN_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    modifier onlySlashing() {
        if (!hasRole(SLASHING_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    modifier onlyKaiSignOrSlashing() {
        if (!hasRole(KAISIGN_ROLE, msg.sender) && !hasRole(SLASHING_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    // =============================================================================
    //                               CONSTRUCTOR
    // =============================================================================
    /**
     * @notice Deploys the KAI Arbitration contract
     * @param _kaiToken Address of the KAI token contract
     * @param _defaultVotingPeriod Default voting duration (e.g., 48 hours)
     * @param _commitRevealWindow Duration of commit phase (e.g., 12 hours)
     * @param _defaultRewardRateBps Default reward rate in basis points (e.g., 55 = 0.055%)
     * @param _minStakePerVote Minimum stake required per vote (e.g., 100 KAI)
     * @param _minTotalStakeThreshold Minimum total stake for valid vote (e.g., 1000 KAI)
     * @param _initialAdmins Array of admin addresses
     */
    constructor(
        address _kaiToken,
        uint32 _defaultVotingPeriod,
        uint32 _commitRevealWindow,
        uint16 _defaultRewardRateBps,
        uint256 _minStakePerVote,
        uint256 _minTotalStakeThreshold,
        address[] memory _initialAdmins
    ) {
        if (_kaiToken == address(0)) revert InvalidContract();
        if (_defaultVotingPeriod < MIN_VOTING_PERIOD || _defaultVotingPeriod > MAX_VOTING_PERIOD) revert InvalidDuration();
        if (_commitRevealWindow < MIN_COMMIT_WINDOW || _commitRevealWindow > MAX_COMMIT_WINDOW) revert InvalidDuration();
        if (_commitRevealWindow >= _defaultVotingPeriod) revert InvalidDuration();
        if (_defaultRewardRateBps > MAX_REWARD_RATE_BPS) revert InvalidRewardRate();
        if (_initialAdmins.length == 0) revert Unauthorized();

        kaiToken = KAIToken(_kaiToken);
        defaultVotingPeriod = _defaultVotingPeriod;
        commitRevealWindow = _commitRevealWindow;
        defaultRewardRateBps = _defaultRewardRateBps;
        minStakePerVote = _minStakePerVote;
        minTotalStakeThreshold = _minTotalStakeThreshold;

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i = 0; i < _initialAdmins.length; i++) {
            _grantRole(ADMIN_ROLE, _initialAdmins[i]);
        }
    }

    // =============================================================================
    //                              VOTING INITIATION
    // =============================================================================
    /**
     * @notice Initiate a new voting period for a spec
     * @dev Only callable by KaiSign contract
     * @param specID The spec ID from KaiSign
     * @param votingDuration Duration of the voting period
     * @param rewardRateBps Reward rate in basis points for majority voters
     * @return votingID Unique identifier for this voting round
     */
    function initiateVoting(
        bytes32 specID,
        uint32 votingDuration,
        uint16 rewardRateBps
    ) external onlyKaiSign whenNotPaused returns (bytes32 votingID) {
        if (rewardRateBps > MAX_REWARD_RATE_BPS) revert InvalidRewardRate();
        if (votingDuration < MIN_VOTING_PERIOD || votingDuration > MAX_VOTING_PERIOD) revert InvalidDuration();

        votingID = keccak256(abi.encodePacked(specID, block.timestamp, msg.sender));

        specVotings[votingID] = SpecVoting({
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + votingDuration),
            totalStakeFor: 0,
            totalStakeAgainst: 0,
            rewardRateBps: rewardRateBps,
            finalized: false,
            result: false,
            voterCount: 0,
            specID: specID
        });

        emit VotingInitiated(votingID, specID, uint64(block.timestamp + votingDuration), rewardRateBps);
        return votingID;
    }

    // =============================================================================
    //                              COMMIT PHASE
    // =============================================================================
    /**
     * @notice Commit a vote hash with stake
     * @dev Must be called during commit phase (0 to commitRevealWindow)
     * @param votingID The voting ID to participate in
     * @param commitHash Hash of (vote, salt) - keccak256(abi.encodePacked(vote, salt))
     * @param stakeAmount Amount of KAI to stake
     */
    function commitVote(
        bytes32 votingID,
        bytes32 commitHash,
        uint256 stakeAmount
    ) external nonReentrant whenNotPaused {
        SpecVoting storage voting = specVotings[votingID];

        if (voting.startTime == 0) revert VotingNotFound();
        if (block.timestamp >= voting.startTime + commitRevealWindow) revert CommitPhaseEnded();
        if (voting.finalized) revert AlreadyFinalized();
        if (stakeAmount < minStakePerVote) revert InsufficientStake();
        if (voteCommitments[votingID][msg.sender].commitTime != 0) revert AlreadyCommitted();

        // Transfer KAI tokens to this contract
        bool success = kaiToken.transferFrom(msg.sender, address(this), stakeAmount);
        if (!success) revert TransferFailed();

        // Prevent overflow for uint96
        if (stakeAmount > type(uint96).max) revert InsufficientStake();

        voteCommitments[votingID][msg.sender] = VoteCommitment({
            commitHash: commitHash,
            commitTime: uint64(block.timestamp),
            revealed: false,
            stake: uint96(stakeAmount)
        });

        userTotalStake[msg.sender] += stakeAmount;
        userActiveVotes[msg.sender].push(votingID);

        emit VoteCommitted(votingID, msg.sender, stakeAmount);
    }

    // =============================================================================
    //                              REVEAL PHASE
    // =============================================================================
    /**
     * @notice Reveal a previously committed vote
     * @dev Must be called during reveal phase (commitRevealWindow to endTime)
     * @param votingID The voting ID
     * @param vote The actual vote (true = spec valid, false = spec invalid)
     * @param salt The salt used when creating the commit hash
     */
    function revealVote(
        bytes32 votingID,
        bool vote,
        bytes32 salt
    ) external nonReentrant whenNotPaused {
        SpecVoting storage voting = specVotings[votingID];
        VoteCommitment storage commitment = voteCommitments[votingID][msg.sender];

        if (voting.startTime == 0) revert VotingNotFound();
        if (block.timestamp < voting.startTime + commitRevealWindow) revert RevealPhaseNotStarted();
        if (block.timestamp >= voting.endTime) revert VotingEnded();
        if (commitment.commitTime == 0) revert NoCommitmentFound();
        if (commitment.revealed) revert AlreadyRevealed();

        // Verify the commitment hash
        bytes32 expectedHash = keccak256(abi.encodePacked(vote, salt));
        if (expectedHash != commitment.commitHash) revert InvalidReveal();

        // Mark as revealed
        commitment.revealed = true;

        // Record the vote
        voterRecords[votingID][msg.sender] = VoterRecord({
            vote: vote,
            stake: commitment.stake,
            claimed: false
        });

        // Update tallies
        if (vote) {
            voting.totalStakeFor += commitment.stake;
        } else {
            voting.totalStakeAgainst += commitment.stake;
        }
        voting.voterCount++;

        emit VoteRevealed(votingID, msg.sender, vote, commitment.stake);
    }

    // =============================================================================
    //                              FINALIZATION
    // =============================================================================
    /**
     * @notice Finalize a voting round and determine the result
     * @dev Anyone can call this after voting ends and if minimum stake threshold is met
     * @param votingID The voting ID to finalize
     * @return result The voting result (true = spec accepted, false = rejected)
     */
    function finalizeVoting(bytes32 votingID) external nonReentrant whenNotPaused returns (bool result) {
        SpecVoting storage voting = specVotings[votingID];

        if (voting.startTime == 0) revert VotingNotFound();
        if (block.timestamp < voting.endTime) revert VotingNotEnded();
        if (voting.finalized) revert AlreadyFinalized();

        uint256 totalStake = uint256(voting.totalStakeFor) + uint256(voting.totalStakeAgainst);
        if (totalStake < minTotalStakeThreshold) revert InsufficientTotalStake();

        // Determine result by majority stake
        // In case of tie, spec is rejected (conservative approach)
        voting.result = voting.totalStakeFor > voting.totalStakeAgainst;
        voting.finalized = true;

        emit VotingFinalized(
            votingID,
            voting.result,
            voting.totalStakeFor,
            voting.totalStakeAgainst,
            voting.voterCount
        );

        return voting.result;
    }

    // =============================================================================
    //                              CLAIMS
    // =============================================================================
    /**
     * @notice Claim rewards for voting with the majority
     * @dev Winners get their stake back plus NEWLY MINTED inflation rewards
     *      Must wait until challenge window passes unless stake is not locked
     * @param votingID The voting ID to claim rewards from
     */
    function claimRewards(bytes32 votingID) external nonReentrant whenNotPaused {
        SpecVoting storage voting = specVotings[votingID];
        VoterRecord storage record = voterRecords[votingID][msg.sender];

        if (!voting.finalized) revert NotFinalized();
        if (record.stake == 0) revert NoStake();
        if (record.claimed) revert AlreadyClaimed();
        if (record.vote != voting.result) revert VotedWithMinority();

        // Check if stake is locked for a challenge
        if (stakeLocked[votingID][msg.sender]) revert StakeLocked();

        // Must wait until challenge window passes
        if (block.timestamp < voting.endTime + CHALLENGE_WINDOW) revert ChallengeWindowNotPassed();

        record.claimed = true;
        userTotalStake[msg.sender] -= record.stake;

        // Calculate inflation reward: stake * reward rate
        // Each winner gets their proportional share based on their stake
        uint256 userReward = (uint256(record.stake) * voting.rewardRateBps) / 10000;

        // Return original stake
        bool transferSuccess = kaiToken.transfer(msg.sender, record.stake);
        if (!transferSuccess) revert TransferFailed();

        // MINT new tokens as reward (inflation)
        if (userReward > 0) {
            kaiToken.mint(msg.sender, userReward);
        }

        uint256 totalPayout = record.stake + userReward;

        emit RewardsClaimed(votingID, msg.sender, record.stake, userReward, totalPayout);
    }

    /**
     * @notice Withdraw stake for minority voters (no penalty)
     * @dev Losers get their full stake back - NO slashing
     *      Must wait until challenge window passes unless stake is not locked
     * @param votingID The voting ID to withdraw from
     */
    function withdrawStake(bytes32 votingID) external nonReentrant whenNotPaused {
        SpecVoting storage voting = specVotings[votingID];
        VoterRecord storage record = voterRecords[votingID][msg.sender];

        if (!voting.finalized) revert NotFinalized();
        if (record.stake == 0) revert NoStake();
        if (record.claimed) revert AlreadyClaimed();
        if (record.vote == voting.result) revert VotedWithMajority();

        // Check if stake is locked for a challenge
        if (stakeLocked[votingID][msg.sender]) revert StakeLocked();

        // Must wait until challenge window passes
        if (block.timestamp < voting.endTime + CHALLENGE_WINDOW) revert ChallengeWindowNotPassed();

        record.claimed = true;
        userTotalStake[msg.sender] -= record.stake;

        // Return FULL stake - NO slashing penalty
        bool success = kaiToken.transfer(msg.sender, record.stake);
        if (!success) revert TransferFailed();

        emit StakeWithdrawn(votingID, msg.sender, record.stake);
    }

    /**
     * @notice Withdraw uncommitted stake if vote was not revealed
     * @dev For users who committed but failed to reveal - they still get stake back
     *      Must wait until challenge window passes
     * @param votingID The voting ID
     */
    function withdrawUnrevealedStake(bytes32 votingID) external nonReentrant whenNotPaused {
        SpecVoting storage voting = specVotings[votingID];
        VoteCommitment storage commitment = voteCommitments[votingID][msg.sender];

        if (!voting.finalized) revert NotFinalized();
        if (commitment.commitTime == 0) revert NoCommitmentFound();
        if (commitment.revealed) revert AlreadyRevealed();

        // Check if already processed
        VoterRecord storage record = voterRecords[votingID][msg.sender];
        if (record.claimed) revert AlreadyClaimed();

        // Check if stake is locked for a challenge
        if (stakeLocked[votingID][msg.sender]) revert StakeLocked();

        // Must wait until challenge window passes
        if (block.timestamp < voting.endTime + CHALLENGE_WINDOW) revert ChallengeWindowNotPassed();

        // Mark as claimed to prevent double withdrawal
        record.claimed = true;
        record.stake = commitment.stake;

        userTotalStake[msg.sender] -= commitment.stake;

        // Return stake even for unrevealed votes (no punishment model)
        // They just miss out on rewards - opportunity cost is enough
        bool success = kaiToken.transfer(msg.sender, commitment.stake);
        if (!success) revert TransferFailed();

        emit StakeWithdrawn(votingID, msg.sender, commitment.stake);
    }

    // =============================================================================
    //                              VIEW FUNCTIONS
    // =============================================================================
    /**
     * @notice Get the voting result for a spec
     * @param votingID The voting ID
     * @return finalized Whether voting is finalized
     * @return result The result (true = accepted, false = rejected)
     */
    function getVotingResult(bytes32 votingID) external view returns (bool finalized, bool result) {
        SpecVoting storage voting = specVotings[votingID];
        return (voting.finalized, voting.result);
    }

    /**
     * @notice Get detailed voting information
     * @param votingID The voting ID
     */
    function getVotingDetails(bytes32 votingID) external view returns (
        bool finalized,
        bool result,
        uint256 totalStakeFor,
        uint256 totalStakeAgainst,
        uint256 endTime,
        uint32 voterCount,
        bytes32 specID
    ) {
        SpecVoting storage voting = specVotings[votingID];
        return (
            voting.finalized,
            voting.result,
            voting.totalStakeFor,
            voting.totalStakeAgainst,
            voting.endTime,
            voting.voterCount,
            voting.specID
        );
    }

    /**
     * @notice Get user's commitment for a voting round
     * @param votingID The voting ID
     * @param voter The voter address
     */
    function getUserCommitment(bytes32 votingID, address voter) external view returns (
        bytes32 commitHash,
        uint64 commitTime,
        bool revealed,
        uint96 stake
    ) {
        VoteCommitment storage commitment = voteCommitments[votingID][voter];
        return (
            commitment.commitHash,
            commitment.commitTime,
            commitment.revealed,
            commitment.stake
        );
    }

    /**
     * @notice Get user's vote record after reveal
     * @param votingID The voting ID
     * @param voter The voter address
     */
    function getUserVoteRecord(bytes32 votingID, address voter) external view returns (
        bool vote,
        uint96 stake,
        bool claimed
    ) {
        VoterRecord storage record = voterRecords[votingID][voter];
        return (record.vote, record.stake, record.claimed);
    }

    /**
     * @notice Get all active voting IDs for a user
     * @param user The user address
     */
    function getUserActiveVotes(address user) external view returns (bytes32[] memory) {
        return userActiveVotes[user];
    }

    /**
     * @notice Check if we're in commit phase
     * @param votingID The voting ID
     */
    function isCommitPhase(bytes32 votingID) external view returns (bool) {
        SpecVoting storage voting = specVotings[votingID];
        return block.timestamp >= voting.startTime &&
               block.timestamp < voting.startTime + commitRevealWindow;
    }

    /**
     * @notice Check if we're in reveal phase
     * @param votingID The voting ID
     */
    function isRevealPhase(bytes32 votingID) external view returns (bool) {
        SpecVoting storage voting = specVotings[votingID];
        return block.timestamp >= voting.startTime + commitRevealWindow &&
               block.timestamp < voting.endTime;
    }

    /**
     * @notice Calculate potential reward for a winner
     * @param votingID The voting ID
     * @param stakeAmount The stake amount to calculate reward for
     */
    function calculatePotentialReward(bytes32 votingID, uint256 stakeAmount) external view returns (uint256) {
        SpecVoting storage voting = specVotings[votingID];

        // User reward = stake * reward rate in bps / 10000
        return (stakeAmount * voting.rewardRateBps) / 10000;
    }

    /**
     * @notice Get the reward rate for a voting round
     * @param votingID The voting ID
     */
    function getRewardRate(bytes32 votingID) external view returns (uint16) {
        return specVotings[votingID].rewardRateBps;
    }

    /**
     * @notice Check if stake is locked for a user in a voting
     * @param votingID The voting ID
     * @param actor The user address
     */
    function isStakeLocked(bytes32 votingID, address actor) external view returns (bool) {
        return stakeLocked[votingID][actor];
    }

    /**
     * @notice Check if challenge window has passed for a voting
     * @param votingID The voting ID
     */
    function isChallengeWindowPassed(bytes32 votingID) external view returns (bool) {
        SpecVoting storage voting = specVotings[votingID];
        if (!voting.finalized) return false;
        return block.timestamp >= voting.endTime + CHALLENGE_WINDOW;
    }

    // =============================================================================
    //                           SLASHING FUNCTIONS
    // =============================================================================
    /**
     * @notice Initiate voting for a challenge (called by KAISlashing)
     * @dev Creates a new voting round specifically for challenge resolution
     * @param challengeID The challenge ID (used as specID)
     * @param votingDuration Duration of voting
     * @param rewardRateBps Reward rate (typically 0 for challenge votes)
     * @return votingID The voting ID for the challenge
     */
    function initiateVotingForChallenge(
        bytes32 challengeID,
        uint32 votingDuration,
        uint16 rewardRateBps
    ) external onlySlashing whenNotPaused returns (bytes32 votingID) {
        if (rewardRateBps > MAX_REWARD_RATE_BPS) revert InvalidRewardRate();
        if (votingDuration < MIN_VOTING_PERIOD || votingDuration > MAX_VOTING_PERIOD) revert InvalidDuration();

        votingID = keccak256(abi.encodePacked(challengeID, block.timestamp, msg.sender, "CHALLENGE"));

        specVotings[votingID] = SpecVoting({
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + votingDuration),
            totalStakeFor: 0,
            totalStakeAgainst: 0,
            rewardRateBps: rewardRateBps,
            finalized: false,
            result: false,
            voterCount: 0,
            specID: challengeID
        });

        emit VotingInitiated(votingID, challengeID, uint64(block.timestamp + votingDuration), rewardRateBps);
        return votingID;
    }

    /**
     * @notice Lock a user's stake for a pending challenge
     * @dev Called by KAISlashing when a challenge is initiated
     * @param votingID The voting ID where the actor participated
     * @param actor The actor being challenged
     */
    function lockStakeForChallenge(bytes32 votingID, address actor) external onlySlashing {
        SpecVoting storage voting = specVotings[votingID];
        if (voting.startTime == 0) revert VotingNotFound();
        if (!voting.finalized) revert NotFinalized();

        // Verify actor has stake
        VoterRecord storage record = voterRecords[votingID][actor];
        if (record.stake == 0) revert NoStake();
        if (record.claimed) revert AlreadyClaimed();

        stakeLocked[votingID][actor] = true;

        emit StakeLockedForChallenge(votingID, actor);
    }

    /**
     * @notice Unlock a user's stake after a challenge fails
     * @dev Called by KAISlashing when challenge is resolved as failed
     * @param votingID The voting ID
     * @param actor The actor whose stake should be unlocked
     */
    function unlockStake(bytes32 votingID, address actor) external onlySlashing {
        if (!stakeLocked[votingID][actor]) revert StakeNotLocked();

        stakeLocked[votingID][actor] = false;

        emit StakeUnlocked(votingID, actor);
    }

    /**
     * @notice Execute slashing on an actor's stake
     * @dev Called by KAISlashing when a challenge succeeds
     * @param votingID The voting ID
     * @param actor The actor to slash
     * @param slashAmount Amount to slash from their stake
     */
    function executeSlash(
        bytes32 votingID,
        address actor,
        uint256 slashAmount
    ) external onlySlashing nonReentrant {
        SpecVoting storage voting = specVotings[votingID];
        VoterRecord storage record = voterRecords[votingID][actor];

        if (voting.startTime == 0) revert VotingNotFound();
        if (!voting.finalized) revert NotFinalized();
        if (!stakeLocked[votingID][actor]) revert StakeNotLocked();
        if (record.stake == 0) revert NoStake();
        if (record.claimed) revert AlreadyClaimed();

        // Mark as claimed and unlock
        record.claimed = true;
        stakeLocked[votingID][actor] = false;
        userTotalStake[actor] -= record.stake;

        // Calculate remaining stake after slash
        uint256 remainingStake = record.stake > slashAmount ? record.stake - slashAmount : 0;

        // Transfer slashed amount to KAISlashing contract for distribution
        if (slashAmount > 0) {
            bool slashSuccess = kaiToken.transfer(msg.sender, slashAmount);
            if (!slashSuccess) revert TransferFailed();
        }

        // Return remaining stake to actor
        if (remainingStake > 0) {
            bool returnSuccess = kaiToken.transfer(actor, remainingStake);
            if (!returnSuccess) revert TransferFailed();
        }

        emit StakeSlashed(votingID, actor, slashAmount);
    }

    // =============================================================================
    //                              ADMIN FUNCTIONS
    // =============================================================================
    /**
     * @notice Set the KaiSign contract address
     * @dev Can only be called once to set the KaiSign contract
     * @param kaisign The KaiSign contract address
     */
    function setKaiSignContract(address kaisign) external onlyAdmin {
        if (kaisign == address(0)) revert ZeroAddress();
        _grantRole(KAISIGN_ROLE, kaisign);
    }

    /**
     * @notice Set the KAISlashing contract address
     * @param slashing The KAISlashing contract address
     */
    function setSlashingContract(address slashing) external onlyAdmin {
        if (slashing == address(0)) revert ZeroAddress();
        _grantRole(SLASHING_ROLE, slashing);
    }

    /**
     * @notice Update the default voting period
     * @param newPeriod New voting period in seconds
     */
    function setDefaultVotingPeriod(uint32 newPeriod) external onlyAdmin {
        if (newPeriod < MIN_VOTING_PERIOD || newPeriod > MAX_VOTING_PERIOD) revert InvalidDuration();
        emit ParameterUpdated("defaultVotingPeriod", defaultVotingPeriod, newPeriod);
        defaultVotingPeriod = newPeriod;
    }

    /**
     * @notice Update the commit-reveal window
     * @param newWindow New commit window in seconds
     */
    function setCommitRevealWindow(uint32 newWindow) external onlyAdmin {
        if (newWindow < MIN_COMMIT_WINDOW || newWindow > MAX_COMMIT_WINDOW) revert InvalidDuration();
        emit ParameterUpdated("commitRevealWindow", commitRevealWindow, newWindow);
        commitRevealWindow = newWindow;
    }

    /**
     * @notice Update the default reward rate
     * @param newRateBps New reward rate in basis points
     */
    function setDefaultRewardRateBps(uint16 newRateBps) external onlyAdmin {
        if (newRateBps > MAX_REWARD_RATE_BPS) revert InvalidRewardRate();
        emit ParameterUpdated("defaultRewardRateBps", defaultRewardRateBps, newRateBps);
        defaultRewardRateBps = newRateBps;
    }

    /**
     * @notice Update minimum stake per vote
     * @param newMinStake New minimum stake amount
     */
    function setMinStakePerVote(uint256 newMinStake) external onlyAdmin {
        if (newMinStake == 0) revert InsufficientStake();
        emit ParameterUpdated("minStakePerVote", minStakePerVote, newMinStake);
        minStakePerVote = newMinStake;
    }

    /**
     * @notice Update minimum total stake threshold
     * @param newThreshold New threshold amount
     */
    function setMinTotalStakeThreshold(uint256 newThreshold) external onlyAdmin {
        if (newThreshold < minStakePerVote) revert InsufficientStake();
        emit ParameterUpdated("minTotalStakeThreshold", minTotalStakeThreshold, newThreshold);
        minTotalStakeThreshold = newThreshold;
    }

    /**
     * @notice Extend voting period for a specific vote (emergency only)
     * @param votingID The voting ID
     * @param extension Additional time in seconds
     */
    function extendVoting(bytes32 votingID, uint32 extension) external onlyAdmin {
        SpecVoting storage voting = specVotings[votingID];
        if (voting.startTime == 0) revert VotingNotFound();
        if (voting.finalized) revert AlreadyFinalized();
        if (extension > MAX_VOTING_PERIOD) revert InvalidDuration();

        voting.endTime += extension;
        emit VotingExtended(votingID, extension);
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
