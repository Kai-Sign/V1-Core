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

---
---

# Re-Audit: Main Contracts (excluding economics/)

**Date:** 2026-02-25
**Scope:** `KaiSignRegistry.sol`, `PermissionedBToken.sol`, `Whitelistable.sol`, `RealityETH_ERC20_v3_2.sol`, `RealityETH_ERC20_Factory.sol`, cross-contract interactions, deploy scripts.

Findings below are **new** — they do not duplicate items H-1 through I-4 above.

---

## HIGH (2 findings)

### RH-1: Rejected revoke permanently prevents future revocation (Reality.eth question ID collision)

- **File:** `src/KaiSignRegistry.sol` (lines 398-429, 461-500)
- **Description:** When `finalizeRevoke` rejects a revoke (lines 496-499), `revokeProposedAt` and `revokeProposer` are reset to zero, but the Reality.eth question still exists. On a second `proposeRevoke`, `_buildRevokeQuestionParams` produces identical parameters and `nonce=0` is passed to `askQuestionWithMinBondERC20` (line 416), generating the same `question_id`. Reality.eth reverts with `"question must not exist"` (`stateNotCreated` modifier, RealityETH_ERC20_v3_2.sol line 432). The attestation becomes **permanently irrevocable**.
- **PoC:** Alice submits spec → approved → Bob proposes revoke → revoke rejected → Charlie tries proposeRevoke → reverts. Attestation can never be revoked.
- **Suggested fix:** Use an incrementing `revokeNonce` per UID as the `nonce` parameter to `askQuestionWithMinBondERC20`, or include a counter in `_buildRevokeQuestionParams`. Example: add `uint32 revokeAttempt` to the Attestation struct, increment in `_proposeRevokeValidation`, and pass `uint256(att.revokeAttempt)` as the nonce.

---

### RH-2: `importMigratedAttestation` idx bound uses evolving `merkleRootIdx` — allows duplicate attestation records

- **File:** `src/KaiSignRegistry.sol` (line 751)
- **Description:** The guard `if (idx > merkleRootIdx) revert IdxBeyondMigrated()` is intended to restrict imports to the migrated range. However, `merkleRootIdx` increases on every `finalize` (line 379) and `finalizeRevoke` (line 492). After post-migration finalization, an attacker can `importMigratedAttestation` for newly-created indices. The import UID differs from the finalize UID (different hash format: `abi.encode` vs `abi.encodePacked`), bypassing `AlreadyImported`. This creates duplicate Attestation records with `attester=address(0)` and pushes duplicates into `_specsByChainAndBytecode`.
- **PoC:** `migrate(frontier, 10)` → `finalize` new spec at idx=11 → attacker calls `importMigratedAttestation(chainId, extcodehash, metadataHash, 11, proof)` → second Attestation record for same leaf.
- **Suggested fix:** Store the migrated idx separately:
  ```solidity
  uint64 public migratedIdx;
  function migrate(...) external onlyOwner {
      ...
      migratedIdx = _currentIdx;
      ...
  }
  function importMigratedAttestation(...) external whenNotPaused {
      if (idx > migratedIdx) revert IdxBeyondMigrated();
      ...
  }
  ```

---

## MEDIUM (7 findings)

### RM-1: `setMinBond` does not increment `configNonce` — bypasses commit-reveal protection

- **File:** `src/KaiSignRegistry.sol` (lines 652-656, 276)
- **Description:** `setBondToken` increments `configNonce` (line 640), but `setMinBond` does not. Owner can raise `minBond` after a user commits, and the reveal passes the `configNonceSnapshot` check (line 276) but reverts at `BelowMinBond` (line 208). The user's commitment is effectively DoS'd.
- **PoC:** minBond=100 → user commits → owner calls setMinBond(1000) → user's reveal with tokenAmount=100 reverts.
- **Suggested fix:** Add `configNonce++;` to `setMinBond`.

---

### RM-2: Reality.eth question ID collision for identical spec resubmissions (`nonce=0` hardcoded)

