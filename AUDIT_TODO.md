# Audit TODO Findings

Security audit findings for v1-core. Track and address each item below.

---

## HIGH (3 findings)

All in `IncentivePool` — involve direct fund loss.

### H-1: `claimForSpec` sends funds to `address(0)` for imported attestations

- **File:** `src/economics/IncentivePool.sol` (line 311)
- **Description:** `importMigratedAttestation` stores attestations with `attester = address(0)` (KaiSignRegistry.sol line 739). When `claimForSpec` is called for such a UID, `_transferWithFee(poolAmount, att.attester, isToken)` sends the entire pool to `address(0)`, permanently burning the funds.
- **Suggested fix:** Add a guard in `claimForSpec`: `if (att.attester == address(0)) revert ZeroAttester();` or allow the caller to specify a valid recipient for imported attestations.

---

### H-2: `clawbackIncentive` underflows after spec claim drains pool

- **File:** `src/economics/IncentivePool.sol` (line 395)
- **Description:** `claimForSpec` (line 308) zeroes `poolByBytecode[extcodehash] = 0`, but individual `Incentive` structs are never marked as claimed. A contributor calling `clawbackIncentive` after a claim triggers `poolByBytecode[extcodehash] -= amount`, which panics with arithmetic underflow (Solidity 0.8+).
- **Suggested fix:** Mark each `Incentive` as claimed in `claimForSpec`, or add a guard in `clawbackIncentive` that checks whether the pool has already been claimed.

---

### H-3: `uint80` amount truncation silently loses funds

- **File:** `src/economics/IncentivePool.sol` (lines 52, 214, 225)
- **Description:** `Incentive.amount` is stored as `uint80` (max ~1.2M ether). On deposit, `uint80(amount)` silently truncates values exceeding `type(uint80).max`. Meanwhile `poolByBytecode[extcodehash] += amount` accumulates the full `uint256` value (line 225). This creates a permanent accounting mismatch: `clawbackIncentive` uses the truncated `incentive.amount`, so the contributor can never reclaim the excess.
- **Suggested fix:** Add `require(amount <= type(uint80).max, "Amount overflow")` before storing, or widen `amount` to `uint256`.

---

## MEDIUM (6 findings)

### M-1: `setBondToken` re-callable — griefing / template pollution

- **File:** `src/KaiSignRegistry.sol` (lines 617-630)
- **Description:** No "already set" guard exists. The owner can call `setBondToken` again, replacing `bondToken`, `realityETH`, and `templateId`. Existing open questions reference the old Reality.eth instance; new reveals/revokes would use the new instance, breaking resolution for any outstanding questions.
- **Suggested fix:** Add a one-shot guard: `require(address(bondToken) == address(0), "Already set");`

---

### M-2: Same-block UID/commitment collision overwrites

- **File:** `src/KaiSignRegistry.sol` (lines 160-166, 265-271)
- **Description:** `commitmentId` and `uid` both include `block.timestamp`. Two transactions from the same sender with identical parameters in the same block produce the same hash. The second `commitSpec` silently overwrites the first commitment; the second `revealSpec` silently overwrites the first attestation.
- **Suggested fix:** Include a nonce or auto-incrementing counter in the hash preimage to guarantee uniqueness within a block.

---

### M-3: `migrate` validation gaps

- **File:** `src/KaiSignRegistry.sol` (lines 638-652)
- **Description:** No validation that `_currentIdx > 0`. Calling with `_currentIdx = 0` computes a root from an all-zero frontier, potentially creating inconsistent state. No validation that `_frontier` elements are consistent with `_currentIdx`. The `merkleRoot == bytes32(0)` guard may be bypassable if `_computeRootFromFrontier(0)` returns `bytes32(0)`. Uses `require` strings instead of custom errors for consistency.
- **Suggested fix:** Add `require(_currentIdx > 0, "Invalid index")` and validate at least one non-zero frontier element. Use custom errors.

---

### M-4: `PermissionedBToken` uses single-step `Ownable` instead of `Ownable2Step`

- **File:** `src/Whitelistable.sol` (lines 12, 19), `src/PermissionedBToken.sol` (lines 4, 19)
- **Description:** `PermissionedBToken` inherits from `Whitelistable` which uses plain `Ownable` (single-step ownership transfer). Ownership can be irrecoverably transferred to a wrong address. `KaiSignRegistry` and `IncentivePool` both use `Ownable2Step` — this contract is inconsistent.
- **Suggested fix:** Change `Whitelistable` to inherit `Ownable2Step` instead of `Ownable`.

---

### M-5: Merkle tree never updated on revocation — stale proofs remain valid

- **File:** `src/KaiSignRegistry.sol` (lines 509-527)
- **Description:** The incremental Merkle tree is append-only; leaves are inserted with `revoked=false` and never updated. `verifyAttestationInclusion` blocks on-chain revoked UIDs, but off-chain verifiers using raw `verifyMerkleProof` against a stored proof will still get a valid result. There is no mechanism to prove exclusion or update a leaf.
- **Suggested fix:** Maintain a separate revocation bitmap or publish a revocation event that off-chain verifiers must check. Document clearly that Merkle proofs alone are insufficient — on-chain revocation status must always be verified.

---

### M-6: Missing `nonReentrant` on `importMigratedAttestation`

- **File:** `src/KaiSignRegistry.sol` (lines 699-705)
- **Description:** `revealSpec`, `finalize`, `proposeRevoke`, and `finalizeRevoke` all have `nonReentrant`. `importMigratedAttestation` writes to `_attestations[uid]` and pushes to `_specsByChainAndBytecode` but lacks the guard. Low risk currently (no external calls), but inconsistent with every other state-mutating function.
- **Suggested fix:** Add `nonReentrant` modifier for defense-in-depth consistency.

