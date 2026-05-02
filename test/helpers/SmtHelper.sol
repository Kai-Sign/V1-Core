// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title SmtHelper
 * @notice Test-only Sparse Merkle Tree (depth 256) that mirrors the verification
 *         rules in KaiSignRegistry. Used by tests to construct (siblings, root)
 *         tuples; the contract under test only verifies — it never builds proofs.
 *
 * @dev Storage shape: only non-empty nodes are kept. Each node lives at a path
 *      bit-string from the root; we encode the path as `keccak256(bitsHigh, depth)`
 *      where bitsHigh is the upper `depth` bits of the key zero-extended. Leaves
 *      live at depth 256 keyed by the full 256-bit key. This is more memory than
 *      necessary but keeps the helper simple and deterministic.
 */
contract SmtHelper {
    uint256 internal constant DEPTH = 256;

    // path-hash => node hash. Empty subtrees are represented by absence (read as bytes32(0)).
    mapping(bytes32 => bytes32) internal _nodes;

    /// @notice Current root.
    bytes32 public root;

    /// @notice Set the slot at `key` to `value`. Returns the new root and the
    /// proof siblings that *led to the previous state* (these are exactly the
    /// siblings the contract needs to verify oldValue and compute newValue —
    /// before the update is applied).
    function update(bytes32 key, bytes32 value)
        external
        returns (bytes32 newRoot, bytes32[] memory siblings)
    {
        siblings = _proof(key);
        _setLeaf(key, value);
        newRoot = _recomputePath(key);
        root = newRoot;
    }

    /// @notice Get the proof siblings for `key` against the current state.
    /// Returned proof verifies whatever value is currently at `key` (which may
    /// be bytes32(0) for non-membership).
    function proof(bytes32 key) external view returns (bytes32[] memory) {
        return _proof(key);
    }

    /// @notice Read the current value at `key`.
    function get(bytes32 key) external view returns (bytes32) {
        return _nodes[_pathHash(key, DEPTH)];
    }

    // ========== INTERNALS ==========

    function _proof(bytes32 key) internal view returns (bytes32[] memory siblings) {
        siblings = new bytes32[](DEPTH);
        // siblings[0] = sibling at top of tree (depth 1 from root) ... siblings[255] = leaf-level sibling
        // To match the contract's MSB-first walk, siblings[i] is the sibling at level (i+1) from the root.
        uint256 k = uint256(key);
        for (uint256 d = 1; d <= DEPTH; ++d) {
            // At depth d, the bit that decides direction is bit (DEPTH - d) of the key.
            // Sibling lives at the same depth, opposite direction.
            uint256 bitIdx = DEPTH - d; // 0..255
            uint256 bit = (k >> bitIdx) & 1;
            // Path of self (depth d): top `d` bits of key.
            // Path of sibling: same top bits but with the d-th bit flipped.
            uint256 selfPathBits = k >> (DEPTH - d); // top d bits, right-aligned
            uint256 sibPathBits = selfPathBits ^ 1;  // flip the lowest of the d bits
            // bit unused beyond determining flip; suppress linter
            bit;
            siblings[d - 1] = _nodes[_pathHashBits(sibPathBits, d)];
        }
    }

    function _setLeaf(bytes32 key, bytes32 value) internal {
        _nodes[_pathHash(key, DEPTH)] = value;
    }

    function _recomputePath(bytes32 key) internal returns (bytes32) {
        uint256 k = uint256(key);
        bytes32 node = _nodes[_pathHash(key, DEPTH)];

        // Walk from leaf (depth DEPTH) up to root (depth 0).
        for (uint256 d = DEPTH; d >= 1; --d) {
            uint256 bitIdx = DEPTH - d;
            uint256 bit = (k >> bitIdx) & 1;
            uint256 selfPathBits = k >> (DEPTH - d);
            uint256 sibPathBits = selfPathBits ^ 1;
            bytes32 sib = _nodes[_pathHashBits(sibPathBits, d)];

            bytes32 parent;
            if (bit == 0) {
                parent = _hashNode(node, sib);
            } else {
                parent = _hashNode(sib, node);
            }

            // Persist parent at depth d-1 path.
            uint256 parentPathBits = selfPathBits >> 1;
            if (d - 1 == 0) {
                // root level
                _nodes[_pathHashBits(0, 0)] = parent;
            } else {
                _nodes[_pathHashBits(parentPathBits, d - 1)] = parent;
            }
            node = parent;

            if (d == 1) break;
        }
        return node;
    }

    function _hashNode(bytes32 left, bytes32 right) internal pure returns (bytes32) {
        if (left == bytes32(0) && right == bytes32(0)) return bytes32(0);
        return keccak256(abi.encodePacked(left, right));
    }

    function _pathHash(bytes32 key, uint256 depth) internal pure returns (bytes32) {
        uint256 k = uint256(key);
        uint256 bits = (depth == 0) ? 0 : (k >> (DEPTH - depth));
        return _pathHashBits(bits, depth);
    }

    function _pathHashBits(uint256 bits, uint256 depth) internal pure returns (bytes32) {
        return keccak256(abi.encode(bits, depth));
    }
}
