// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {RealityETH_v3_0} from "../staticlib/RealityETH-3.0.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract KaiSign is ReentrancyGuard, AccessControl, Pausable {

    // =============================================================================
    //                                CUSTOM ERRORS
    // =============================================================================
    error AlreadyProposed();
    error NotProposed();
    error InsufficientBond();
    error InsufficientIncentive();
    error InvalidContract();
    error ContractNotFound();
    error CommitmentNotFound();
    error CommitmentExpired();
    error CommitmentAlreadyRevealed();
    error InvalidReveal();
    error NotFinalized();
    error AlreadySettled();
    error NoIncentiveToClaim();
    error IncentiveExpired();
    error Unauthorized();
    error ClawbackTooEarly();

    // =============================================================================
    //                                   ROLES
    // =============================================================================
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // =============================================================================
    //                                CONSTANTS
    // =============================================================================
    string public constant VERSION = "1.0.0";
    uint256 public constant PLATFORM_FEE_PERCENT = 5; // 5%
    uint256 public constant COMMIT_REVEAL_TIMEOUT = 1 hours;
    uint256 public constant INCENTIVE_DURATION = 30 days;
    uint256 public constant INCENTIVE_CLAWBACK_PERIOD = 90 days; // 3 months
    uint32 public constant DEFAULT_TIMEOUT = 48 hours; // 48 hours for Reality.eth questions

    // =============================================================================
    //                              STATE VARIABLES
    // =============================================================================
    address public immutable realityETH;
    address public immutable arbitrator;
    address public immutable treasury;
    uint256 public minBond;
    uint256 public templateId;
    
    // Blob hash storage only
    mapping(bytes32 => bytes32) public specBlobHash;
    
    // Commit-reveal mechanism
    mapping(bytes32 => CommitData) public commitments;
    
    // Contract address integration with chain support
    mapping(uint256 => mapping(address => bytes32[])) public contractSpecs;
    mapping(uint256 => mapping(address => uint256)) public contractSpecCount;
    
    // Incentive system
    mapping(bytes32 => IncentiveData) public incentives;
    mapping(address => bytes32[]) public userIncentives;
    mapping(uint256 => mapping(address => uint256)) public incentivePool;
    mapping(uint256 => mapping(address => uint256)) public poolContributorCount;
    
    // Spec management
    mapping(bytes32 => ERC7730Spec) public specs;
    mapping(bytes32 => mapping(address => uint256)) public userBonds;
    
    // =============================================================================
    //                                   ENUMS
    // =============================================================================
    enum Status {
        Committed,    // Commitment submitted, waiting for reveal
        Submitted,    // Revealed and submitted, waiting for proposal
        Proposed,     // Question created on Reality.eth
        Finalized,    // Final result determined
        Cancelled     // Cancelled/invalid
    }

    // =============================================================================
    //                                 STRUCTS
    // =============================================================================
    
    // Optimized struct packing for gas efficiency
    struct ERC7730Spec {
        uint64 createdTimestamp;    // 8 bytes
        uint64 proposedTimestamp;   // 8 bytes  
        Status status;              // 1 byte
        uint80 totalBonds;          // 10 bytes (up to ~1.2M ETH)
        uint32 reserved;            // 4 bytes - reserved for future use
        // SLOT 1: 32 bytes total (perfectly packed!)
        
        address creator;            // 20 bytes  
        address targetContract;     // 20 bytes - contract this spec validates
        // SLOT 2: 40 bytes - needs 2 slots but efficiently packed
        
        bytes32 blobHash;          // 32 bytes - EIP-4844 blob hash for ERC7730 JSON
        bytes32 questionId;        // 32 bytes - full slot
        bytes32 incentiveId;       // 32 bytes - linked incentive if any
        uint256 chainId;           // 32 bytes - target chain ID
        // SLOTS 3+: Only when spec has blobHash/questionId/incentiveId/chainId
    }

    struct CommitData {
        address committer;          // 20 bytes
        uint64 commitTimestamp;     // 8 bytes
        uint32 reserved1;           // 4 bytes - reserved for future use
        // SLOT 1: 32 bytes total (perfectly packed!)
        
        address targetContract;     // 20 bytes
        bool isRevealed;            // 1 byte
        uint80 bondAmount;          // 10 bytes (up to 1.2M ETH)
        uint8 reserved;             // 1 byte - for alignment
        // SLOT 2: 32 bytes total (perfectly packed!)
        
        uint64 revealDeadline;      // 8 bytes (safe until year 2554)
        uint256 chainId;            // 32 bytes - target chain ID
        bytes32 incentiveId;        // 32 bytes - if incentivized
        // SLOTS 3-4: Chain ID and incentive data
    }

    struct IncentiveData {
        address creator;            // 20 bytes
        uint80 amount;              // 10 bytes (up to ~1.2M ETH)
        uint16 reserved1;           // 2 bytes - reserved for future use
        // SLOT 1: 32 bytes total (perfectly packed!)
        
        uint64 deadline;            // 8 bytes
        uint64 createdAt;           // 8 bytes
        address targetContract;     // 20 bytes - truncated to 16 bytes
        // SLOT 2: 36 bytes - needs 2 slots
        
        bool isClaimed;             // 1 byte
        bool isActive;              // 1 byte
        uint256 chainId;            // 32 bytes - target chain ID
        // SLOT 3: Chain ID and flags
        
        string description;         // Dynamic - separate slots when needed
        // SLOT 4+: Description when exists
    }

    // =============================================================================
    //                                  EVENTS
    // =============================================================================
    event LogCommitSpec(
        address indexed committer,
        bytes32 indexed commitmentId,
        address indexed targetContract,
        uint256 chainId,
        uint256 bondAmount,
        uint64 revealDeadline
    );

    event LogRevealSpec(
        address indexed creator,
        bytes32 indexed specID,
        bytes32 indexed blobHash,
        bytes32 commitmentId,
        address targetContract,
        uint256 chainId
    );

    event LogCreateSpec(
        address indexed creator,
        bytes32 indexed specID,
        bytes32 indexed blobHash,
        address targetContract,
        uint256 chainId,
        uint256 timestamp,
        bytes32 incentiveId
    );

    event LogProposeSpec(
        address indexed user,
        bytes32 indexed specID,
        bytes32 questionId,
        uint256 bond
    );

    // The following events related to spec assertion have been removed.
    // Originally, KaiSign allowed anyone to top up a spec’s bond and vote on the outcome
    // through `assertSpecValid` and `assertSpecInvalid`. Those functions (and their
    // associated events) have been removed to simplify the contract and rely solely on
    // Reality.eth’s native bond mechanism.

    event LogHandleResult(
        bytes32 indexed specID,
        bool isAccepted
    );


    event LogIncentiveCreated(
        bytes32 indexed incentiveId,
        address indexed creator,
        address indexed targetContract,
        uint256 chainId,
        uint256 amount,
        uint64 deadline,
        string description
    );

    event LogIncentiveClaimed(
        bytes32 indexed incentiveId,
        address indexed claimer,
        bytes32 indexed specID,
        uint256 amount
    );

    event LogIncentiveClawback(
        bytes32 indexed incentiveId,
        address indexed creator,
        uint256 amount
    );

    event LogContractSpecAdded(
        address indexed targetContract,
        bytes32 indexed specID,
        address indexed creator,
        uint256 chainId,
        bytes32 blobHash
    );

    event LogEmergencyPause(address indexed admin);
    event LogEmergencyUnpause(address indexed admin);

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
    constructor(
        address _realityETH,
        address _arbitrator,
        address _treasury,
        uint256 _minBond,
        address[] memory _initialAdmins
    ) {
        if (_realityETH == address(0)) revert InvalidContract();
        if (_arbitrator == address(0)) revert InvalidContract();
        if (_treasury == address(0)) revert InvalidContract();
        if (_initialAdmins.length == 0) revert Unauthorized();

        realityETH = _realityETH;
        arbitrator = _arbitrator;
        treasury = _treasury;
        minBond = _minBond;

        // Set up initial admins
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i = 0; i < _initialAdmins.length; i++) {
            _grantRole(ADMIN_ROLE, _initialAdmins[i]);
        }

        // Create Reality.eth template
        templateId = RealityETH_v3_0(realityETH).createTemplate(
            '{"title": "Is the ERC7730 specification %s for contract %s on chain %s correct?", "type": "bool", "category": "misc"}'
        );
    }

    // =============================================================================
    //                              ADMIN FUNCTIONS
    // =============================================================================
    
    function setMinBond(uint256 _minBond) external onlyAdmin {
        minBond = _minBond;
    }


    function addAdmin(address newAdmin) external onlyAdmin {
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    function removeAdmin(address admin) external onlyAdmin {
        _revokeRole(ADMIN_ROLE, admin);
    }

    // Emergency pause/unpause - any admin can trigger
    function emergencyPause() external onlyAdmin {
        _pause();
        emit LogEmergencyPause(msg.sender);
    }

    function emergencyUnpause() external onlyAdmin {
        _unpause();
        emit LogEmergencyUnpause(msg.sender);
    }

    // =============================================================================
    //                           INCENTIVE SYSTEM
    // =============================================================================
    
    function createIncentive(
        address targetContract,
        uint256 targetChainId,
        uint256 amount,
        uint64 duration,
        string calldata description
    ) external payable nonReentrant whenNotPaused returns (bytes32 incentiveId) {
        if (targetContract == address(0)) revert InvalidContract();
        if (targetChainId == 0) revert InvalidContract();
        if (amount > type(uint80).max) revert InsufficientIncentive(); // Prevent overflow
        if (duration == 0 || duration > 30 days) revert IncentiveExpired();
        
        // ETH incentive only
        if (msg.value < amount) revert InsufficientIncentive();
        // Refund excess ETH
        if (msg.value > amount) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - amount}("");
            require(success, "Excess ETH refund failed");
        }
        
        incentiveId = keccak256(abi.encodePacked(
            msg.sender,
            targetContract,
            targetChainId,
            amount,
            block.timestamp,
            description
        ));

        incentives[incentiveId] = IncentiveData({
            creator: msg.sender,
            amount: uint80(amount),
            reserved1: 0,
            deadline: uint64(block.timestamp + duration),
            createdAt: uint64(block.timestamp),
            targetContract: targetContract,
            isClaimed: false,
            isActive: true,
            chainId: targetChainId,
            description: description
        });

        userIncentives[msg.sender].push(incentiveId);
        incentivePool[targetChainId][targetContract] += amount;
        poolContributorCount[targetChainId][targetContract]++;

        emit LogIncentiveCreated(
            incentiveId,
            msg.sender,
            targetContract,
            targetChainId,
            amount,
            uint64(block.timestamp + duration),
            description
        );
    }

    // =============================================================================
    //                           COMMIT-REVEAL PATTERN
    // =============================================================================
    
    function commitSpec(
        bytes32 commitment,
        address targetContract,
        uint256 targetChainId
    ) external nonReentrant whenNotPaused {
        if (targetContract == address(0)) revert InvalidContract();
        if (targetChainId == 0) revert InvalidContract();
        // This function is intentionally non-payable. Any Ether sent with this call will
        // cause the transaction to revert before reaching this code. Bonds must be
        // supplied during the reveal step, not at commit time.

        uint64 currentTime = uint64(block.timestamp);

        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment,
            msg.sender,
            targetContract,
            targetChainId,
            currentTime
        ));

        // Store the commitment with zero bond. The bond will be provided at reveal time.
        commitments[commitmentId] = CommitData({
            committer: msg.sender,
            commitTimestamp: currentTime,
            reserved1: 0,
            targetContract: targetContract,
            isRevealed: false,
            bondAmount: 0,
            reserved: 0,
            revealDeadline: currentTime + uint64(COMMIT_REVEAL_TIMEOUT),
            chainId: targetChainId,
            incentiveId: bytes32(0)
        });

        emit LogCommitSpec(
            msg.sender,
            commitmentId,
            targetContract,
            targetChainId,
            0,
            currentTime + uint64(COMMIT_REVEAL_TIMEOUT)
        );
    }

    function revealSpec(
        bytes32 commitmentId,
        bytes32 blobHash,
        bytes32 metadataHash,
        uint256 nonce
    ) external payable nonReentrant whenNotPaused returns (bytes32 specID) {
        return _revealSpecInternal(commitmentId, blobHash, metadataHash, nonce);
    }
    
    
    function _revealSpecInternal(
        bytes32 commitmentId,
        bytes32 blobHash,
        bytes32 metadataHash,
        uint256 nonce
    ) internal returns (bytes32 specID) {
        CommitData storage commitment = commitments[commitmentId];
        
        if (commitment.committer == address(0)) revert CommitmentNotFound();
        if (commitment.committer != msg.sender) revert InvalidReveal();
        if (commitment.isRevealed) revert CommitmentAlreadyRevealed();
        // If the commit has expired, no reveal is allowed.
        if (block.timestamp > commitment.revealDeadline) revert CommitmentExpired();
        // Blob hash is mandatory for EIP-4844 blob reference
        if (blobHash == bytes32(0)) revert InvalidReveal();
        
        // Collect the bond at reveal time. Require it meets the minimum bond.
        // No platform fee is deducted - the full amount goes to the spec.
        if (msg.value < minBond) revert InsufficientBond();
        uint256 netBondAmount = msg.value;
        // Prevent overflow when storing into uint80
        if (netBondAmount > type(uint80).max) revert InsufficientBond();
        // Record the bond on the commitment. This replaces any bond recorded during commit.
        commitment.bondAmount = uint80(netBondAmount);

        // Verify commitment: use metadataHash instead of blobHash for verification
        bytes32 expectedCommitment = keccak256(abi.encodePacked(metadataHash, nonce));
        bytes32 reconstructedCommitmentId = keccak256(abi.encodePacked(
            expectedCommitment,
            commitment.committer,
            commitment.targetContract,
            commitment.chainId,
            commitment.commitTimestamp
        ));

        if (reconstructedCommitmentId != commitmentId) revert InvalidReveal();

        // Create spec ID
        specID = keccak256(abi.encodePacked(
            blobHash,
            commitment.targetContract,
            commitment.chainId,
            msg.sender,
            commitment.commitTimestamp
        ));

        if (specs[specID].createdTimestamp != 0) revert AlreadyProposed();

        // Mark commitment as revealed
        commitment.isRevealed = true;

        // Create spec and store ERC7730 JSON
        specs[specID] = ERC7730Spec({
            createdTimestamp: uint64(block.timestamp),
            proposedTimestamp: 0,
            status: Status.Submitted,
            totalBonds: uint80(commitment.bondAmount),
            reserved: 0,
            creator: msg.sender,
            targetContract: commitment.targetContract,
            blobHash: blobHash,
            questionId: bytes32(0),
            incentiveId: bytes32(0),
            chainId: commitment.chainId
        });
        
        // Store the blob hash
        specBlobHash[specID] = blobHash;

        // Index by contract and chain
        contractSpecs[commitment.chainId][commitment.targetContract].push(specID);
        contractSpecCount[commitment.chainId][commitment.targetContract]++;

        emit LogRevealSpec(
            msg.sender,
            specID,
            blobHash,
            commitmentId,
            commitment.targetContract,
            commitment.chainId
        );

        emit LogCreateSpec(
            msg.sender,
            specID,
            blobHash,
            commitment.targetContract,
            commitment.chainId,
            block.timestamp,
            bytes32(0)
        );

        emit LogContractSpecAdded(
            commitment.targetContract,
            specID,
            msg.sender,
            commitment.chainId,
            blobHash
        );

        // Auto-propose if enough bond was provided
        if (commitment.bondAmount >= minBond) {
            _proposeSpec(specID, true);
        }

        // No platform fee is collected for spec submissions
        return specID;
    }

    // =============================================================================
    //                              SPEC MANAGEMENT
    // =============================================================================
    
    function proposeSpec(bytes32 specID) external payable nonReentrant whenNotPaused {
        _proposeSpec(specID, false);
    }

    function _proposeSpec(bytes32 specID, bool isInternalCall) internal {
        ERC7730Spec storage spec = specs[specID];
        if (spec.createdTimestamp == 0) revert NotProposed();
        if (spec.status != Status.Submitted) revert AlreadyProposed();

        uint256 additionalBond;
        uint256 totalBond;
        
        if (isInternalCall) {
            // Called from revealSpec - no additional bond, use existing totalBonds
            additionalBond = 0;
            totalBond = spec.totalBonds;
        } else {
            // Called from proposeSpec - msg.value is additional bond
            additionalBond = msg.value;
            totalBond = spec.totalBonds + additionalBond;
        }
        
        if (totalBond < minBond) revert InsufficientBond();
        if (totalBond > type(uint80).max) revert InsufficientBond(); // Prevent overflow

        // EFFECTS: update state before external interactions
        spec.status = Status.Proposed;
        spec.proposedTimestamp = uint64(block.timestamp);
        spec.totalBonds = uint80(totalBond);
        // Track the entire amount credited to the spec for this user
        if (additionalBond > 0) {
            userBonds[specID][msg.sender] += additionalBond;
        }

        // INTERACTIONS: create Reality.eth question using the total bond
        string memory delim = unicode"␟";
        string memory questionParams = string(abi.encodePacked(
            _bytes32ToString(spec.blobHash),
            delim,
            _addressToString(spec.targetContract),
            delim,
            _uint256ToString(spec.chainId)
        ));

        spec.questionId = RealityETH_v3_0(realityETH).askQuestionWithMinBond{value: totalBond}(
            templateId,
            questionParams,
            arbitrator,
            DEFAULT_TIMEOUT,
            0,
            0,
            minBond
        );

        emit LogProposeSpec(msg.sender, specID, spec.questionId, totalBond);

    }


    function handleResult(bytes32 specID) external nonReentrant whenNotPaused {
        ERC7730Spec storage spec = specs[specID];
        if (spec.status != Status.Proposed) revert NotProposed();

        // Check if Reality.eth question is finalized
        if (!RealityETH_v3_0(realityETH).isFinalized(spec.questionId)) revert NotFinalized();

        bytes32 result = RealityETH_v3_0(realityETH).resultFor(spec.questionId);
        bool specAccepted = uint256(result) == 1;

        spec.status = Status.Finalized;
        emit LogHandleResult(specID, specAccepted);

        if (specAccepted) {
            // Blob hash is stored in the contract
            // Metadata is in the blob sidecar referenced by blobHash
            
            // Claim from the incentive pool for this contract/chain
            uint256 poolAmount = incentivePool[spec.chainId][spec.targetContract];
            if (poolAmount > 0) {
                incentivePool[spec.chainId][spec.targetContract] = 0;
                _claimFromPool(poolAmount, specID, spec.creator);
            }
        }
    }

    function _claimIncentive(bytes32 incentiveId, bytes32 specID, address claimer) internal {
        IncentiveData storage incentive = incentives[incentiveId];
        if (incentive.isClaimed || !incentive.isActive) revert NoIncentiveToClaim();
        if (block.timestamp > incentive.deadline) revert IncentiveExpired();

        incentive.isClaimed = true;
        incentive.isActive = false;

        uint256 platformFee = (incentive.amount * PLATFORM_FEE_PERCENT) / 100;
        uint256 claimerAmount = incentive.amount - platformFee;

        // ETH payout only
        (bool success, ) = payable(claimer).call{value: claimerAmount}("");
        require(success, "Claimer transfer failed");
        (bool treasurySuccess, ) = treasury.call{value: platformFee, gas: 50000}("");
        require(treasurySuccess, "Treasury transfer failed");

        emit LogIncentiveClaimed(incentiveId, claimer, specID, claimerAmount);
    }

    function _claimFromPool(uint256 poolAmount, bytes32 specID, address claimer) internal {
        if (poolAmount == 0) revert NoIncentiveToClaim();

        uint256 platformFee = (poolAmount * PLATFORM_FEE_PERCENT) / 100;
        uint256 claimerAmount = poolAmount - platformFee;

        // ETH payout only
        (bool success, ) = payable(claimer).call{value: claimerAmount}("");
        require(success, "Claimer transfer failed");
        (bool treasurySuccess, ) = treasury.call{value: platformFee, gas: 50000}("");
        require(treasurySuccess, "Treasury transfer failed");

        emit LogIncentiveClaimed(bytes32(0), claimer, specID, claimerAmount);
    }

    // Allow incentive creators to reclaim funds after 3 months if unclaimed
    function clawbackIncentive(bytes32 incentiveId) external nonReentrant whenNotPaused {
        IncentiveData storage incentive = incentives[incentiveId];
        
        if (incentive.creator != msg.sender) revert Unauthorized();
        if (incentive.isClaimed || !incentive.isActive) revert NoIncentiveToClaim();
        if (block.timestamp < incentive.createdAt + INCENTIVE_CLAWBACK_PERIOD) revert ClawbackTooEarly();
        
        // Mark as inactive and claimed to prevent double-spending
        incentive.isClaimed = true;
        incentive.isActive = false;
        
        uint256 clawbackAmount = incentive.amount;
        
        // ETH clawback only - no platform fee on clawback
        (bool success, ) = payable(msg.sender).call{value: clawbackAmount}("");
        require(success, "Clawback transfer failed");

        // Reduce pool amount by clawback amount
        incentivePool[incentive.chainId][incentive.targetContract] -= clawbackAmount;
        poolContributorCount[incentive.chainId][incentive.targetContract]--;
        
        emit LogIncentiveClawback(incentiveId, msg.sender, clawbackAmount);
    }


    // =============================================================================
    //                              BOND SETTLEMENT
    // =============================================================================

    // =============================================================================
    //                              QUERY FUNCTIONS
    // =============================================================================
    
    function getSpecsByContract(address targetContract, uint256 chainId) external view returns (bytes32[] memory) {
        return contractSpecs[chainId][targetContract];
    }

    function getSpecsByContractPaginated(
        address targetContract,
        uint256 chainId,
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory specIds, uint256 total) {
        bytes32[] storage allSpecs = contractSpecs[chainId][targetContract];
        total = allSpecs.length;
        
        if (offset >= total) {
            return (new bytes32[](0), total);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        specIds = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            specIds[i - offset] = allSpecs[i];
        }
    }

    function getContractSpecCount(address targetContract, uint256 chainId) external view returns (uint256) {
        return contractSpecCount[chainId][targetContract];
    }

    function getUserIncentives(address user) external view returns (bytes32[] memory) {
        return userIncentives[user];
    }

    function getIncentivePool(address targetContract, uint256 chainId) external view returns (uint256 poolAmount, uint256 contributorCount) {
        return (incentivePool[chainId][targetContract], poolContributorCount[chainId][targetContract]);
    }
    
    
    function getSpecBlobHash(bytes32 specID) external view returns (bytes32) {
        return specBlobHash[specID];
    }
    

    // =============================================================================
    //                              UTILITY FUNCTIONS
    // =============================================================================
    
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint8(data[i] >> 4)];
            str[3+i*2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function _bytes32ToString(bytes32 value) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(66); // "0x" + 64 characters
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }

}
