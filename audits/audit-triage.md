# Audit Findings Triage

**Date:** 2026-04-02
**Scope:** KaiSignRegistry.sol, PermissionedBToken.sol, Whitelistable.sol
**Source:** [GitHub Issues](https://github.com/muhammadaus/v1-core-new/issues)

---

## Summary

| Issue | Severity | Verdict | Action |
|-------|----------|---------|--------|
| H-01 | High | **Real bug** | Fix |
| M-01 | Medium | False positive | No change |
| M-02 | Medium | False positive | No change |
| M-03 | Medium | False positive (code inconsistency) | Fix inconsistency only |
| M-04 | Medium | False positive | No change |
| M-05 | Medium | False positive | No change |
| L-01 | Low | False positive | No change |
| L-02 | Low | False positive | No change |
| L-03 | Low | False positive | No change |
| L-04 | Low | False positive | No change |
| L-05 | Low | False positive | No change |
| L-06 | Low | False positive | No change |
| I-01 to I-10 | Informational | Acknowledged | No change |

---

## [H-01] Repeated `finalizeRevoke()` Drains Merkle Tree

**Verdict: Real bug — fix required**

`finalizeRevoke()` has no `att.revoked` guard and does not clear `revokeProposedAt`, `revokeProposer`, or `revokeQuestions[uid]` after a successful revoke. Since the Reality.eth question is already finalized and permanently returns YES, anyone can call `finalizeRevoke(uid)` repeatedly at gas cost only (no bond required). Each call increments `currentIdx` and inserts a duplicate leaf, draining the bounded Merkle tree.

**Fix:** Add `if (att.revoked) revert AlreadyRevoked();` guard and clear state after successful revoke.

---

## [M-01] Migrated Attestation Verification Uses Mutable Live Root

**Verdict: False positive**

This is how incremental Merkle trees work. The root evolves as leaves are appended. Proofs must be computed against the current root. Every system using incremental Merkle trees (Tornado Cash, Semaphore, rollups) works this way. Migrated leaves remain in the tree — proofs are recomputed off-chain against the latest root. A frozen `migrationRoot` would create confusing dual-root semantics with no practical benefit.

---

## [M-02] `minBond = 0` Enables Zero-Cost Spam

**Verdict: False positive**

`setMinBond()` is `onlyOwner`. The owner is trusted via `Ownable2Step`. Setting `minBond = 0` is a governance decision (e.g., during testing or bootstrap). Even at zero, the attacker pays gas, and Reality.eth has its own bond escalation mechanics that provide economic protection. A malicious owner has far more damaging actions available than setting `minBond = 0`.

---

## [M-03] Reality.eth INVALID/UNRESOLVED Answers Freeze Flows

**Verdict: False positive — but fixing code inconsistency**

**`finalize()` freeze — not a bug.** The revert means `finalizedAt` stays 0, so the attestation is stuck, but the user can re-submit the same spec via `commitSpec()` → `revealSpec()` which creates a new uid (includes `block.timestamp`). The stuck attestation is dead state, not a permanent freeze of the spec.

**`finalizeRevoke()` freeze — not practically exploitable.** Forcing an INVALID answer on Reality.eth requires winning the bond escalation, which costs real money. An attacker wealthy enough to force INVALID could also force a NO answer at the same cost. The economic attack is identical. However, the NO path handles cleanup gracefully (resets `revokeProposedAt`, clears `revokeQuestions`) while INVALID/UNRESOLVED reverts — this is a code inconsistency. INVALID/UNRESOLVED should be treated the same as rejection for cleanup purposes.

**Fix:** Handle INVALID/UNRESOLVED in `finalizeRevoke()` by resetting proposal state (same as rejection path) instead of reverting.

---

## [M-04] Whitelister Can Remove Critical Protocol Addresses

**Verdict: False positive**

The whitelister is a trusted role appointed by the owner via `updateWhitelister()`. This finding describes admin misuse of a trusted role. Adding protected addresses increases complexity for a scenario that requires a compromised administrator. The owner can restore whitelist state or rotate the whitelister via `updateWhitelister()`.

---

## [M-05] `renounceOwnership()` Remains Enabled

**Verdict: False positive**

`renounceOwnership()` is the Stage 2 decentralization path. Progressive decentralization (Stage 0 → Stage 1 → Stage 2) requires the ability to remove the admin key entirely once the protocol is mature. Disabling `renounceOwnership()` would permanently lock in admin key dependency, preventing the protocol from ever reaching full decentralization. The 2-step transfer in `Ownable2Step` already protects against accidental ownership transfers.

---

## [L-01] Whitelist Bypass via `msg.sender` Check

**Verdict: False positive**

The `msg.sender` check is correct for the system's actual use case. The bypass scenario requires a whitelisted contract that (a) holds an ERC20 allowance from a non-whitelisted user AND (b) exposes a code path calling `transferFrom(thatUser, arbitraryDest, amount)`. No contract in the system does this:

- Reality.eth only does `transferFrom(msg.sender, address(this), tokens)` — pulls from caller to itself.
- Registry does `safeTransferFrom(msg.sender, address(this), amount)` — same pattern.
- Reality.eth withdrawals use `transfer(msg.sender, bal)` — sends from itself to caller.

No whitelisted contract routes tokens between two arbitrary third parties.

---

## [L-02] Owner Configuration Changes Invalidate Pending Commitments

**Verdict: False positive**

This is intentional design. The `configNonce` mechanism exists precisely to invalidate stale commitments when configuration changes. If `minBond` or `bondToken` changes, old commitments were made under different economic assumptions — allowing them to proceed would be the actual bug. The finding acknowledges "no fund loss or permanent protocol damage."

---

## [L-03] Incorrect Migration Frontier Produces Irrecoverable Corrupted Merkle Root

**Verdict: False positive**

`migrate()` is `onlyOwner` and one-time. The owner is trusted. Adding an `_expectedRoot` parameter is circular — the owner computes both the frontier and the expected root off-chain, so if one is wrong the other likely is too. The real mitigation is operational: test migration on a fork before executing on mainnet. The `AlreadyMigrated` guard correctly prevents accidental re-migration that would corrupt post-migration state.

---

## [L-04] Approved Finalization Before Migration Disables `migrate()`

**Verdict: False positive**

This is a deployment sequencing concern, not a code bug. The intended flow is: deploy → migrate → unpause → normal operation. The contract starts paused, so `commitSpec()` and `revealSpec()` (both `whenNotPaused`) can't be called before migration. The code correctly prevents migration after the tree is already in use, which would corrupt existing leaves.

---

## [L-05] Revocation Uses Current realityETH Instead of Approval-Time Instance

**Verdict: False positive**

Using the current `realityETH` is correct. If the oracle was migrated (e.g., bug fix, upgrade), revocations should go through the current trusted oracle, not a potentially deprecated instance. Binding revocation to an old oracle could mean using a compromised or unsupported contract. The finding acknowledges it "depends on an owner-driven configuration change."

---

## [L-06] `setBondToken()` Leaves `minBond` Temporarily Miscalibrated

**Verdict: False positive**

`configNonce++` in `setBondToken()` invalidates all pending commitments immediately, so no one can exploit the window between `setBondToken()` and `setMinBond()` calls. The owner can batch both calls atomically via a multisig or batch transaction. This is operational hygiene, not a code vulnerability.

---

## [I-01 through I-10] Informationals

**Verdict: Acknowledged, no code changes**

- **I-01** (MIN_REVEAL_DELAY = 1): Intentional. Real front-running protection comes from sender-bound commitments.
- **I-02** (No ERC20 recovery): Operational risk, not a vulnerability. Can be added later if needed.
- **I-03** (Events don't expose full config): Cosmetic. Off-chain indexers can read state.
- **I-04** (Unused `onlyWhitelisted` modifier): Dead code, but harmless.
- **I-05** (Interface missing view functions): Interface is minimal by design.
- **I-06** (IRealityETH broader than needed): Code clarity, not security.
- **I-07** (Verify supports revoked, import doesn't): Intentional. `import` exists to make old specs revocable — importing already-revoked specs is pointless.
- **I-08** (Stale revoke metadata after approval): Fixed by H-01 cleanup.
- **I-09** (Burn exemption documentation): Documentation nit.
- **I-10** (PUSH0 opcode on pre-Shanghai chains): Build config concern, not a code issue.
