# KaiSignRegistry Audit Guide

High-level documentation for auditors reviewing KaiSignRegistry.sol.

---

## 1. Contract Overview

- **ERC7730 clear signing metadata registry** on L1
- Supports **all chains** via `chainId + extcodehash` indexing
- **Reality.eth bond escalation** for decentralized validation
- **Commit-reveal** to prevent front-running

---

## 2. Architecture Diagram

```
User Flow:
  commitSpec() → revealSpec{ETH}() → Reality.eth question → finalize() → Merkle tree
                    │                        │
                    └─ or revealSpecToken()  └─ 48h timeout + bond escalation
```

---

## 3. Trust Model

| Role | Capabilities | Trust Level |
|------|-------------|-------------|
| Owner | pause/unpause, setMinBond, setBondToken | Multisig recommended |
| Arbitrator | Resolve Reality.eth disputes | External (can be address(0)) |
| Anyone | Submit specs, propose revokes, finalize | Permissionless |

---

## 4. State Machine

### Attestation Lifecycle

```
UNCOMMITTED → COMMITTED → REVEALED/PENDING → FINALIZED (approved) → REVOKED
                                           → FINALIZED (rejected)
```

### Key Transitions

| Function | From | To |
|----------|------|-----|
| `commitSpec()` | UNCOMMITTED | COMMITTED |
| `revealSpec()` / `revealSpecToken()` | COMMITTED | PENDING |
| `finalize()` + approved | PENDING | APPROVED (indexed in merkle tree) |
| `finalize()` + rejected | PENDING | REJECTED (marked revoked) |
| `proposeRevoke()` | APPROVED | REVOKE_PROPOSED |
| `finalizeRevoke()` + approved | REVOKE_PROPOSED | REVOKED |
| `finalizeRevoke()` + rejected | REVOKE_PROPOSED | APPROVED (reset) |

---

## 5. Merkle Tree: Off-Chain Verification

### Purpose

The merkle tree enables hardware wallets and off-chain verifiers to cryptographically prove a spec is valid **without querying the contract directly**.

### How It Works

```
On-chain:                          Off-chain (hardware wallet):
┌─────────────────────┐            ┌─────────────────────────────────┐
│ KaiSignRegistry     │            │ Ledger / Trezor / etc           │
│                     │            │                                 │
│ merkleRoot: 0xabc   │  ───────>  │ 1. Receive merkleRoot from L1   │
│ (checkpoint state)  │            │ 2. Receive spec + proof         │
│                     │            │ 3. Verify proof locally         │
└─────────────────────┘            │ 4. Trust spec if valid          │
                                   └─────────────────────────────────┘
```

### Leaf Structure (EIP-712 Typed)

```solidity
bytes32 leaf = keccak256(abi.encode(
    LEAF_TYPEHASH,       // Domain separator
    att.chainId,         // Target chain
    att.extcodehash,     // Contract bytecode hash
    att.metadataHash,    // keccak256(ERC7730 metadata)
    att.idx,             // Position in tree (1-based)
    att.revoked          // Revocation status
));
```

### Why This Matters for Auditors

- Only **approved** specs enter the merkle tree (rejected specs never indexed)
- `idx` is assigned at finalization and is **append-only** - cannot reorder
- Hardware wallets don't need to trust any server - just verify proof against L1 root
- Revoked specs have `revoked = true` in leaf - verifiers must check this flag

### Verification Functions

| Function | Purpose |
|----------|---------|
| `verifyMerkleProof()` | Pure function to verify any leaf + proof + index |
| `verifyAttestationInclusion()` | Convenience wrapper using current `merkleRoot` |
| `computeAttestationLeaf()` | Compute leaf hash from attestation data |

---

## 6. Key Storage Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_attestations` | `mapping(bytes32 => Attestation)` | Core attestation data |
| `_specsByChainAndBytecode` | `mapping(chainId => mapping(extcodehash => uid[]))` | Index for lookups |
| `merkleRoot` | `bytes32` | Current checkpoint state |
| `merkleRootIdx` | `uint64` | Index at which merkleRoot was set |
| `currentIdx` | `uint64` | Monotonically increasing (1-based) |
| `questionIds` | `mapping(uid => questionId)` | Reality.eth question for spec |
| `revokeQuestionIds` | `mapping(uid => questionId)` | Reality.eth question for revoke |
| `bondToken` | `IERC20` | `address(0)` = ETH mode, else bToken mode |

---

## 7. Key Invariants

1. **idx monotonically increases** - `currentIdx` only increments, never decreases
2. **Only approved specs indexed** - Rejected specs never enter merkle tree
3. **finalizedAt is immutable** - Set exactly once when finalized
4. **Revoked specs cannot be un-revoked** - No path from REVOKED back to APPROVED
5. **revokeProposedAt requires finalization** - Can only propose revoke on finalized attestations
6. **Commit must precede reveal** - `commitmentId` must exist and not be revealed

---

## 8. External Dependencies

| Dependency | Address | Purpose |
|------------|---------|---------|
| Reality.eth ETH | immutable `realityETH` | Bond escalation (Phase 1) |
| Reality.eth ERC20 | mutable `realityETH_ERC20` | Bond escalation (Phase 2) |
| OpenZeppelin Ownable2Step | inherited | 2-step ownership transfer |
| OpenZeppelin ReentrancyGuard | inherited | Reentrancy protection |
| OpenZeppelin Pausable | inherited | Emergency pause |
| OpenZeppelin SafeERC20 | used | Safe token transfers |

---

## 9. Attack Surface / Areas of Focus

| Area | Risk | Mitigation |
|------|------|------------|
| Commit-reveal timing | Front-running between commit and reveal | Commitment hides blobHash |
| Reality.eth manipulation | Counter-bonds can flip result | Economic security via bond escalation |
| Merkle proof validity | Invalid proofs could corrupt state | `_verifyMerkleUpdate()` verification |
| ETH/bToken mode switch | Pending ETH specs orphaned | Documented clean break |
| Reentrancy | External calls to Reality.eth, token transfers | ReentrancyGuard on all state-changing functions |
| Paused state | Blocks new operations | Owner-controlled, doesn't affect finalization reads |

---

## 10. Function Access Control Summary

| Function | Access | Reentrancy Guard | Pausable |
|----------|--------|------------------|----------|
| `commitSpec` | Anyone | No | Yes |
| `revealSpec` | Committer | Yes | Yes |
| `revealSpecToken` | Committer | Yes | Yes |
| `finalize` | Anyone | Yes | Yes |
| `proposeRevoke` | Anyone | Yes | Yes |
| `proposeRevokeToken` | Anyone | Yes | Yes |
| `finalizeRevoke` | Anyone | Yes | Yes |
| `setBondToken` | Owner | No | No |
| `setMinBond` | Owner | No | No |
| `pause/unpause` | Owner | No | N/A |

---

## 11. Test Coverage Reference

| Test Type | Location |
|-----------|----------|
| Unit tests | `test/unit/` |
| Fork tests | `test/fork/BTokenFork.t.sol` |
| Security tests | `test/security/SecurityTests.t.sol` |

---

## Related Documentation

- [bToken Fork Mechanism](./BTOKEN_FORK_MECHANISM.md) - Phase 1/2 transition details
