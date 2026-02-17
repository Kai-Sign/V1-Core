// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IKaiSignRegistry} from "./interfaces/IKaiSignRegistry.sol";
import {IRealityETH} from "./interfaces/IRealityETH.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title KaiSignRegistry
 * @notice Registry for ERC7730 clear signing metadata specifications
 * @dev Single registry on L1 for all chains with Reality.eth bond escalation
 *
 * Key Features:
 * - Commit-reveal for spec submission (prevents front-running)
 * - Reality.eth for bond escalation (48h timeout, counter-bonds)
 * - chainId + extcodehash indexing (supports all chains from L1)
 * - Merkle root checkpoints with idx ordering
 * - Universe ID for fork support (EIGEN-style intersubjective forking)
 * - Only APPROVED specs are indexed in merkle tree
 */
contract KaiSignRegistry is IKaiSignRegistry, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========== CUSTOM ERRORS ==========
    error UseRevealSpecToken();
    error UseRevealSpecETH();
    error UseProposeRevokeToken();
    error UseProposeRevokeETH();
    error AttestationNotFound();
    error AlreadyRevoked();
    error InvalidExtcodehash();
    error InvalidChainId();
    error InvalidMerkleRootIdx();
    error EmptyBlobHash();
    error CommitmentNotFound();
    error CommitmentAlreadyRevealed();
    error InvalidReveal();
    error AlreadyFinalized();
    error ChallengePeriodActive();
    error NotFinalized();
    error RevokeAlreadyProposed();
    error NoRevokeProposal();
    error InvalidMerkleProof();
    error BelowMinBond();
    error EmptyMetadataHash();

    // ========== CONSTANTS ==========
    string public constant VERSION = "1.0.0";
    uint32 public constant DEFAULT_TIMEOUT = 48 hours;
    bytes32 public constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,uint256 idx,bool revoked)");

    // ========== FORK-READY: Universe tracking ==========
    uint256 public immutable override universeId;
    address public immutable override parentRegistry;
    uint64 public forkTimestamp;
    bytes32 public forkStateRoot;

    // ========== REALITY.ETH INTEGRATION ==========
    IRealityETH public immutable realityETH;      // ETH version (Phase 1)
    IRealityETH public realityETH_ERC20;          // ERC20 version (Phase 2) - set later
    address public immutable arbitrator;
    uint256 public templateId;
    uint256 public minBond;
    IERC20 public bondToken;                       // address(0) = ETH mode, otherwise bToken mode
    mapping(bytes32 => bytes32) public questionIds;        // uid => Reality.eth questionId
    mapping(bytes32 => bytes32) public revokeQuestionIds;  // uid => Reality.eth questionId for revoke

    // ========== INDEX FOR MERKLE ORDERING ==========
    uint64 public override currentIdx;

    // ========== ATTESTATION STORAGE ==========
    mapping(bytes32 => Attestation) private _attestations;

    // ========== CHAIN + EXTCODEHASH INDEXING ==========
    mapping(uint256 => mapping(bytes32 => bytes32[])) private _specsByChainAndBytecode;

    // ========== COMMIT-REVEAL ==========
    struct CommitData {
        address committer;
        uint64 commitTimestamp;
        uint256 chainId;
        bytes32 extcodehash;
        bool isRevealed;
    }
    mapping(bytes32 => CommitData) public commitments;

    // ========== MERKLE ROOT CHECKPOINT ==========
    bytes32 public override merkleRoot;
    uint64 public override merkleRootIdx;

    // ========== EVENTS ==========
    event BondTokenSet(address indexed token, address indexed realityERC20);
    event RegistryForked(uint256 indexed newUniverseId, address indexed newRegistry, bytes32 stateRoot);
    event QuestionCreated(bytes32 indexed uid, bytes32 indexed questionId, uint256 bond);
    event RevokeQuestionCreated(bytes32 indexed uid, bytes32 indexed questionId, uint256 bond);
    event LogCommitSpec(
        address indexed committer,
        bytes32 indexed commitmentId,
        uint256 chainId,
        bytes32 extcodehash
    );
    event LogRevealSpec(
        address indexed creator,
        bytes32 indexed uid,
        bytes32 indexed blobHash,
        bytes32 commitmentId,
        uint256 chainId,
        bytes32 extcodehash
    );

    // ========== CONSTRUCTOR ==========
    constructor(
        uint256 _universeId,
        address _parentRegistry,
        address _initialOwner,
        address _realityETH,
        address _arbitrator,
        uint256 _minBond
    ) {
        require(_realityETH != address(0), "Invalid Reality.eth");
        // Note: arbitrator can be address(0) - questions finalize after timeout without arbitration

        universeId = _universeId;
        parentRegistry = _parentRegistry;
        realityETH = IRealityETH(_realityETH);
        arbitrator = _arbitrator;
        minBond = _minBond;

        // Create Reality.eth template for ERC7730 spec validation
        templateId = realityETH.createTemplate(
            '{"title": "Is the ERC7730 specification %s for contract %s on chain %s correct?", "type": "bool", "category": "misc"}'
        );

        if (_initialOwner != msg.sender) {
            _transferOwnership(_initialOwner);
        }
    }

    // ========== COMMIT-REVEAL FOR SPEC SUBMISSION ==========

    /**
     * @notice Commit a spec submission (prevents front-running)
     * @param commitment Hash of (blobHash, nonce)
     * @param chainId Target chain ID
     * @param extcodehash Bytecode hash of target contract
     * @return commitmentId Unique commitment identifier
     */
    function commitSpec(
        bytes32 commitment,
        uint256 chainId,
        bytes32 extcodehash
    ) external whenNotPaused returns (bytes32 commitmentId) {
        if (chainId == 0) revert InvalidChainId();
        if (extcodehash == bytes32(0)) revert InvalidExtcodehash();

        commitmentId = keccak256(abi.encodePacked(
            commitment,
            msg.sender,
            chainId,
            extcodehash,
            block.timestamp
        ));

        commitments[commitmentId] = CommitData({
            committer: msg.sender,
            commitTimestamp: uint64(block.timestamp),
            chainId: chainId,
            extcodehash: extcodehash,
            isRevealed: false
        });

        emit LogCommitSpec(msg.sender, commitmentId, chainId, extcodehash);
    }

    /**
     * @notice Reveal a committed spec with ETH bond (Phase 1)
     * @param commitmentId The commitment to reveal
     * @param blobHash EIP-4844 blob hash containing metadata
     * @param nonce Nonce used in commitment
     * @return uid Unique attestation identifier
     */
    function revealSpec(
        bytes32 commitmentId,
        bytes32 blobHash,
        uint256 nonce,
        bytes32 metadataHash
    ) external payable nonReentrant whenNotPaused returns (bytes32 uid) {
        if (address(bondToken) != address(0)) revert UseRevealSpecToken();
        if (msg.value < minBond) revert BelowMinBond();

        uid = _revealSpec(commitmentId, blobHash, nonce, metadataHash);

        // Create Reality.eth question with ETH bond
        string memory questionParams = _buildQuestionParams(
            blobHash,
            commitments[commitmentId].extcodehash,
            commitments[commitmentId].chainId
        );

        bytes32 questionId = realityETH.askQuestionWithMinBond{value: msg.value}(
            templateId,
            questionParams,
            arbitrator,
            DEFAULT_TIMEOUT,
            0,  // opening_ts
            0,  // nonce
            minBond
        );

        questionIds[uid] = questionId;
        emit QuestionCreated(uid, questionId, msg.value);
    }

    /**
     * @notice Reveal a committed spec with bToken bond (Phase 2)
     * @dev Caller must approve bToken first
     * @param commitmentId The commitment to reveal
     * @param blobHash EIP-4844 blob hash containing metadata
     * @param nonce Nonce used in commitment
     * @param tokenAmount Amount of bToken to bond
     * @return uid Unique attestation identifier
     */
    function revealSpecToken(
        bytes32 commitmentId,
        bytes32 blobHash,
        uint256 nonce,
        bytes32 metadataHash,
        uint256 tokenAmount
    ) external nonReentrant whenNotPaused returns (bytes32 uid) {
        if (address(bondToken) == address(0)) revert UseRevealSpecETH();
        if (tokenAmount < minBond) revert BelowMinBond();

        uid = _revealSpec(commitmentId, blobHash, nonce, metadataHash);

        // Transfer bToken from user and approve Reality.eth ERC20
        bondToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
        bondToken.safeApprove(address(realityETH_ERC20), tokenAmount);

        // Create Reality.eth question with bToken bond
        string memory questionParams = _buildQuestionParams(
            blobHash,
            commitments[commitmentId].extcodehash,
            commitments[commitmentId].chainId
        );

        bytes32 questionId = realityETH_ERC20.askQuestionWithMinBondERC20(
            templateId,
            questionParams,
            arbitrator,
            DEFAULT_TIMEOUT,
            0,  // opening_ts
            0,  // nonce
            minBond,
            tokenAmount
        );

        questionIds[uid] = questionId;
        emit QuestionCreated(uid, questionId, tokenAmount);
    }

    /**
     * @dev Internal reveal logic shared by ETH and token versions
     */
    function _revealSpec(
        bytes32 commitmentId,
        bytes32 blobHash,
        uint256 nonce,
        bytes32 metadataHash
    ) internal returns (bytes32 uid) {
        CommitData storage commitment = commitments[commitmentId];

        if (commitment.committer == address(0)) revert CommitmentNotFound();
        if (commitment.committer != msg.sender) revert InvalidReveal();
        if (commitment.isRevealed) revert CommitmentAlreadyRevealed();
        if (blobHash == bytes32(0)) revert EmptyBlobHash();
        if (metadataHash == bytes32(0)) revert EmptyMetadataHash();

        // Verify commitment
        // Note: must cast commitTimestamp to uint256 to match how commitmentId was computed
        bytes32 expectedCommitment = keccak256(abi.encodePacked(blobHash, nonce));
        bytes32 reconstructedId = keccak256(abi.encodePacked(
            expectedCommitment,
            commitment.committer,
            commitment.chainId,
            commitment.extcodehash,
            uint256(commitment.commitTimestamp)
        ));

        if (reconstructedId != commitmentId) revert InvalidReveal();

        commitment.isRevealed = true;

        // Create attestation (not indexed yet - will be indexed only if approved)
        uid = keccak256(abi.encodePacked(
            commitment.chainId,
            commitment.extcodehash,
            blobHash,
            msg.sender,
            block.timestamp
        ));

        _attestations[uid] = Attestation({
            uid: uid,
            chainId: commitment.chainId,
            extcodehash: commitment.extcodehash,
            blobHash: blobHash,
            metadataHash: metadataHash,
            attester: msg.sender,
            timestamp: uint64(block.timestamp),
            idx: 0,  // Will be assigned on finalization if approved
            revoked: false,
            finalizedAt: 0,
            revokeProposedAt: 0,
            revokeProposer: address(0)
        });

        emit LogRevealSpec(
            msg.sender,
            uid,
            blobHash,
            commitmentId,
            commitment.chainId,
            commitment.extcodehash
        );
    }

    /**
     * @dev Build question params string for Reality.eth
     */
    function _buildQuestionParams(
        bytes32 blobHash,
        bytes32 extcodehash,
        uint256 chainId
    ) internal pure returns (string memory) {
        string memory delim = unicode"␟";
        return string(abi.encodePacked(
            _bytes32ToString(blobHash),
            delim,
            _bytes32ToString(extcodehash),
            delim,
            _uint256ToString(chainId)
        ));
    }

    // ========== FINALIZATION ==========

    /**
     * @notice Finalize an attestation after Reality.eth question is resolved
     * @dev Only APPROVED specs get indexed in merkle tree
     * @param uid Attestation UID
     * @param newMerkleRoot Proposed new merkle root (only used if approved)
     * @param merkleProof Proof for the new leaf (only used if approved)
     */
    function finalize(
        bytes32 uid,
        bytes32 newMerkleRoot,
        bytes32[] calldata merkleProof
    ) external nonReentrant whenNotPaused {
        Attestation storage att = _attestations[uid];

        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt != 0) revert AlreadyFinalized();

        bytes32 questionId = questionIds[uid];

        // Use appropriate Reality.eth instance based on mode
        IRealityETH reality = address(bondToken) == address(0) ? realityETH : realityETH_ERC20;

        // Check Reality.eth finalization
        if (!reality.isFinalized(questionId)) {
            revert ChallengePeriodActive();
        }

        // Get result from Reality.eth (1 = approved, 0 = rejected)
        bytes32 result = reality.resultFor(questionId);
        bool approved = (uint256(result) == 1);

        att.finalizedAt = uint64(block.timestamp);

        if (approved) {
            // APPROVED: Assign index and add to merkle tree
            uint64 idx = ++currentIdx;
            att.idx = idx;

            // Index by chain and bytecode
            _specsByChainAndBytecode[att.chainId][att.extcodehash].push(uid);

            // Compute leaf hash (EIP-712-style domain separation)
            bytes32 leaf = keccak256(abi.encode(
                LEAF_TYPEHASH,
                att.chainId,
                att.extcodehash,
                att.metadataHash,
                att.idx,
                false  // not revoked
            ));

            // Verify merkle proof
            if (!_verifyMerkleUpdate(leaf, att.idx, merkleProof, newMerkleRoot)) {
                revert InvalidMerkleProof();
            }

            // Update merkle root
            merkleRoot = newMerkleRoot;
            merkleRootIdx = att.idx;

            emit SpecIndexed(uid, att.chainId, att.extcodehash, att.blobHash, att.attester, idx);
        } else {
            // REJECTED: Mark as revoked, do NOT index
            att.revoked = true;
            // No merkle update, no incentives
        }

        emit AttestationFinalized(uid, att.idx, approved);
    }

    // ========== REVOCATION ==========

    /**
     * @notice Propose revocation with ETH bond (Phase 1)
     * @param uid Attestation UID
     */
    function proposeRevoke(bytes32 uid) external payable nonReentrant whenNotPaused {
        if (address(bondToken) != address(0)) revert UseProposeRevokeToken();
        if (msg.value < minBond) revert BelowMinBond();

        _proposeRevokeValidation(uid);

        string memory questionParams = _buildRevokeQuestionParams(uid);

        bytes32 revokeQuestionId = realityETH.askQuestionWithMinBond{value: msg.value}(
            templateId,
            questionParams,
            arbitrator,
            DEFAULT_TIMEOUT,
            0,
            0,
            minBond
        );

        revokeQuestionIds[uid] = revokeQuestionId;

        emit RevokeProposed(uid, msg.sender);
        emit RevokeQuestionCreated(uid, revokeQuestionId, msg.value);
    }

    /**
     * @notice Propose revocation with bToken bond (Phase 2)
     * @param uid Attestation UID
     * @param tokenAmount Amount of bToken to bond
     */
    function proposeRevokeToken(bytes32 uid, uint256 tokenAmount) external nonReentrant whenNotPaused {
        if (address(bondToken) == address(0)) revert UseProposeRevokeETH();
        if (tokenAmount < minBond) revert BelowMinBond();

        _proposeRevokeValidation(uid);

        // Transfer bToken and approve Reality.eth ERC20
        bondToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
        bondToken.safeApprove(address(realityETH_ERC20), tokenAmount);

        string memory questionParams = _buildRevokeQuestionParams(uid);

        bytes32 revokeQuestionId = realityETH_ERC20.askQuestionWithMinBondERC20(
            templateId,
            questionParams,
            arbitrator,
            DEFAULT_TIMEOUT,
            0,
            0,
            minBond,
            tokenAmount
        );

        revokeQuestionIds[uid] = revokeQuestionId;

        emit RevokeProposed(uid, msg.sender);
        emit RevokeQuestionCreated(uid, revokeQuestionId, tokenAmount);
    }

    function _proposeRevokeValidation(bytes32 uid) internal {
        Attestation storage att = _attestations[uid];

        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt == 0) revert NotFinalized();
        if (att.revoked) revert AlreadyRevoked();
        if (att.revokeProposedAt != 0) revert RevokeAlreadyProposed();

        att.revokeProposedAt = uint64(block.timestamp);
        att.revokeProposer = msg.sender;
    }

    function _buildRevokeQuestionParams(bytes32 uid) internal view returns (string memory) {
        Attestation storage att = _attestations[uid];
        string memory delim = unicode"␟";
        return string(abi.encodePacked(
            "REVOKE:",
            _bytes32ToString(uid),
            delim,
            _bytes32ToString(att.extcodehash),
            delim,
            _uint256ToString(att.chainId)
        ));
    }

    /**
     * @notice Finalize a revoke proposal based on Reality.eth result
     * @param uid Attestation UID
     */
    function finalizeRevoke(bytes32 uid) external nonReentrant whenNotPaused {
        Attestation storage att = _attestations[uid];

        if (att.revokeProposedAt == 0) revert NoRevokeProposal();

        bytes32 revokeQuestionId = revokeQuestionIds[uid];

        // Use appropriate Reality.eth instance based on mode
        IRealityETH reality = address(bondToken) == address(0) ? realityETH : realityETH_ERC20;

        // Check Reality.eth finalization
        if (!reality.isFinalized(revokeQuestionId)) {
            revert ChallengePeriodActive();
        }

        // Get result from Reality.eth (1 = revoke approved, 0 = revoke rejected)
        bytes32 result = reality.resultFor(revokeQuestionId);
        bool revokeApproved = (uint256(result) == 1);

        if (revokeApproved) {
            att.revoked = true;
            emit RevokeFinalized(uid, true);
        } else {
            // Revoke rejected - reset proposal
            att.revokeProposedAt = 0;
            att.revokeProposer = address(0);
            emit RevokeFinalized(uid, false);
        }
    }

    // ========== MERKLE HELPERS ==========

    function computeAttestationLeaf(bytes32 uid) public view returns (bytes32 leaf) {
        Attestation memory att = _attestations[uid];
        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt == 0) revert NotFinalized();

        leaf = keccak256(abi.encode(
            LEAF_TYPEHASH,
            att.chainId,
            att.extcodehash,
            att.metadataHash,
            att.idx,
            att.revoked
        ));
    }

    function verifyMerkleProof(
        bytes32 leaf,
        bytes32[] calldata proof,
        uint256 index,
        bytes32 root
    ) public pure returns (bool valid) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }

            index = index / 2;
        }

        return computedHash == root;
    }

    function verifyAttestationInclusion(
        bytes32 uid,
        bytes32[] calldata proof
    ) external view returns (bool valid) {
        Attestation memory att = _attestations[uid];
        if (att.finalizedAt == 0) revert NotFinalized();

        bytes32 leaf = computeAttestationLeaf(uid);
        return verifyMerkleProof(leaf, proof, att.idx - 1, merkleRoot);
    }

    function _verifyMerkleUpdate(
        bytes32 leaf,
        uint64 leafIdx,
        bytes32[] calldata proof,
        bytes32 expectedRoot
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        uint256 position = leafIdx - 1; // idx is 1-based

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if ((position >> i) & 1 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == expectedRoot;
    }

    // ========== STRING HELPERS (for Reality.eth question params) ==========

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

    // ========== ECONOMICS INTEGRATION ==========

    /**
     * @notice Transition to Phase 2 (bToken mode)
     * @param _bondToken The bToken address
     * @param _realityETH_ERC20 Reality.eth ERC20 version address
     */
    function setBondToken(address _bondToken, address _realityETH_ERC20) external onlyOwner {
        require(_bondToken != address(0), "Invalid token");
        require(_realityETH_ERC20 != address(0), "Invalid Reality.eth ERC20");

        bondToken = IERC20(_bondToken);
        realityETH_ERC20 = IRealityETH(_realityETH_ERC20);

        emit BondTokenSet(_bondToken, _realityETH_ERC20);
    }

    function setMinBond(uint256 _minBond) external onlyOwner {
        minBond = _minBond;
    }

    // ========== QUERY FUNCTIONS ==========

    function getAttestation(bytes32 uid) external view override returns (Attestation memory) {
        return _attestations[uid];
    }

    function revokeProposers(bytes32 uid) external view returns (address) {
        return _attestations[uid].revokeProposer;
    }

    function getSpecsForBytecode(uint256 chainId, bytes32 extcodehash) external view returns (bytes32[] memory) {
        return _specsByChainAndBytecode[chainId][extcodehash];
    }

    function getLatestSpecForBytecode(uint256 chainId, bytes32 extcodehash) external view returns (bytes32 uid, bool valid) {
        bytes32[] memory specs = _specsByChainAndBytecode[chainId][extcodehash];

        for (uint256 i = specs.length; i > 0; i--) {
            bytes32 specUid = specs[i - 1];
            Attestation memory att = _attestations[specUid];
            if (att.finalizedAt != 0 && !att.revoked) {
                return (specUid, true);
            }
        }

        return (bytes32(0), false);
    }

    function getSpecsForBytecodePaginated(
        uint256 chainId,
        bytes32 extcodehash,
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory uids, uint256 total) {
        bytes32[] storage specs = _specsByChainAndBytecode[chainId][extcodehash];
        total = specs.length;

        if (offset >= total) {
            return (new bytes32[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uids = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            uids[i - offset] = specs[i];
        }
    }

    // ========== FORK-READY: State snapshot ==========

    function getStateRoot() external view returns (bytes32) {
        return merkleRoot;
    }

    function getStateAtIdx() external view returns (uint64) {
        return merkleRootIdx;
    }

    // ========== ADMIN FUNCTIONS ==========

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
