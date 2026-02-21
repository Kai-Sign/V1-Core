// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title IKaiSignRegistry
 * @notice Interface for KaiSign clear signing metadata registry
 * @dev Single registry on L1 for all chains with bond escalation and fork support
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
        uint64 idx;                 // Global index for merkle ordering
        bool revoked;               // Whether this attestation is revoked
        uint64 finalizedAt;         // When finalized (0 = not finalized)
        uint64 revokeProposedAt;    // When revoke was proposed (0 = no proposal)
        address revokeProposer;     // Who proposed the revoke (for incentive claims)
        uint64 revokeIdx;           // Tree index of revocation leaf (0 = not revoked on-tree)
    }

    // ========== EVENTS ==========
    event SpecIndexed(
        bytes32 indexed uid,
        uint256 indexed chainId,
        bytes32 indexed extcodehash,
        bytes32 blobHash,
        address attester,
        uint64 idx
    );

    event AttestationFinalized(
        bytes32 indexed uid,
        uint64 indexed idx,
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

    event MerkleRootUpdated(bytes32 indexed newRoot, uint64 atIdx);

    event MinBondUpdated(uint256 oldBond, uint256 newBond);

    event Migrated(bytes32 indexed merkleRoot, uint64 currentIdx);

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
    function finalize(bytes32 uid) external;

    // ========== REVOCATION ==========
    function proposeRevoke(bytes32 uid, uint256 tokenAmount) external;
    function finalizeRevoke(bytes32 uid) external;

    // ========== MERKLE HELPERS ==========
    function computeAttestationLeaf(bytes32 uid) external view returns (bytes32 leaf);
    function verifyMerkleProof(
        bytes32 leaf,
        bytes32[] calldata proof,
        uint256 index,
        bytes32 root
    ) external pure returns (bool valid);
    // ========== MIGRATION ==========
    function verifyMigratedAttestation(
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash,
        uint64 idx,
        bool revoked,
        bytes32[] calldata merkleProof
    ) external view;

    function importMigratedAttestation(
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash,
        uint64 idx,
        bytes32[] calldata merkleProof
    ) external;

    // ========== QUERIES ==========
    function getAttestation(bytes32 uid) external view returns (Attestation memory);
    function getSpecsForBytecode(uint256 chainId, bytes32 extcodehash) external view returns (bytes32[] memory);
    function getLatestSpecForBytecode(uint256 chainId, bytes32 extcodehash) external view returns (bytes32 uid, bool valid);

    // ========== STATE ==========
    function currentIdx() external view returns (uint64);
    function merkleRoot() external view returns (bytes32);
    function merkleRootIdx() external view returns (uint64);
    function universeId() external view returns (uint256);
    function parentRegistry() external view returns (address);

    // ========== REVOKE PROPOSER ==========
    function revokeProposers(bytes32 uid) external view returns (address);
}
