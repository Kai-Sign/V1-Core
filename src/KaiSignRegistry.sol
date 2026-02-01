// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IKaiSignRegistry} from "./interfaces/IKaiSignRegistry.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title KaiSignRegistry
 * @notice Registry for ERC7730 clear signing metadata specifications
 * @dev Single registry on L1 for all chains with bond escalation and fork support
 *
 * Key Features:
 * - Commit-reveal for spec submission (prevents front-running)
 * - Bond escalation (Reality.eth style, 2-day timer resets on each bond)
 * - chainId + extcodehash indexing (supports all chains from L1)
 * - Merkle root checkpoints with idx ordering
 * - Universe ID for fork support (EIGEN-style intersubjective forking)
 */
contract KaiSignRegistry is IKaiSignRegistry, Ownable2Step, ReentrancyGuard, Pausable {
    // ========== CUSTOM ERRORS ==========
    error NotAttester();
    error AlreadyAttester();
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

    // ========== CONSTANTS ==========
    string public constant VERSION = "1.0.0";
    uint64 public constant CHALLENGE_PERIOD = 2 days;

    // ========== FORK-READY: Universe tracking ==========
    uint256 public immutable override universeId;
    address public immutable override parentRegistry;
    uint64 public forkTimestamp;
    bytes32 public forkStateRoot;

    // ========== ATTESTER ALLOWLIST ==========
    mapping(address => bool) private _isAttester;
    address[] private _attesters;

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

    // ========== ECONOMICS INTEGRATION ==========
    address public bondManager;
    address public incentivePool;

    // ========== EVENTS ==========
    event BondManagerSet(address indexed bondManager);
    event IncentivePoolSet(address indexed incentivePool);
    event RegistryForked(uint256 indexed newUniverseId, address indexed newRegistry, bytes32 stateRoot);
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

    // ========== MODIFIERS ==========
    modifier onlyAttester() {
        if (!_isAttester[msg.sender]) revert NotAttester();
        _;
    }

    // ========== CONSTRUCTOR ==========
    constructor(
        uint256 _universeId,
        address _parentRegistry,
        address _initialOwner,
        address[] memory _initialAttesters
    ) {
        universeId = _universeId;
        parentRegistry = _parentRegistry;

        if (_initialOwner != msg.sender) {
            _transferOwnership(_initialOwner);
        }

        for (uint256 i = 0; i < _initialAttesters.length; i++) {
            address attester = _initialAttesters[i];
            if (attester != address(0) && !_isAttester[attester]) {
                _isAttester[attester] = true;
                _attesters.push(attester);
                emit AttesterAdded(attester);
            }
        }
    }

    // ========== ATTESTER MANAGEMENT (Owner only) ==========

    function addAttester(address attester) external onlyOwner {
        if (attester == address(0)) revert InvalidExtcodehash();
        if (_isAttester[attester]) revert AlreadyAttester();

        _isAttester[attester] = true;
        _attesters.push(attester);

        emit AttesterAdded(attester);
    }

    function removeAttester(address attester) external onlyOwner {
        if (!_isAttester[attester]) revert NotAttester();

        _isAttester[attester] = false;

        emit AttesterRemoved(attester);
    }

    function isAttester(address account) external view override returns (bool) {
        return _isAttester[account];
    }

    function getAttesters() external view override returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _attesters.length; i++) {
            if (_isAttester[_attesters[i]]) {
                activeCount++;
            }
        }

        address[] memory active = new address[](activeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < _attesters.length; i++) {
            if (_isAttester[_attesters[i]]) {
                active[j++] = _attesters[i];
            }
        }

        return active;
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
     * @notice Reveal a committed spec and create attestation
     * @param commitmentId The commitment to reveal
     * @param blobHash EIP-4844 blob hash containing metadata
     * @param nonce Nonce used in commitment
     * @return uid Unique attestation identifier
     */
    function revealSpec(
        bytes32 commitmentId,
        bytes32 blobHash,
        uint256 nonce
    ) external payable nonReentrant whenNotPaused returns (bytes32 uid) {
        CommitData storage commitment = commitments[commitmentId];

        if (commitment.committer == address(0)) revert CommitmentNotFound();
        if (commitment.committer != msg.sender) revert InvalidReveal();
        if (commitment.isRevealed) revert CommitmentAlreadyRevealed();
        if (blobHash == bytes32(0)) revert EmptyBlobHash();

        // Verify commitment
        bytes32 expectedCommitment = keccak256(abi.encodePacked(blobHash, nonce));
        bytes32 reconstructedId = keccak256(abi.encodePacked(
            expectedCommitment,
            commitment.committer,
            commitment.chainId,
            commitment.extcodehash,
            commitment.commitTimestamp
        ));

        if (reconstructedId != commitmentId) revert InvalidReveal();

        commitment.isRevealed = true;

        // Create attestation
        uint64 idx = ++currentIdx;

        uid = keccak256(abi.encodePacked(
            commitment.chainId,
            commitment.extcodehash,
            blobHash,
            msg.sender,
            block.timestamp,
            idx
        ));

        _attestations[uid] = Attestation({
            uid: uid,
            chainId: commitment.chainId,
            extcodehash: commitment.extcodehash,
            blobHash: blobHash,
            attester: msg.sender,
            timestamp: uint64(block.timestamp),
            idx: idx,
            revoked: false,
            finalizedAt: 0,
            revokeProposedAt: 0
        });

        // Index by chain and bytecode
        _specsByChainAndBytecode[commitment.chainId][commitment.extcodehash].push(uid);

        emit LogRevealSpec(
            msg.sender,
            uid,
            blobHash,
            commitmentId,
            commitment.chainId,
            commitment.extcodehash
        );

        emit SpecIndexed(uid, commitment.chainId, commitment.extcodehash, blobHash, msg.sender, idx);

        // Forward bond to BondManager if provided
        if (msg.value > 0 && bondManager != address(0)) {
            (bool success, ) = bondManager.call{value: msg.value}(
                abi.encodeWithSignature("propose(bytes32)", uid)
            );
            require(success, "Bond transfer failed");
        }
    }

    // ========== FINALIZATION ==========

    /**
     * @notice Finalize an attestation after challenge period
     * @param uid Attestation UID
     * @param newMerkleRoot Proposed new merkle root
     * @param merkleProof Proof for the new leaf
     */
    function finalize(
        bytes32 uid,
        bytes32 newMerkleRoot,
        bytes32[] calldata merkleProof
    ) external nonReentrant whenNotPaused {
        Attestation storage att = _attestations[uid];

        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt != 0) revert AlreadyFinalized();

        // Check with BondManager if can finalize
        if (bondManager != address(0)) {
            (bool canFin, ) = bondManager.staticcall(
                abi.encodeWithSignature("canFinalize(bytes32)", uid)
            );
            if (!canFin) revert ChallengePeriodActive();
        } else {
            // Fallback: simple time check
            if (block.timestamp < att.timestamp + CHALLENGE_PERIOD) {
                revert ChallengePeriodActive();
            }
        }

        // Determine outcome from BondManager
        bool approved = true;
        if (bondManager != address(0)) {
            (bool success, bytes memory data) = bondManager.staticcall(
                abi.encodeWithSignature("getCurrentAnswer(bytes32)", uid)
            );
            if (success && data.length >= 32) {
                approved = abi.decode(data, (bool));
            }
        }

        att.finalizedAt = uint64(block.timestamp);
        att.revoked = !approved;

        // Compute leaf hash
        bytes32 leaf = keccak256(abi.encodePacked(
            att.chainId,
            att.extcodehash,
            att.blobHash,
            att.idx,
            att.revoked
        ));

        // Verify merkle proof
        if (!_verifyMerkleUpdate(leaf, att.idx, merkleProof, newMerkleRoot)) {
            revert InvalidMerkleProof();
        }

        // Update merkle root
        merkleRoot = newMerkleRoot;
        merkleRootIdx = att.idx;

        // Settle with economics contracts
        if (approved) {
            if (bondManager != address(0)) {
                (bool success, ) = bondManager.call(
                    abi.encodeWithSignature("settleApproved(bytes32)", uid)
                );
                require(success, "Settle approved failed");
            }
            if (incentivePool != address(0)) {
                (bool success, ) = incentivePool.call(
                    abi.encodeWithSignature("claimPool(bytes32,bytes32,address)", att.extcodehash, uid, att.attester)
                );
                // Don't revert if no incentives
            }
        } else {
            if (bondManager != address(0)) {
                (bool success, ) = bondManager.call(
                    abi.encodeWithSignature("settleRejected(bytes32)", uid)
                );
                require(success, "Settle rejected failed");
            }
        }

        emit AttestationFinalized(uid, att.idx, approved);
    }

    // ========== REVOCATION ==========

    /**
     * @notice Propose revocation of an approved attestation
     * @param uid Attestation UID
     */
    function proposeRevoke(bytes32 uid) external nonReentrant whenNotPaused {
        Attestation storage att = _attestations[uid];

        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt == 0) revert NotFinalized();
        if (att.revoked) revert AlreadyRevoked();
        if (att.revokeProposedAt != 0) revert RevokeAlreadyProposed();

        att.revokeProposedAt = uint64(block.timestamp);

        emit RevokeProposed(uid, msg.sender);
    }

    /**
     * @notice Finalize a revoke proposal
     * @param uid Attestation UID
     */
    function finalizeRevoke(bytes32 uid) external nonReentrant whenNotPaused {
        Attestation storage att = _attestations[uid];

        if (att.revokeProposedAt == 0) revert NoRevokeProposal();

        // Check with BondManager
        bool revokeApproved = false;
        if (bondManager != address(0)) {
            (bool canFin, ) = bondManager.staticcall(
                abi.encodeWithSignature("canFinalizeRevoke(bytes32)", uid)
            );
            if (!canFin) revert ChallengePeriodActive();

            (bool success, bytes memory data) = bondManager.staticcall(
                abi.encodeWithSignature("getRevokeAnswer(bytes32)", uid)
            );
            if (success && data.length >= 32) {
                revokeApproved = abi.decode(data, (bool));
            }
        } else {
            if (block.timestamp < att.revokeProposedAt + CHALLENGE_PERIOD) {
                revert ChallengePeriodActive();
            }
            revokeApproved = true; // Default to approve if no bond manager
        }

        if (revokeApproved) {
            att.revoked = true;

            if (bondManager != address(0)) {
                (bool success, ) = bondManager.call(
                    abi.encodeWithSignature("settleRevokeApproved(bytes32)", uid)
                );
                require(success, "Settle revoke approved failed");
            }

            emit RevokeFinalized(uid, true);
        } else {
            att.revokeProposedAt = 0;

            if (bondManager != address(0)) {
                (bool success, ) = bondManager.call(
                    abi.encodeWithSignature("settleRevokeRejected(bytes32)", uid)
                );
                require(success, "Settle revoke rejected failed");
            }

            emit RevokeFinalized(uid, false);
        }
    }

    // ========== MERKLE HELPERS ==========

    function computeAttestationLeaf(bytes32 uid) public view returns (bytes32 leaf) {
        Attestation memory att = _attestations[uid];
        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt == 0) revert NotFinalized();

        leaf = keccak256(abi.encodePacked(
            att.chainId,
            att.extcodehash,
            att.blobHash,
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

    // ========== ECONOMICS INTEGRATION ==========

    function setBondManager(address _bondManager) external onlyOwner {
        bondManager = _bondManager;
        emit BondManagerSet(_bondManager);
    }

    function setIncentivePool(address _incentivePool) external onlyOwner {
        incentivePool = _incentivePool;
        emit IncentivePoolSet(_incentivePool);
    }

    // ========== QUERY FUNCTIONS ==========

    function getAttestation(bytes32 uid) external view override returns (Attestation memory) {
        return _attestations[uid];
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