- **File:** `src/KaiSignRegistry.sol` (lines 229, 416)
- **Description:** Both `revealSpec` and `proposeRevoke` pass `nonce=0` to `askQuestionWithMinBondERC20`. If the same spec parameters (blobHash, extcodehash, chainId) produce the same question string and config hasn't changed, the question ID collides. The first reveal succeeds but any subsequent identical spec submission permanently fails. Legitimate scenario: spec rejected, different user wants to resubmit the same spec.
- **PoC:** Alice reveals spec(X,Y,1) → rejected → Bob reveals same spec(X,Y,1) → Reality.eth reverts.
- **Suggested fix:** Use `uint256(uid)` as the `nonce` parameter instead of `0`.

---

### RM-3: `MIN_REVEAL_DELAY=1` second provides negligible front-running protection

- **File:** `src/KaiSignRegistry.sol` (lines 61, 273-274)
- **Description:** `MIN_REVEAL_DELAY=1` is compared against `block.timestamp` (seconds). The reveal can occur 1 second after the commit — effectively in the next block. On L2s with 1-2s block times, same-block commit-reveal is possible. Block proposers can manipulate timestamps within ~15s tolerance to include both commit and reveal in the same block. This negates the commit-reveal scheme's purpose.
- **Suggested fix:** Increase to a meaningful value: `uint256 public constant MIN_REVEAL_DELAY = 2 minutes;` (spans ~10 mainnet blocks).

---

### RM-4: Pausing blocks finalization of active Reality.eth questions

- **File:** `src/KaiSignRegistry.sol` (lines 340, 461, 860-866)
- **Description:** `finalize` and `finalizeRevoke` use `whenNotPaused`. If the owner pauses while Reality.eth questions are active, finalization is blocked. Reality.eth questions still finalize independently after timeout. Bonds can be claimed directly from Reality.eth, but the registry's state becomes inconsistent — approved attestations remain unindexed. After unpause, `finalize` works again, but during pause the registry denies service.
- **Suggested fix:** Remove `whenNotPaused` from `finalize` and `finalizeRevoke` (they only read from Reality.eth and write to registry state, accepting no user funds).

---

### RM-5: `proposeRevoke` lacks `configNonce` guard — economic mismatch after `setBondToken`

- **File:** `src/KaiSignRegistry.sol` (lines 398-430, 636-650)
- **Description:** `revealSpec` checks `configNonce` to prevent reveals after config changes, but `proposeRevoke` has no such check. After `setBondToken` changes the bond token and Reality.eth instance, `proposeRevoke` uses the NEW token/instance for the revoke question, while the original attestation used the OLD. If the new token is cheaper, an attacker can cheaply push through a revocation at a fraction of the original bond escalation cost.
- **Suggested fix:** Store the `configNonce` at attestation creation and check it in `proposeRevoke`, or always use the stored `questions[uid].realityInstance` for the revoke question's Reality.eth instance.

---

### RM-6: `SetBondToken.s.sol` does not whitelist KaiSignRegistry — `revealSpec`/`proposeRevoke` break

- **File:** `script/SetBondToken.s.sol` (lines 35-38)
- **Description:** The script only whitelists Reality.eth on the token (line 37), but does NOT whitelist KaiSignRegistry. When `revealSpec` calls `bondToken.safeTransferFrom(msg.sender, address(this), tokenAmount)` (KaiSignRegistry.sol line 213), both `msg.sender` and `to` are KaiSignRegistry — which is not whitelisted. PermissionedBToken's `_beforeTokenTransfer` will revert. `DeployAll.s.sol` correctly whitelists KaiSign (line 45), but anyone using `SetBondToken.s.sol` alone will deploy a non-functional registry.
- **Suggested fix:** Add `token.whitelist(kaisignAddr);` to `SetBondToken.s.sol`.

---

### RM-7: `_beforeTokenTransfer` blocks burns — no `burn()` function and `to=address(0)` fails whitelist

