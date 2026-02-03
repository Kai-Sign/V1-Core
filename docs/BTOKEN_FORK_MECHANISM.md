# bToken Fork Mechanism

## Overview

KaiSignRegistry supports two operational phases for bond management:
- **Phase 1 (ETH Mode):** Bonds paid in native ETH
- **Phase 2 (bToken Mode):** Bonds paid in ERC20 token (e.g., governance token)

## Architecture

### Dual Reality.eth Instances

The registry maintains TWO Reality.eth connections:
- `realityETH` (immutable): ETH-based Reality.eth for Phase 1
- `realityETH_ERC20` (set on activation): ERC20 Reality.eth for Phase 2

```
┌─────────────────────────────────────────────────────────────┐
│                     KaiSignRegistry                          │
├─────────────────────────────────────────────────────────────┤
│  Phase 1 (ETH)              │  Phase 2 (bToken)             │
│  ─────────────              │  ────────────────             │
│  bondToken = address(0)     │  bondToken = bToken           │
│  realityETH (immutable)     │  realityETH_ERC20             │
│  revealSpec{value}()        │  revealSpecToken()            │
│  proposeRevoke{value}()     │  proposeRevokeToken()         │
└─────────────────────────────────────────────────────────────┘
```

### Mode Detection

```solidity
IERC20 public bondToken;  // address(0) = ETH mode

// Check current mode:
if (address(bondToken) == address(0)) {
    // Phase 1: ETH mode
} else {
    // Phase 2: bToken mode
}
```

## Phase 1: ETH Mode

### Deployment

```solidity
KaiSignRegistry registry = new KaiSignRegistry(
    1,                                              // universeId
    address(0),                                     // parentRegistry
    multisig,                                       // initialOwner
    attesters,                                      // initialAttesters
    0x5b7dD1E86623548AF054A4985F7fc8Ccbb554E2c,    // realityETH (mainnet)
    address(0),                                     // arbitrator (none)
    0.01 ether                                      // minBond
);
```

### Usage

```solidity
// Submit spec with ETH bond
bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
bytes32 uid = registry.revealSpec{value: 0.01 ether}(commitmentId, blobHash, nonce);

// Propose revocation with ETH bond
registry.proposeRevoke{value: 0.01 ether}(uid);
```

## Phase 2: bToken Activation

### One-Way Transition (CLEAN BREAK)

```solidity
// Owner activates bToken mode (PERMANENT)
registry.setBondToken(
    bTokenAddress,           // ERC20 token for bonds
    realityETH_ERC20Address  // ERC20 version of Reality.eth
);
```

**CRITICAL: This is a CLEAN BREAK transition:**

| Before Activation | After Activation |
|-------------------|------------------|
| ETH functions work | ETH functions revert |
| Pending ETH specs can finalize | Pending ETH specs become ORPHANED |
| Reality.eth ETH queried | Reality.eth ERC20 queried |

**What happens to pending ETH specs:**
- They CANNOT be finalized (wrong Reality.eth instance)
- They are effectively orphaned
- Users must re-submit in bToken mode

### Usage After Activation

```solidity
// Approve tokens first
bToken.approve(address(registry), tokenAmount);

// Submit spec with token bond
bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
bytes32 uid = registry.revealSpecToken(commitmentId, blobHash, nonce, tokenAmount);

// Propose revocation with token bond
bToken.approve(address(registry), tokenAmount);
registry.proposeRevokeToken(uid, tokenAmount);
```

### Mode Enforcement Errors

```solidity
// In bToken mode:
revealSpec{value}()     → revert UseRevealSpecToken()
proposeRevoke{value}()  → revert UseProposeRevokeToken()

// In ETH mode:
revealSpecToken()       → revert UseRevealSpecETH()
proposeRevokeToken()    → revert UseProposeRevokeETH()
```

## Fork Architecture (Universe System)

### Universe Concept

Each registry belongs to a "universe" - enabling EIGEN-style intersubjective forking:

```solidity
uint256 public immutable universeId;      // Unique universe identifier
address public immutable parentRegistry;  // Parent in fork chain
uint64 public forkTimestamp;              // When this universe forked
bytes32 public forkStateRoot;             // State at fork time
```

### Fork Scenarios

**Scenario 1: L1 → L2 Bridge**
```
Universe 1 (L1 Mainnet)
    └── Universe 2 (L2 Arbitrum) - reads L1 state via parentRegistry
```

**Scenario 2: Governance Dispute Fork**
```
Universe 1 (Original)
    ├── Universe 2 (Fork A) - Community A's choice
    └── Universe 3 (Fork B) - Community B's choice
```

### Creating a Child Universe

```solidity
KaiSignRegistry childRegistry = new KaiSignRegistry(
    2,                      // universeId = 2
    address(parentRegistry), // parentRegistry = L1 registry
    owner,
    attesters,
    realityETH,
    arbitrator,
    minBond
);
```

### Reading Cross-Universe State

```solidity
// Get state root at specific index
bytes32 root = registry.getStateRoot();
(bytes32 stateRoot, uint64 idx) = registry.getStateAtIdx(targetIdx);

// Verify inclusion in parent universe
bool valid = IKaiSignRegistry(parentRegistry).verifyAttestationInclusion(uid, proof);
```

## Function Reference

| Operation | ETH Function | bToken Function |
|-----------|--------------|-----------------|
| Submit Spec | `revealSpec{value}()` | `revealSpecToken(amount)` |
| Propose Revoke | `proposeRevoke{value}()` | `proposeRevokeToken(amount)` |

## Reality.eth Contract Addresses

### Mainnet
- ETH Version: `0x5b7dD1E86623548AF054A4985F7fc8Ccbb554E2c`
- ERC20 Version: Deploy with your bToken

### Sepolia
- ETH Version: `0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA`
- ERC20 Version: Deploy with your bToken

## Migration Checklist

### Before Activation
- [ ] Deploy bToken ERC20 contract
- [ ] Deploy Reality.eth ERC20 instance with your bToken
- [ ] Ensure sufficient bToken liquidity for participants
- [ ] **Notify users: all pending ETH specs will be orphaned**
- [ ] Set deadline for ETH spec finalization

### Activation
- [ ] Call `setBondToken(bToken, realityETH_ERC20)`
- [ ] Verify mode switched: `registry.bondToken() != address(0)`
- [ ] Update frontend to use token approval flow

### After Activation (CLEAN BREAK)
- [ ] **Old ETH-based attestations are ORPHANED** - cannot be finalized
- [ ] All pending ETH-mode specs must be re-submitted in bToken mode
- [ ] New submissions must use `revealSpecToken()`
- [ ] Update documentation and SDKs
- [ ] Monitor for users attempting ETH functions (will revert)

## Testing

### Fork Tests Available

```bash
# Run all bToken tests (requires Sepolia RPC)
SEPOLIA_RPC_URL="your-url" forge test --match-contract BTokenForkTest -vvv
```

**Tests included:**
- `test_SetBondToken` - Activation
- `test_SetBondToken_OnlyOwner` - Access control
- `test_SetBondToken_InvalidParams` - Validation
- `test_ModeEnforcement_*` - Mode switching
- `test_CleanBreak` - ETH attestations orphaned
- `test_UniverseFork` - Fork architecture

**Note:** Full bToken flow tests (revealSpecToken, proposeRevokeToken, finalization) require deploying an ERC20 Reality.eth instance, which is beyond Sepolia testnet scope.
