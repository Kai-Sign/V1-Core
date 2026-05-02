// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title IKaiSignRegistry
 * @notice Interface for KaiSign clear signing metadata registry
 * @dev Single registry on L1 for all chains with bond escalation and fork support.
 *      The on-chain commitment is a Sparse Merkle Tree of depth 256, keyed by
 *      keccak256(chainId, extcodehash). Only the root is stored on chain; all other
 *      tree state is reconstructible from events (off-chain DA tradeoff).
 */
interface IKaiSignRegistry {
    // ========== STRUCTS ==========
    struct Attestation {
        bytes32 uid;                // Unique identifier
        uint256 chainId;            // Target chain ID
        bytes32 extcodehash;        // Target contract bytecode hash
        bytes32 blobHash;           // EIP-4844 blob hash (commit-reveal only)
        bytes32 metadataHash;       // keccak256(canonical(metadata)) - provable content hash
        address attester;           // Who created this attestation
        uint64 timestamp;           // When it was created
        bool revoked;               // Whether this attestation is revoked
        uint64 finalizedAt;         // When finalized (0 = not finalized)
        uint64 revokeProposedAt;    // When revoke was proposed (0 = no proposal)
        address revokeProposer;     // Who proposed the revoke (for incentive claims)
        uint32 revokeAttempt;       // counter for revoke attempts (nonce uniqueness)
    }

    // ========== EVENTS ==========
    event SpecIndexed(
        bytes32 indexed uid,
        uint256 indexed chainId,
        bytes32 indexed extcodehash,
        bytes32 blobHash,
        address attester
    );

    event AttestationFinalized(
        bytes32 indexed uid,
        bool approved
    );

    event RevokeProposed(
        bytes32 indexed uid,
        address indexed proposer
    );

    event RevokeFinalized(
        bytes32 indexed uid,
        bool revoked
    );

    /// @dev Emitted whenever the SMT root changes. `oldLeaf` is the slot value before
    /// the update, `newLeaf` is the value after. Off-chain indexers reconstruct tree
    /// state from this stream.
    event SmtRootUpdated(
        bytes32 indexed newRoot,
        bytes32 indexed key,
        bytes32 oldLeaf,
        bytes32 newLeaf
    );

    event MinBondUpdated(uint256 oldBond, uint256 newBond);

    /// @dev Emitted on owner-initiated migration of the SMT root.
    event Migrated(bytes32 indexed smtRoot);

    // ========== COMMIT-REVEAL ==========
    function commitSpec(
        bytes32 commitment,
        uint256 chainId,
        bytes32 extcodehash
    ) external returns (bytes32 commitmentId);

    function revealSpec(
        bytes32 commitmentId,
        bytes32 blobHash,
        uint256 nonce,
        bytes32 metadataHash,
        uint256 tokenAmount
    ) external returns (bytes32 uid);

    // ========== FINALIZATION ==========
    /// @notice Finalize an attestation. Caller must supply the SMT proof for the
    /// (chainId, extcodehash) key showing the slot is currently empty.
    function finalize(bytes32 uid, bytes32[] calldata siblings) external;

    // ========== REVOCATION ==========
    function proposeRevoke(bytes32 uid, uint256 tokenAmount) external;

    /// @notice Finalize a revocation. Caller must supply the SMT proof for the
    /// (chainId, extcodehash) key showing the slot currently holds the approved leaf.
    function finalizeRevoke(bytes32 uid, bytes32[] calldata siblings) external;

    // ========== SMT VERIFIER ==========
    /// @notice Compute the SMT key for a (chainId, extcodehash) pair.
    function smtKey(uint256 chainId, bytes32 extcodehash) external pure returns (bytes32);

    /// @notice Compute the SMT leaf hash for an approved attestation.
    function approvedLeaf(uint256 chainId, bytes32 extcodehash, bytes32 metadataHash)
        external pure returns (bytes32);

    /// @notice Verify a (key, value) inclusion against a given SMT root. Empty slots
    /// have value bytes32(0); non-membership is proved by passing value=bytes32(0).
    function verifySmtProof(
        bytes32 key,
        bytes32 value,
        bytes32[] calldata siblings,
        bytes32 root
    ) external pure returns (bool);

    /// @notice Recompute an SMT root after setting (key) to (newValue), using the
    /// siblings of the current proof for that key.
    function computeSmtRoot(
        bytes32 key,
        bytes32 newValue,
        bytes32[] calldata siblings
    ) external pure returns (bytes32);

    // ========== MIGRATION ==========
    /// @notice One-shot migration: import a precomputed SMT root.
    function migrate(bytes32 newRoot) external;

    /// @notice Verify an attestation against the current SMT root (view-only,
    /// reverts on invalid proof). Designed for trustless hardware-wallet
    /// verification: valid proof → call succeeds, invalid → revert.
    function verifyAttestation(
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash,
        bytes32[] calldata siblings
    ) external view;

    // ========== QUERIES ==========
    function getAttestation(bytes32 uid) external view returns (Attestation memory);
    function getSpecsForBytecode(uint256 chainId, bytes32 extcodehash) external view returns (bytes32[] memory);
    function getLatestSpecForBytecode(uint256 chainId, bytes32 extcodehash) external view returns (bytes32 uid, bool valid);

    // ========== STATE ==========
    function smtRoot() external view returns (bytes32);
    function universeId() external view returns (uint256);
    function parentRegistry() external view returns (address);

    // ========== REVOKE PROPOSER ==========
    function revokeProposers(bytes32 uid) external view returns (address);
}