- **File:** `src/PermissionedBToken.sol` (lines 48-66)
- **Description:** When `_burn` is called, `_beforeTokenTransfer` fires with `to=address(0)`. The hook only short-circuits for `from=address(0)` (minting), not `to=address(0)`. Execution falls through to `require(_isWhitelisted(to))` — since `address(0)` is not whitelisted, burning reverts. Combined with no public `burn()` function, tokens are irrevocable once minted. If a `burn()` function is ever added, it will be broken.
- **Suggested fix:** Add `if (to == address(0)) return;` in `_beforeTokenTransfer`, or at minimum add a guarded `burn()` function with the bypass.

---

## LOW (12 findings)

### RL-1: Reality.eth `INVALID_RESULT` / `UNRESOLVED_ANSWER` permanently locks attestation as rejected

- **File:** `src/KaiSignRegistry.sol` (lines 354, 474)
- **Description:** `finalize` checks `uint256(result) == 1` for approval. Reality.eth special values (INVALID=0xFF..FF, UNRESOLVED=0xFF..FE) are treated as rejection. The attestation gets `revoked=true` and `finalizedAt=now`, permanently preventing re-finalization (`AlreadyFinalized`). Reality.eth has `reopenQuestion` for UNRESOLVED results, but the registry cannot leverage it.
- **Suggested fix:** Add explicit checks: `if (uint256(result) == type(uint256).max) revert InvalidResult();` and `if (result == bytes32(type(uint256).max - 1)) revert UnresolvedQuestion();` — allowing the question to be reopened without permanently locking the attestation.

---

### RL-2: `MerkleRootUpdated` event declared in interface but never emitted

- **File:** `src/interfaces/IKaiSignRegistry.sol` (line 53), `src/KaiSignRegistry.sol` (lines 378, 491, 686)
- **Description:** `event MerkleRootUpdated(bytes32 indexed newRoot, uint64 atIdx)` is declared but never emitted. Merkle root changes in `finalize`, `finalizeRevoke`, and `migrate` are invisible to off-chain indexers relying on this event.
- **Suggested fix:** Add `emit MerkleRootUpdated(merkleRoot, merkleRootIdx);` after each root update.

---

### RL-3: `computeAttestationLeaf` returns only the revoke leaf for revoked attestations

- **File:** `src/KaiSignRegistry.sol` (lines 505-522)
- **Description:** For revoked attestations, two leaves exist in the tree: the original approval leaf at `att.idx` and the revocation leaf at `att.revokeIdx`. `computeAttestationLeaf` always returns the revoke leaf when `att.revoked==true`. The original approval leaf is uncomputable through this helper. Off-chain auditors cannot verify historical inclusion.
- **Suggested fix:** Add a parameter: `computeAttestationLeaf(bytes32 uid, bool useRevokeLeaf)` or a second function.

---

### RL-4: `configNonce` (`uint32`) overflow bricks `setBondToken`

- **File:** `src/KaiSignRegistry.sol` (lines 75, 640)
- **Description:** `configNonce` is `uint32`. After 4,294,967,295 increments, the next `configNonce++` reverts with arithmetic overflow, permanently bricking `setBondToken`. Practically unreachable but a latent defect.
- **Suggested fix:** Use `uint256` for `configNonce`.

---

### RL-5: Fee-on-transfer / rebasing tokens cause revert or accounting errors

- **File:** `src/KaiSignRegistry.sol` (lines 213-214, 405-406), `src/external/RealityETH_ERC20_v3_2.sol` (lines 406-426)
- **Description:** `safeTransferFrom(user, registry, tokenAmount)` delivers less than `tokenAmount` for fee-on-transfer tokens. `forceApprove(realityETH, tokenAmount)` then approves more than the registry holds. Reality.eth's `transferFrom` reverts. For rebasing tokens, balances can decrease between operations. Reality.eth's `_deductTokensOrRevert` also assumes exact delivery. No validation in `setBondToken` prevents using such tokens.
- **Suggested fix:** Document that fee-on-transfer/rebasing tokens are unsupported, or use balance-before/after pattern.

---

### RL-6: Whitelisted address can drain tokens from any approver via `transferFrom`

