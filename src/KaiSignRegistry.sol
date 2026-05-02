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
 * @dev Single registry on L1 for all chains with Reality.eth bond escalation.
 *
 * Tree commitment: Sparse Merkle Tree of depth 256, keyed by
 * keccak256(chainId, extcodehash). Only the root is stored on-chain. All other
 * tree state lives off-chain (events, blobs, IPFS, DA layer) and is reconstructible
 * from the SmtRootUpdated event stream — this is the explicit DA tradeoff.
 *
 * Slot semantics:
 *   - Empty slot (value = bytes32(0)) = no approved attestation OR revoked
 *   - Non-empty slot (value = approvedLeaf) = a current approved attestation exists
 * Revocation overwrites the slot back to bytes32(0). Hardware wallets verify
 * "is this metadata current?" by checking the approvedLeaf membership against
 * the latest root — pull-free.
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
    error InvalidSmtProof();
    error BelowMinBond();
    error EmptyMetadataHash();
    error BondTokenNotSet();
    error AlreadyMigrated();
    error InvalidRoot();
    error RevealTooEarly();
    error ConfigChanged();
    error InvalidToken();
    error InvalidRealityETH();
    error InvalidQuestionResult();
    error UnresolvedQuestionResult();
    error SlotAlreadyOccupied();
    error SlotNotApproved();

    // ========== CONSTANTS ==========
    string public constant VERSION = "2.0.0";
    uint32 public constant DEFAULT_TIMEOUT = 48 hours;
    uint256 public constant MIN_REVEAL_DELAY = 1;
    uint256 public constant SMT_DEPTH = 256;
    bytes32 public constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash)");

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
    mapping(bytes32 => QuestionData) public revokeQuestions;  // uid => revoke question

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

    // ========== SMT ROOT ==========
    /// @dev The SMT root. Empty tree = bytes32(0). Updated by finalize / finalizeRevoke
    /// / migrate. Off-chain indexers reconstruct tree state from SmtRootUpdated events.
    bytes32 public override smtRoot;

    /// @dev True once migrate() has been called. Locks out further migration.
    bool public migrated;

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
        uint256 _universeId,
        address _parentRegistry,
        address _initialOwner,
        address _arbitrator,
        uint256 _minBond
    ) {
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

        bondToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
        bondToken.forceApprove(address(realityETH), tokenAmount);

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
            0,
            uint256(uid),
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
     * @notice Finalize an approved attestation by inserting its leaf into the SMT.
     * @dev Caller supplies the current SMT proof for the (chainId, extcodehash) key.
     *      The slot must currently be empty (no current approved attestation for this
     *      contract). If a previous attestation occupies the slot it must be revoked
     *      first.
     * @param uid Attestation UID
     * @param siblings 256-element SMT proof siblings (high bit first)
     */
    function finalize(bytes32 uid, bytes32[] calldata siblings) external nonReentrant {
        Attestation storage att = _attestations[uid];

        if (att.timestamp == 0) revert AttestationNotFound();
        if (att.finalizedAt != 0) revert AlreadyFinalized();

        QuestionData memory q = questions[uid];
        if (address(q.realityInstance) == address(0)) revert AttestationNotFound();

        if (!q.realityInstance.isFinalized(q.questionId)) {
            revert ChallengePeriodActive();
        }

        bytes32 result = q.realityInstance.resultFor(q.questionId);

        // Treat INVALID/UNRESOLVED same as rejection so the submission reaches terminal state.
        if (uint256(result) == type(uint256).max || uint256(result) == type(uint256).max - 1) {
            att.finalizedAt = uint64(block.timestamp);
            att.revoked = true;
            emit AttestationFinalized(uid, false);
            return;
        }
        bool approved = (uint256(result) == 1);

        att.finalizedAt = uint64(block.timestamp);

        if (approved) {
            bytes32 key = _smtKey(att.chainId, att.extcodehash);
            bytes32 newLeaf = _approvedLeaf(att.chainId, att.extcodehash, att.metadataHash);

            // Slot must currently be empty (no current approved attestation).
            if (!_verifySmtProof(key, bytes32(0), siblings, smtRoot)) {
                revert SlotAlreadyOccupied();
            }

            bytes32 newRoot = _computeSmtRoot(key, newLeaf, siblings);
            smtRoot = newRoot;
            emit SmtRootUpdated(newRoot, key, bytes32(0), newLeaf);

            _specsByChainAndBytecode[att.chainId][att.extcodehash].push(uid);
            emit SpecIndexed(uid, att.chainId, att.extcodehash, att.blobHash, att.attester);
        } else {
            att.revoked = true;
        }

        emit AttestationFinalized(uid, approved);
    }

    // ========== REVOCATION ==========

    function proposeRevoke(bytes32 uid, uint256 tokenAmount) external nonReentrant whenNotPaused {
        if (address(bondToken) == address(0)) revert BondTokenNotSet();
        if (tokenAmount < minBond) revert BelowMinBond();

        _proposeRevokeValidation(uid);

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
     * @notice Finalize a revocation by overwriting the SMT slot back to empty.
     * @param uid Attestation UID
     * @param siblings SMT proof siblings showing the slot currently holds the
     *                 approved leaf for (att.chainId, att.extcodehash).
     */
    function finalizeRevoke(bytes32 uid, bytes32[] calldata siblings) external nonReentrant {
        Attestation storage att = _attestations[uid];

        if (att.revokeProposedAt == 0) revert NoRevokeProposal();
        if (att.revoked) revert AlreadyRevoked();

        QuestionData memory rq = revokeQuestions[uid];
        if (address(rq.realityInstance) == address(0)) revert AttestationNotFound();

        if (!rq.realityInstance.isFinalized(rq.questionId)) {
            revert ChallengePeriodActive();
        }

        bytes32 result = rq.realityInstance.resultFor(rq.questionId);

        if (uint256(result) == type(uint256).max || uint256(result) == type(uint256).max - 1) {
            att.revokeProposedAt = 0;
            att.revokeProposer = address(0);
            delete revokeQuestions[uid];
            emit RevokeFinalized(uid, false);
            return;
        }
        bool revokeApproved = (uint256(result) == 1);

        if (revokeApproved) {
            bytes32 key = _smtKey(att.chainId, att.extcodehash);
            bytes32 currentLeaf = _approvedLeaf(att.chainId, att.extcodehash, att.metadataHash);

            // Slot must currently hold the approved leaf for this attestation.
            if (!_verifySmtProof(key, currentLeaf, siblings, smtRoot)) {
                revert SlotNotApproved();
            }

            bytes32 newRoot = _computeSmtRoot(key, bytes32(0), siblings);
            smtRoot = newRoot;
            emit SmtRootUpdated(newRoot, key, currentLeaf, bytes32(0));

            att.revoked = true;
            att.revokeProposedAt = 0;
            att.revokeProposer = address(0);
            delete revokeQuestions[uid];

            emit RevokeFinalized(uid, true);
        } else {
            att.revokeProposedAt = 0;
            att.revokeProposer = address(0);
            delete revokeQuestions[uid];
            emit RevokeFinalized(uid, false);
        }
    }

    // ========== SMT VERIFIER ==========

    function smtKey(uint256 chainId, bytes32 extcodehash) external pure returns (bytes32) {
        return _smtKey(chainId, extcodehash);
    }

    function approvedLeaf(uint256 chainId, bytes32 extcodehash, bytes32 metadataHash)
        external pure returns (bytes32)
    {
        return _approvedLeaf(chainId, extcodehash, metadataHash);
    }

    function verifySmtProof(
        bytes32 key,
        bytes32 value,
        bytes32[] calldata siblings,
        bytes32 root
    ) external pure returns (bool) {
        return _verifySmtProof(key, value, siblings, root);
    }

    function computeSmtRoot(
        bytes32 key,
        bytes32 newValue,
        bytes32[] calldata siblings
    ) external pure returns (bytes32) {
        return _computeSmtRoot(key, newValue, siblings);
    }

    function _smtKey(uint256 chainId, bytes32 extcodehash) internal pure returns (bytes32) {
        return keccak256(abi.encode(chainId, extcodehash));
    }

    function _approvedLeaf(
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(LEAF_TYPEHASH, chainId, extcodehash, metadataHash));
    }

    /**
     * @dev Verify a (key, value) inclusion against `root`. Empty slots have
     *      value = bytes32(0). Walks bits of `key` from most-significant to
     *      least-significant; sibling i is the sibling at depth i (the bit
     *      at position 255 - i is the direction at that depth).
     */
    function _verifySmtProof(
        bytes32 key,
        bytes32 value,
        bytes32[] calldata siblings,
        bytes32 root
    ) internal pure returns (bool) {
        if (siblings.length != SMT_DEPTH) return false;
        bytes32 node = value;
        uint256 k = uint256(key);
        unchecked {
            for (uint256 i = 0; i < SMT_DEPTH; ++i) {
                bytes32 sib = siblings[SMT_DEPTH - 1 - i];
                // Bit at level i (counting from leaf = level 0) is bit i of k.
                if ((k >> i) & 1 == 0) {
                    node = _hashNode(node, sib);
                } else {
                    node = _hashNode(sib, node);
                }
            }
        }
        return node == root;
    }

    /**
     * @dev Compute the SMT root that results from setting `key` to `newValue` using
     *      the current proof siblings for that key. Caller must already have
     *      verified the old value against the current root using the SAME siblings.
     */
    function _computeSmtRoot(
        bytes32 key,
        bytes32 newValue,
        bytes32[] calldata siblings
    ) internal pure returns (bytes32) {
        require(siblings.length == SMT_DEPTH, "siblings length");
        bytes32 node = newValue;
        uint256 k = uint256(key);
        unchecked {
            for (uint256 i = 0; i < SMT_DEPTH; ++i) {
                bytes32 sib = siblings[SMT_DEPTH - 1 - i];
                if ((k >> i) & 1 == 0) {
                    node = _hashNode(node, sib);
                } else {
                    node = _hashNode(sib, node);
                }
            }
        }
        return node;
    }

    /// @dev Two empty children must hash to bytes32(0) so a fully-empty tree has
    /// root bytes32(0). We special-case this; all other parents use keccak.
    function _hashNode(bytes32 left, bytes32 right) private pure returns (bytes32) {
        if (left == bytes32(0) && right == bytes32(0)) return bytes32(0);
        return keccak256(abi.encodePacked(left, right));
    }

    // ========== STRING HELPERS (for Reality.eth question params) ==========

    function _bytes32ToString(bytes32 value) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(66);
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

    function setBondToken(address _bondToken, address _realityETH) external onlyOwner {
        if (_bondToken == address(0)) revert InvalidToken();
        if (_realityETH == address(0)) revert InvalidRealityETH();

        configNonce++;
        bondToken = IERC20(_bondToken);
        realityETH = IRealityETH(_realityETH);

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
     * @notice One-shot migration of the SMT root from a precomputed off-chain
     *         reconstruction. Owner-trusted.
     * @dev Tree state itself is not imported — only the root. Off-chain consumers
     *      reconstruct the full tree from event history (or external DA) to
     *      generate proofs for subsequent finalizes/revokes.
     * @param newRoot The SMT root computed off-chain
     */
    function migrate(bytes32 newRoot) external onlyOwner {
        if (migrated) revert AlreadyMigrated();
        if (newRoot == bytes32(0)) revert InvalidRoot();
        migrated = true;
        smtRoot = newRoot;
        emit Migrated(newRoot);
    }

    /**
     * @notice Verify an attestation against the current SMT root. Reverts on
     *         invalid proof. Designed for trustless hardware-wallet verification:
     *         valid proof → call succeeds, invalid → revert.
     */
    function verifyAttestation(
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash,
        bytes32[] calldata siblings
    ) external view {
        bytes32 key = _smtKey(chainId, extcodehash);
        bytes32 leaf = _approvedLeaf(chainId, extcodehash, metadataHash);
        if (!_verifySmtProof(key, leaf, siblings, smtRoot)) revert InvalidSmtProof();
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
        return smtRoot;
    }

    // ========== ADMIN FUNCTIONS ==========

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
