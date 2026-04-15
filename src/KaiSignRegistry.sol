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
 * - Incremental merkle tree for on-chain proof verification
 * - Universe ID for fork support (EIGEN-style intersubjective forking)
 * - Only APPROVED specs are indexed in merkle tree
 */
contract KaiSignRegistry is IKaiSignRegistry, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========== CUSTOM ERRORS ==========
    error AttestationNotFound();
    error AlreadyRevoked();
    error InvalidExtcodehash();
    error InvalidChainId();
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
    error BondTokenNotSet();
    error AlreadyImported();
    error TreeFull();
    error AlreadyMigrated();
    error NothingToMigrate();
    error RevealTooEarly();
    error ConfigChanged();
    error InvalidToken();
    error InvalidRealityETH();
    error InvalidTreeDepth();
    error InvalidQuestionResult();      
    error UnresolvedQuestionResult();  

    // ========== CONSTANTS ==========
    string public constant VERSION = "1.0.0";
    uint32 public constant DEFAULT_TIMEOUT = 48 hours;
    uint256 public constant MIN_REVEAL_DELAY = 1;
    bytes32 public constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,bool revoked)");

    // ========== FORK-READY: Universe tracking ==========
    uint256 public immutable override universeId;
    address public immutable override parentRegistry;

    // ========== REALITY.ETH INTEGRATION ==========
    address public immutable arbitrator;
    IRealityETH public realityETH;
    uint256 public templateId;
    uint256 public revokeTemplateId;
    uint256 public minBond;
    IERC20 public bondToken;
    uint32 public configNonce;
    struct QuestionData {
        bytes32 questionId;
        IRealityETH realityInstance;
    }
    mapping(bytes32 => QuestionData) public questions;        // uid => submission question
    mapping(bytes32 => QuestionData) public revokeQuestions;   // uid => revoke question

    // ========== INTERNAL MERKLE INSERTION CURSOR ==========
    uint64 private currentIdx;

    // ========== ATTESTATION STORAGE ==========
    mapping(bytes32 => Attestation) private _attestations;

    // ========== CHAIN + EXTCODEHASH INDEXING ==========
    mapping(uint256 => mapping(bytes32 => bytes32[])) private _specsByChainAndBytecode;

    // ========== COMMIT-REVEAL ==========
    struct CommitData {
        address committer;
        uint64 commitTimestamp;
        bool isRevealed;
        uint32 configNonceSnapshot;
        uint256 chainId;
        bytes32 extcodehash;
    }
    mapping(bytes32 => CommitData) public commitments;

    // ========== INCREMENTAL MERKLE TREE ==========
    uint256 public immutable treeDepth;
    mapping(uint256 => bytes32) public filledSubtrees;
    mapping(uint256 => bytes32) public zeroHashes;

    // ========== MERKLE ROOT ==========
    bytes32 public override merkleRoot;

    // ========== EVENTS ==========
    event BondTokenSet(address indexed token, address indexed realityERC20);
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
        uint256 _treeDepth,
        uint256 _universeId,
        address _parentRegistry,
        address _initialOwner,
        address _arbitrator,
        uint256 _minBond
    ) {
        if (_treeDepth == 0 || _treeDepth > 32) revert InvalidTreeDepth();
        treeDepth = _treeDepth;

        // Precompute zero hashes for empty subtrees at each level
        bytes32 z = bytes32(0);
        for (uint256 i = 0; i < _treeDepth; i++) {
            zeroHashes[i] = z;
            z = keccak256(abi.encodePacked(z, z));
        }

        // Note: arbitrator can be address(0) - questions finalize after timeout without arbitration

        universeId = _universeId;
        parentRegistry = _parentRegistry;
        arbitrator = _arbitrator;
        minBond = _minBond;

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

        commitmentId = keccak256(abi.encode(
            commitment,
            msg.sender,
            chainId,
            extcodehash,
            block.timestamp
        ));

        commitments[commitmentId] = CommitData({
            committer: msg.sender,
            commitTimestamp: uint64(block.timestamp),
            isRevealed: false,
            configNonceSnapshot: configNonce,
            chainId: chainId,
            extcodehash: extcodehash
        });

        emit LogCommitSpec(msg.sender, commitmentId, chainId, extcodehash);
    }

    /**
     * @notice Reveal a committed spec with ERC20 token bond
     * @dev Caller must approve bondToken first. Bond token must be set via setBondToken.
     * @param commitmentId The commitment to reveal
     * @param blobHash EIP-4844 blob hash containing metadata
     * @param nonce Nonce used in commitment
     * @param metadataHash Hash of the metadata content
     * @param tokenAmount Amount of bondToken to bond
     * @return uid Unique attestation identifier
     */
    function revealSpec(
        bytes32 commitmentId,
        bytes32 blobHash,
        uint256 nonce,
        bytes32 metadataHash,
        uint256 tokenAmount
    ) external nonReentrant whenNotPaused returns (bytes32 uid) {
        if (address(bondToken) == address(0)) revert BondTokenNotSet();
        if (tokenAmount < minBond) revert BelowMinBond();

        uid = _revealSpec(commitmentId, blobHash, nonce, metadataHash);

        // Transfer bondToken from user and approve Reality.eth
        bondToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
        bondToken.forceApprove(address(realityETH), tokenAmount);

        // Create Reality.eth question with token bond
        string memory questionParams = _buildQuestionParams(
            blobHash,
            commitments[commitmentId].extcodehash,
            commitments[commitmentId].chainId
        );

        bytes32 questionId = realityETH.askQuestionWithMinBondERC20(
            templateId,
            questionParams,
            arbitrator,
            DEFAULT_TIMEOUT,
            0,  // opening_ts
            uint256(uid),  // nonce 
            minBond,
            tokenAmount
        );

        bondToken.forceApprove(address(realityETH), 0);

        questions[uid] = QuestionData({
            questionId: questionId,
            realityInstance: realityETH
        });
        emit QuestionCreated(uid, questionId, tokenAmount);
    }

    /**
     * @dev Internal reveal logic
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
        bytes32 expectedCommitment = keccak256(abi.encode(blobHash, nonce));
        bytes32 reconstructedId = keccak256(abi.encode(
            expectedCommitment,
            commitment.committer,
            commitment.chainId,
            commitment.extcodehash,
            uint256(commitment.commitTimestamp)
        ));

        if (reconstructedId != commitmentId) revert InvalidReveal();

        if (block.timestamp < commitment.commitTimestamp + MIN_REVEAL_DELAY)
            revert RevealTooEarly();

        if (commitment.configNonceSnapshot != configNonce) revert ConfigChanged();

        commitment.isRevealed = true;

        // Create attestation (not indexed yet - will be indexed only if approved)
        uid = keccak256(abi.encode(
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
            revoked: false,
            finalizedAt: 0,
            revokeProposedAt: 0,
            revokeProposer: address(0),
            revokeAttempt: 0
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
     * @dev Only APPROVED specs get indexed in on-chain incremental merkle tree
     * @param uid Attestation UID
     */
    function finalize(bytes32 uid) external nonReentrant {  
        Attestation storage att = _attestations[uid];

        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt != 0) revert AlreadyFinalized();

        QuestionData memory q = questions[uid];
        if (address(q.realityInstance) == address(0)) revert AttestationNotFound();

        if (!q.realityInstance.isFinalized(q.questionId)) {
            revert ChallengePeriodActive();
        }

        bytes32 result = q.realityInstance.resultFor(q.questionId);
        
        if (uint256(result) == type(uint256).max) revert InvalidQuestionResult();
        if (uint256(result) == type(uint256).max - 1) revert UnresolvedQuestionResult();
        bool approved = (uint256(result) == 1);

        att.finalizedAt = uint64(block.timestamp);

        if (approved) {
            // APPROVED: Add to merkle tree
            if (currentIdx >= (1 << treeDepth)) revert TreeFull();
            ++currentIdx;

            // Index by chain and bytecode
            _specsByChainAndBytecode[att.chainId][att.extcodehash].push(uid);

            // Compute leaf hash (EIP-712-style domain separation)
            bytes32 leaf = keccak256(abi.encode(
                LEAF_TYPEHASH,
                att.chainId,
                att.extcodehash,
                att.metadataHash,
                false  // not revoked
            ));

            // Insert leaf into on-chain incremental tree
            merkleRoot = _insertLeaf(leaf, currentIdx - 1);
            emit MerkleRootUpdated(merkleRoot);

            emit SpecIndexed(uid, att.chainId, att.extcodehash, att.blobHash, att.attester);
        } else {
            // REJECTED: Mark as revoked, do NOT index
            att.revoked = true;
            // No merkle update, no incentives
        }

        emit AttestationFinalized(uid, approved);
    }

    // ========== REVOCATION ==========

    /**
     * @notice Propose revocation with ERC20 token bond
     * @param uid Attestation UID
     * @param tokenAmount Amount of bondToken to bond
     */
    function proposeRevoke(bytes32 uid, uint256 tokenAmount) external nonReentrant whenNotPaused {
        if (address(bondToken) == address(0)) revert BondTokenNotSet();
        if (tokenAmount < minBond) revert BelowMinBond();

        _proposeRevokeValidation(uid);

        // Transfer bondToken and approve Reality.eth
        bondToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
        bondToken.forceApprove(address(realityETH), tokenAmount);

        string memory questionParams = _buildRevokeQuestionParams(uid);

        bytes32 revokeQuestionId = realityETH.askQuestionWithMinBondERC20(
            revokeTemplateId,
            questionParams,
            arbitrator,
            DEFAULT_TIMEOUT,
            0,
            uint256(keccak256(abi.encode(uid, _attestations[uid].revokeAttempt))),  
            minBond,
            tokenAmount
        );

        bondToken.forceApprove(address(realityETH), 0);

        revokeQuestions[uid] = QuestionData({
            questionId: revokeQuestionId,
            realityInstance: realityETH
        });

        emit RevokeProposed(uid, msg.sender);
        emit RevokeQuestionCreated(uid, revokeQuestionId, tokenAmount);
    }

    function _proposeRevokeValidation(bytes32 uid) internal {
        Attestation storage att = _attestations[uid];

        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt == 0) revert NotFinalized();
        if (att.revoked) revert AlreadyRevoked();
        if (att.revokeProposedAt != 0) revert RevokeAlreadyProposed();

        att.revokeAttempt++;  
        att.revokeProposedAt = uint64(block.timestamp);
        att.revokeProposer = msg.sender;
    }

    function _buildRevokeQuestionParams(bytes32 uid) internal view returns (string memory) {
        Attestation storage att = _attestations[uid];
        string memory delim = unicode"␟";
        return string(abi.encodePacked(
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
    function finalizeRevoke(bytes32 uid) external nonReentrant {  
        Attestation storage att = _attestations[uid];

        if (att.revokeProposedAt == 0) revert NoRevokeProposal();
        if (att.revoked) revert AlreadyRevoked();

        QuestionData memory rq = revokeQuestions[uid];
        if (address(rq.realityInstance) == address(0)) revert AttestationNotFound();

        if (!rq.realityInstance.isFinalized(rq.questionId)) {
            revert ChallengePeriodActive();
        }

        bytes32 result = rq.realityInstance.resultFor(rq.questionId);

        // Treat INVALID/UNRESOLVED same as rejection — reset state so a new revoke can be proposed
        if (uint256(result) == type(uint256).max || uint256(result) == type(uint256).max - 1) {
            att.revokeProposedAt = 0;
            att.revokeProposer = address(0);
            delete revokeQuestions[uid];
            emit RevokeFinalized(uid, false);
            return;
        }
        bool revokeApproved = (uint256(result) == 1);

        if (revokeApproved) {
            att.revoked = true;
            if (currentIdx >= (1 << treeDepth)) revert TreeFull();
            ++currentIdx;

            bytes32 leaf = keccak256(abi.encode(
                LEAF_TYPEHASH,
                att.chainId,
                att.extcodehash,
                att.metadataHash,
                true  // revoked
            ));

            merkleRoot = _insertLeaf(leaf, currentIdx - 1);
            emit MerkleRootUpdated(merkleRoot);

            att.revokeProposedAt = 0;
            att.revokeProposer = address(0);
            delete revokeQuestions[uid];

            emit RevokeFinalized(uid, true);
        } else {
            // Revoke rejected - reset proposal and clean up stale question
            att.revokeProposedAt = 0;
            att.revokeProposer = address(0);
            delete revokeQuestions[uid];
            emit RevokeFinalized(uid, false);
        }
    }

    // ========== MERKLE HELPERS ==========

    function computeAttestationLeaf(bytes32 uid, bool revoked) public view returns (bytes32 leaf) {
        Attestation memory att = _attestations[uid];
        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt == 0) revert NotFinalized();

        leaf = keccak256(abi.encode(
            LEAF_TYPEHASH,
            att.chainId,
            att.extcodehash,
            att.metadataHash,
            revoked
        ));
    }

    function verifyMerkleProof(
        bytes32 leaf,
        bytes32[] calldata proof,
        uint256 index,
        bytes32 root
    ) public view returns (bool valid) {
        if (proof.length != treeDepth) revert InvalidMerkleProof();
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

    /**
     * @dev Insert a leaf into the on-chain incremental Merkle tree
     * @param leaf The leaf hash to insert
     * @param pos The 0-based tree position for this leaf
     * @return root The new Merkle root after insertion
     */
    function _insertLeaf(bytes32 leaf, uint256 pos) internal returns (bytes32 root) {
        bytes32 currentHash = leaf;

        for (uint256 i = 0; i < treeDepth; i++) {
            if (pos % 2 == 0) {
                filledSubtrees[i] = currentHash;
                currentHash = keccak256(abi.encodePacked(currentHash, zeroHashes[i]));
            } else {
                currentHash = keccak256(abi.encodePacked(filledSubtrees[i], currentHash));
            }
            pos /= 2;
        }

        return currentHash;
    }

    /**
     * @dev Recompute Merkle root from the frontier array and leaf count
     * @param numLeaves Number of leaves inserted into the tree
     * @return root The computed Merkle root
     */
    function _computeRootFromFrontier(uint64 numLeaves) internal view returns (bytes32) {
        bytes32 current = bytes32(0);
        uint256 n = numLeaves;

        for (uint256 i = 0; i < treeDepth; i++) {
            if (n & 1 == 1) {
                current = keccak256(abi.encodePacked(filledSubtrees[i], current));
            } else {
                current = keccak256(abi.encodePacked(current, zeroHashes[i]));
            }
            n >>= 1;
        }

        return current;
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
     * @notice Set the bond token and Reality.eth ERC20 instance
     * @dev Must be called before any reveal/revoke operations
     * @param _bondToken The ERC20 token address for bonds
     * @param _realityETH Reality.eth ERC20 version address
     */
    function setBondToken(address _bondToken, address _realityETH) external onlyOwner {
        if (_bondToken == address(0)) revert InvalidToken();
        if (_realityETH == address(0)) revert InvalidRealityETH();

        configNonce++;
        bondToken = IERC20(_bondToken);
        realityETH = IRealityETH(_realityETH);

        // Create template on Reality.eth
        templateId = realityETH.createTemplate(
            '{"title": "Is the ERC7730 specification %s for contract %s on chain %s correct?", "type": "bool", "category": "misc"}'
        );
        revokeTemplateId = realityETH.createTemplate(
            '{"title": "Should attestation %s for contract %s on chain %s be revoked?", "type": "bool", "category": "misc"}'
        );

        emit BondTokenSet(_bondToken, _realityETH);
    }

    function setMinBond(uint256 _minBond) external onlyOwner {
        configNonce++;  
        uint256 old = minBond;
        minBond = _minBond;
        emit MinBondUpdated(old, _minBond);
    }

    /**
     * @notice Migrate state from a previous contract
     * @dev Imports the incremental tree frontier and recomputes the merkle root.
     *      The frontier must be computed off-chain by simulating incremental insertions
     *      of all leaves from the old contract in order.
     *
     *      For standard binary trees: compute frontier by replaying all leaf insertions
     *      through the incremental algorithm off-chain, then pass the resulting
     *      filledSubtrees array here.
     *
     *      IMPORTANT: The computed merkle root will differ from the old contract's root
     *      if the old contract used a different tree algorithm (e.g., standard binary tree).
     *      This is expected - the new root represents the same leaves in incremental format.
     *
     * @param _frontier The filledSubtrees array computed from replaying old leaves
     * @param _currentIdx Number of leaves in the old tree (next finalized spec will be _currentIdx + 1)
     */
    function migrate(bytes32[] calldata _frontier, uint64 _currentIdx) external onlyOwner {
        if (merkleRoot != bytes32(0)) revert AlreadyMigrated();
        if (_currentIdx == 0) revert NothingToMigrate();
        if (_frontier.length != treeDepth) revert InvalidMerkleProof();

        // Import frontier for incremental tree continuation
        for (uint256 i = 0; i < treeDepth; i++) {
            filledSubtrees[i] = _frontier[i];
        }

        // Recompute root from frontier to ensure consistency
        merkleRoot = _computeRootFromFrontier(_currentIdx);
        currentIdx = _currentIdx;
        emit MerkleRootUpdated(merkleRoot);

        emit Migrated(merkleRoot);
    }

    /**
     * @notice Verify a migrated attestation against the merkle root
     * @dev Reverts on invalid proof. Designed for trustless verification from hardware wallets:
     *      valid proof → call succeeds, invalid proof → call reverts.
     *      No need to trust software to interpret a return value.
     * @param chainId Target chain ID
     * @param extcodehash Target contract bytecode hash
     * @param metadataHash Hash of the metadata content
     * @param revoked Whether attestation is revoked
     * @param leafIndex 0-based position of the leaf in the merkle tree
     * @param merkleProof Proof of inclusion in the migrated merkle root
     */
    function verifyMigratedAttestation(
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash,
        bool revoked,
        uint256 leafIndex,
        bytes32[] calldata merkleProof
    ) external view {
        bytes32 leaf = keccak256(abi.encode(
            LEAF_TYPEHASH,
            chainId,
            extcodehash,
            metadataHash,
            revoked
        ));

        if (!verifyMerkleProof(leaf, merkleProof, leafIndex, merkleRoot)) {
            revert InvalidMerkleProof();
        }
    }

    /**
     * @notice Import a migrated attestation by proving inclusion in merkle root
     * @dev Once imported, normal proposeRevoke/finalizeRevoke flow can be used.
     *      UID is derived deterministically from proof-verified fields.
     *      Unverifiable fields (blobHash, attester) are zeroed; timestamps use block.timestamp.
     * @param chainId Target chain ID
     * @param extcodehash Target contract bytecode hash
     * @param metadataHash Hash of metadata content
     * @param leafIndex 0-based position of the leaf in the merkle tree
     * @param merkleProof Proof of inclusion
     */
    function importMigratedAttestation(
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash,
        uint256 leafIndex,
        bytes32[] calldata merkleProof
    ) external whenNotPaused {
        // Derive UID deterministically from proof-verified fields
        bytes32 uid = keccak256(abi.encode(chainId, extcodehash, metadataHash));

        // Must not already exist
        if (_attestations[uid].timestamp != 0) revert AlreadyImported();

        // Verify merkle proof (attestation was not revoked at migration time)
        bytes32 leaf = keccak256(abi.encode(
            LEAF_TYPEHASH,
            chainId,
            extcodehash,
            metadataHash,
            false  // not revoked
        ));

        if (!verifyMerkleProof(leaf, merkleProof, leafIndex, merkleRoot)) {
            revert InvalidMerkleProof();
        }

        // Store the attestation with zeroed unverified fields
        _attestations[uid] = Attestation({
            uid: uid,
            chainId: chainId,
            extcodehash: extcodehash,
            blobHash: bytes32(0),
            metadataHash: metadataHash,
            attester: address(0),
            timestamp: uint64(block.timestamp),
            revoked: false,
            finalizedAt: uint64(block.timestamp),
            revokeProposedAt: 0,
            revokeProposer: address(0),
            revokeAttempt: 0
        });

        // Index by chain and bytecode
        _specsByChainAndBytecode[chainId][extcodehash].push(uid);

        emit SpecIndexed(uid, chainId, extcodehash, bytes32(0), address(0));
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

    // ========== ADMIN FUNCTIONS ==========

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