- **File:** `src/PermissionedBToken.sol` (line 62)
- **Description:** Expands on L-7. A whitelisted address (e.g., Reality.eth) that calls `transferFrom(userA, attackerAddr, amount)` passes the hook because `_isWhitelisted(msg.sender)` returns true. The destination address `attackerAddr` does not need to be whitelisted. Any user who has approved a whitelisted address has their tokens movable to any arbitrary destination by that whitelisted address. While Reality.eth is trusted, this is a broader bypass than the msg.sender/from confusion alone.
- **Suggested fix:** Check `from` for whitelist status, not `msg.sender`. See L-7 fix.

---

### RL-7: Whitelister role persists after ownership transfer

- **File:** `src/Whitelistable.sol` (line 20), `src/PermissionedBToken.sol` (lines 24-25)
- **Description:** When `transferOwnership(newOwner)` is called, `whitelister` remains set to the old owner. The old owner retains whitelist control until the new owner explicitly calls `updateWhitelister`. Window of stale privilege exists between ownership transfer and whitelister update.
- **Suggested fix:** Override `transferOwnership` to auto-update `whitelister`, or document the required `updateWhitelister` call.

---

### RL-8: No supply cap on `mint()` — unbounded token inflation

- **File:** `src/PermissionedBToken.sol` (lines 29-31)
- **Description:** `mint` has no maximum supply cap. A compromised owner key can inflate supply indefinitely, diluting existing holders and making bond escalation costs negligible.
- **Suggested fix:** Add `uint256 public immutable maxSupply` with a check in `mint`.

---

### RL-9: `batchMint` unbounded gas — no recipient limit

- **File:** `src/PermissionedBToken.sol` (lines 34-38)
- **Description:** No upper bound on `recipients.length`. Each `_mint` costs ~50-75k gas. Block gas limit (~30M) allows ~400-600 recipients. Larger arrays revert, wasting gas. Also mints the same `amount` to all recipients — no variable amounts.
- **Suggested fix:** Add `require(recipients.length <= 500)` or accept a `uint256[] amounts` array.

---

### RL-10: `RealityETH_ERC20_Factory._deployProxy` — missing `create` return value check

- **File:** `src/external/RealityETH_ERC20_Factory.sol` (lines 91-101)
- **Description:** The `create` opcode returns `address(0)` on failure. `_deployProxy` does not check `result != address(0)`. If `create` fails, subsequent calls to `IRealityETH_ERC20(address(0)).setToken()` may exhibit undefined behavior. In practice, `createTemplate` returns `uint256` and calling it on `address(0)` would fail on ABI decode, providing implicit protection — but explicit is safer.
- **Suggested fix:** Add `require(result != address(0), "Proxy deployment failed");` after the assembly block.

---

### RL-11: `renounceOwnership` creates irrecoverable frozen state for PermissionedBToken

- **File:** `src/Whitelistable.sol` inherits `Ownable` which has `renounceOwnership()`
- **Description:** If owner calls `renounceOwnership()`, no one can call `mint`, `batchMint`, `updateWhitelister`, or `transferOwnership`. The current whitelister retains their role permanently. The token becomes permanently frozen for minting. The `msg.sender == owner()` bypass in `_beforeTokenTransfer` compares against `address(0)` — effectively disabled.
- **Suggested fix:** Override `renounceOwnership` to revert: `function renounceOwnership() public pure override { revert("Cannot renounce"); }`

---

### RL-12: Bond fee (2.5%) permanently locks tokens in Reality.eth contract

- **File:** `src/external/RealityETH_ERC20_v3_2.sol` (lines 866-869)
- **Description:** The 2.5% fee (1/40th) deducted from intermediate bonds during `claimWinnings` is not transferred anywhere — it remains locked in the Reality.eth contract permanently. No recovery mechanism exists. Over time, bTokens accumulate irretrievably in Reality.eth, creating deflationary pressure on the token supply.
- **Suggested fix:** Document this behavior in system documentation. Account for locked tokens in tokenomics. This is by design in Reality.eth.

---

