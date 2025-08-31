# Complete KaiSign Blob Workflow

## Overview
This guide provides the complete workflow for deploying and using KaiSign with EIP-4844 blob data.

## Contract Addresses
- **KaiSign Contract**: `0x054119c36e6c66029c3fBf3cE4979E54e3137b88` (Sepolia)
- **Your Blob Hash**: `0x018d49902c41b1bd2033ba7b25cfbf551ea8e6c57e0f89c2c1763c41e5698f5e`

## Step-by-Step Workflow

### 1. Commit Your Blob Hash

Run the commit script to create a commitment:

```bash
./run_commit.sh
```

Or manually:
```bash
forge script script/InteractWithBlob.s.sol:InteractWithBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 --keystore $HOME/.foundry/keystores/kaisignblob --broadcast -vvv
```

**Important**: Save the `Commitment ID` from the output!

Example output:
```
Commitment ID for reveal:
0x6fc49946e9c9aa3f05074c7cfb292358b9e689962aede354d7dde22b827faca2
```

### 2. Wait for Commit Period

Wait at least 5 minutes before revealing. This prevents front-running attacks.

### 3. Reveal Your Blob Spec

After waiting, reveal with the commitment ID from step 1:

```bash
./run_reveal.sh 0x6fc49946e9c9aa3f05074c7cfb292358b9e689962aede354d7dde22b827faca2
```

Or manually:
```bash
export COMMITMENT_ID=0x6fc49946e9c9aa3f05074c7cfb292358b9e689962aede354d7dde22b827faca2
forge script script/RevealBlob.s.sol:RevealBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 --keystore $HOME/.foundry/keystores/kaisignblob --broadcast --value 0.01ether -vvv
```

This will:
- Reveal your blob hash
- Pay the 0.01 ETH bond
- Create a spec entry in KaiSign
- Return a Spec ID

### 4. Query Blob Specs

Check that your spec was added:

```bash
./run_query.sh
```

Or manually:
```bash
forge script script/InteractWithBlob.s.sol:QueryBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 -vvv
```

### 5. Test with JavaScript

Test the deployed contract:

```bash
node testKaiSign.js
```

## Alternative: Using Private Key

If you prefer using a private key instead of keystore:

```bash
# Set your private key
export PRIVATE_KEY="your_private_key_here"

# Commit
forge script script/InteractWithBlob.s.sol:InteractWithBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 --private-key $PRIVATE_KEY --broadcast -vvv

# Wait 5 minutes...

# Reveal
export COMMITMENT_ID="commitment_id_from_above"
forge script script/RevealBlob.s.sol:RevealBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 --private-key $PRIVATE_KEY --broadcast --value 0.01ether -vvv
```

## What the Blob Contains

Your blob hash `0x018d49902c41b1bd2033ba7b25cfbf551ea8e6c57e0f89c2c1763c41e5698f5e` contains ERC-7730 metadata that describes:

- All KaiSign contract functions
- Parameter types and meanings
- Security warnings
- Human-readable descriptions

This metadata enables wallets to provide clear transaction signing experiences.

## Troubleshooting

### Keystore Password Issues
The keystore will prompt for a password. Enter it when asked.

### Commitment Not Found
- Ensure you're using the exact commitment ID from the commit transaction
- Wait the full 5 minutes before revealing

### Insufficient Funds
- Ensure your account has at least 0.01 ETH + gas fees for the reveal

### Wrong Chain
- Make sure you're on Sepolia (Chain ID: 11155111)
- RPC URL: `https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5`

## Contract Functions Reference

### commitSpec
```solidity
function commitSpec(
    bytes32 commitment,    // keccak256(blobHash, nonce)
    address targetContract,
    uint256 chainId
)
```

### revealSpec
```solidity
function revealSpec(
    bytes32 commitmentId,
    bytes32 blobHash,
    uint256 nonce
) payable returns (bytes32 specId)
```
Requires: 0.01 ETH bond

### getSpecsByContract
```solidity
function getSpecsByContract(
    address targetContract,
    uint256 chainId
) view returns (bytes32[] memory)
```

## Summary

1. **Commit** - Create commitment hash
2. **Wait** - 5 minute minimum  
3. **Reveal** - Submit blob hash with bond
4. **Query** - Verify spec was added
5. **Use** - Wallets can now use the metadata

Your ERC-7730 metadata is now linked to the KaiSign contract and can be validated through Reality.eth!