---

## LOW (7 findings)

### L-1: `verifyMigratedAttestation` idx=0 panics instead of custom error

- **File:** `src/KaiSignRegistry.sol` (line 683)
- **Description:** `idx` is `uint64`. When called with `idx = 0`, the expression `idx - 1` causes an arithmetic underflow panic. Unlike `importMigratedAttestation` (which checks `idx`), this function has no guard, producing a cryptic panic instead of a meaningful error.
- **Suggested fix:** Add `if (idx == 0) revert InvalidIndex();` before the subtraction.

---

### L-2: `claimForSpec` first-claim-takes-all per bytecode

- **File:** `src/economics/IncentivePool.sol` (lines 306-308)
- **Description:** The entire `poolByBytecode[extcodehash]` (accumulated from all contributors) is paid to the first approved spec for that bytecode. If a second spec is later approved, the pool is already zeroed — the second `claimForSpec` returns silently. Contributors who expected any valid spec to be rewarded see their funds go only to the first-past-the-post winner.
- **Suggested fix:** Document this behavior clearly, or implement per-incentive claiming so each contributor's deposit maps to a specific claim.

---

### L-3: No commit expiry mechanism

- **File:** `src/KaiSignRegistry.sol` (lines 86-93, 152-177)
- **Description:** `commitTimestamp` is stored but never checked for expiry. Commitments sit unrevealed indefinitely with no way to prune them. Stale commitments accumulate permanently.
- **Suggested fix:** Add an expiry duration (e.g., 24 hours) and allow cleanup of expired commitments, or check expiry at reveal time.

---

### L-4: `getLatestSpecForBytecode` unbounded loop

- **File:** `src/KaiSignRegistry.sol` (lines 768-780)
- **Description:** The loop iterates the full `_specsByChainAndBytecode[chainId][extcodehash]` array from newest to oldest. For a popular bytecode with many submissions (including rejected specs), this view function can hit the block gas limit and become uncallable.
- **Suggested fix:** Maintain a separate mapping for the latest valid spec per bytecode, updated on finalization and revocation.

---

### L-5: `setMinBond(0)` allowed — removes economic security

- **File:** `src/KaiSignRegistry.sol` (lines 632-636)
- **Description:** No lower-bound check on `_minBond`. Setting `minBond = 0` makes the check `if (tokenAmount < minBond) revert BelowMinBond()` always pass, allowing zero-bond reveals/revokes and bypassing the economic security assumption entirely.
- **Suggested fix:** Add `require(_minBond > 0, "Min bond must be positive");` or define a protocol minimum constant.

---

### L-6: `IncentivePool.receive()` accepts untracked ETH

- **File:** `src/economics/IncentivePool.sol` (line 482)
- **Description:** The bare `receive()` function accepts ETH without updating any accounting (`poolByBytecode`, `revokeRewardPool`, etc.). ETH sent directly to the contract is silently received and tracked by no mapping, recoverable only via `emergencyWithdraw`.
- **Suggested fix:** Remove `receive()` to reject direct ETH transfers, or add accounting logic.

---

### L-7: `PermissionedBToken._beforeTokenTransfer` checks `msg.sender` not `from`

- **File:** `src/PermissionedBToken.sol` (lines 48-66)
- **Description:** The whitelist restriction checks `msg.sender` (the transaction initiator) instead of `from` (the token holder). A whitelisted operator (e.g., Reality.eth) can call `transferFrom` to move tokens from any non-whitelisted user, bypassing the intended restriction.
- **Suggested fix:** Replace `msg.sender` checks with `from` checks: `if (from == owner()) return;` and `if (_isWhitelisted(from)) return;`.

---

## INFORMATIONAL (4 findings)

### I-1: `abi.encodePacked` for UID generation

- **File:** `src/KaiSignRegistry.sol` (lines 160-166, 252-258, 265-271), `src/economics/IncentivePool.sol` (lines 204-210)
- **Description:** `abi.encodePacked` with mixed-type arguments (`address` at 20 bytes adjacent to `uint256`/`bytes32`) creates ambiguous byte boundaries. In `IncentivePool`, a dynamic `string description` is packed after fixed types, further increasing collision risk. All current types are fixed-size so exploitation is impractical, but `abi.encode` is the canonical safe alternative.
- **Suggested fix:** Replace `abi.encodePacked` with `abi.encode` in all hash preimages.

---

### I-2: No test coverage for migration and import functions

- **Description:** `importMigratedAttestation`, `verifyMigratedAttestation`, `migrate`, and `finalize` lack dedicated test coverage. These are critical paths involving Merkle proof verification and state transitions.
- **Suggested fix:** Add unit and integration tests covering happy paths, edge cases (idx=0, invalid proofs, double-import), and revocation flows.

---

### I-3: Deploy script uses `type(uint256).max` approval

- **File:** `script/DeployAll.s.sol` (lines 82-83)
- **Description:** The deployment script grants infinite approval of `PermissionedBToken` to `KaiSignRegistry` on behalf of the deployer. If the registry were ever compromised, this unlimited allowance allows draining the deployer's entire token balance.
- **Suggested fix:** Approve only the amount needed per operation, or revoke the approval after deployment setup is complete.

---

### I-4: Deprecated `BondManager` still compiled

- **File:** `src/economics/deprecated/BondManager.sol`
- **Description:** The file lives in a `deprecated/` directory and is not imported by any active contract, but is still part of the compiled artifact surface. It contains the same issues as active code (re-callable `setBondToken`, zero `setMinBond`, untracked `receive()` ETH). Its presence risks accidental deployment.
- **Suggested fix:** Remove the file from the repository or exclude the `deprecated/` directory from compilation via `foundry.toml`.