## INFORMATIONAL (7 findings)

### RI-1: `revokeQuestions` mapping not cleared on revoke rejection

- **File:** `src/KaiSignRegistry.sol` (lines 495-499)
- **Description:** When `finalizeRevoke` rejects a proposal, `revokeProposedAt` and `revokeProposer` are reset, but `revokeQuestions[uid]` retains stale `QuestionData`. Wastes storage and confuses off-chain readers. Also contributes to RH-1 (question ID collision).
- **Suggested fix:** Add `delete revokeQuestions[uid];` in the rejection branch. (Does not fully fix RH-1 — the Reality.eth question still exists.)

---

### RI-2: Migrated attestation proofs become stale after any new tree insertion

- **File:** `src/KaiSignRegistry.sol` (lines 724, 769)
- **Description:** `verifyMigratedAttestation` and `importMigratedAttestation` verify proofs against the current `merkleRoot`, which changes on every `finalize`/`finalizeRevoke`. Proofs computed at time T are invalid at T+1. Creates race conditions for `importMigratedAttestation` and makes `verifyMigratedAttestation` fragile.
- **Suggested fix:** Store the migrated root separately (`bytes32 public migratedMerkleRoot`) and verify import/verify proofs against it.

---

### RI-3: Factory templates differ from implementation constructor templates

- **File:** `src/external/RealityETH_ERC20_Factory.sol` (lines 109-113), `src/external/RealityETH_ERC20_v3_2.sol` (lines 258-263)
- **Description:** Factory creates 5 templates with `"category"` field; constructor creates 6 with `"description"` field (plus `"hash"` type). Proxy instances have different template schemas than direct deployments. Not relevant for KaiSignRegistry (which creates its own template) but could confuse other consumers.
- **Suggested fix:** Align factory templates with constructor templates if consistency is desired.

---

### RI-4: `RealityETH.submitAnswerForERC20` allows crediting answers to arbitrary addresses

- **File:** `src/external/RealityETH_ERC20_v3_2.sol` (lines 507-516)
- **Description:** `msg.sender` pays the bond but `answerer` parameter receives winnings. By design for delegation, but the UX risk is that users could be tricked into paying bonds with winnings directed elsewhere.
- **Suggested fix:** Document the `answerer` parameter prominently. No contract change needed.

---

### RI-5: Non-whitelisted users CAN receive bond winnings from Reality.eth

- **File:** `src/external/RealityETH_ERC20_v3_2.sol` (lines 40-46), `src/PermissionedBToken.sol` (line 62)
- **Description:** When a user calls `Reality.eth.withdraw()`, `msg.sender` in PermissionedBToken's context is Reality.eth (whitelisted), so `_isWhitelisted(msg.sender)` returns true. Any address can receive tokens from Reality.eth via `withdraw()`, regardless of whitelist status. By design ("whitelisted addresses can transfer to anyone"), but the whitelist only restricts P2P transfers, not receipt from whitelisted contracts.
- **Suggested fix:** Document as accepted design property. Ensure Reality.eth is never un-whitelisted while questions are pending.

---

### RI-6: Double ownership initialization emits redundant event

- **File:** `src/PermissionedBToken.sol` (line 24)
- **Description:** Ownable's constructor sets owner to `msg.sender`, then PermissionedBToken's constructor calls `_transferOwnership(_owner)`. Two `OwnershipTransferred` events are emitted during deployment. If `_owner == msg.sender`, the second is a no-op transfer. Cosmetic issue for indexers.
- **Suggested fix:** No action needed. Document that the first event should be ignored by indexers.

---

### RI-7: Whitelisting `address(0)` is not prevented

- **File:** `src/Whitelistable.sol` (lines 63-65, 103-104)
- **Description:** `_whitelist` does not validate against `address(0)`. While OZ ERC20 prevents transfers to `address(0)` internally, setting `_whitelisted[address(0)] = true` is a logic error with no practical impact on current code but could interact poorly with future changes.
- **Suggested fix:** Add `require(_account != address(0))` in `_whitelist`.
