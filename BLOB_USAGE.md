# Using KaiSign with EIP-4844 Blob Data

This guide shows how to use the KaiSign contract with your blob hash from the EIP-4844 transaction.

## Your Blob Hash

The ERC-7730 metadata was successfully deployed as a blob with hash:
```
0x018d49902c41b1bd2033ba7b25cfbf551ea8e6c57e0f89c2c1763c41e5698f5e
```

This blob contains the KaiSign ERC-7730 specification that describes all contract functions and their parameters.

## Prerequisites

1. Deploy the KaiSign contract first (if not already deployed)
2. Update the `KAISIGN_ADDRESS` constant in the scripts with your deployed address
3. Set your target contract address in `TARGET_CONTRACT`

## Usage Flow

### Step 1: Commit Your Blob Hash

First, commit to submitting the blob spec. This creates a hash commitment that includes your blob hash and a nonce.

```bash
# Set your private key
export PRIVATE_KEY="your_private_key_here"

# Run the commit script
forge script script/InteractWithBlob.s.sol:InteractWithBlob \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  -vvv
```

**Important**: Save the `Commitment ID` from the output. You'll need it for revealing.

### Step 2: Wait for Commit Period

Wait at least 5 minutes (the minimum commit period) before revealing. This prevents front-running.

### Step 3: Reveal Your Blob Spec

After the waiting period, reveal your commitment with the blob hash and nonce:

```bash
# Set the commitment ID from step 1
export COMMITMENT_ID="0x..." # Use the value from commit script output

# Reveal with bond (0.01 ETH)
forge script script/InteractWithBlob.s.sol:RevealBlob \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --value 0.01ether \
  -vvv
```

This will:
- Reveal your blob hash
- Pay the 0.01 ETH bond
- Create a spec entry in KaiSign
- Link your ERC-7730 metadata to the target contract

### Step 4: Query Blob Specs

Check that your blob spec was successfully added:

```bash
forge script script/InteractWithBlob.s.sol:QueryBlob \
  --rpc-url $SEPOLIA_RPC_URL \
  -vvv
```

## Using with Keystore

If using a keystore file instead of private key:

```bash
# Commit
forge script script/InteractWithBlob.s.sol:InteractWithBlob \
  --rpc-url $SEPOLIA_RPC_URL \
  --keystore kaisignblob \
  --broadcast \
  -vvv

# Reveal (with bond)
forge script script/InteractWithBlob.s.sol:RevealBlob \
  --rpc-url $SEPOLIA_RPC_URL \
  --keystore kaisignblob \
  --broadcast \
  --value 0.01ether \
  -vvv
```

## Contract Functions Used

### commitSpec
```solidity
function commitSpec(
    bytes32 commitment,
    address targetContract,
    uint256 chainId
)
```
Creates a commitment to submit a spec. The commitment is `keccak256(blobHash, nonce)`.

### revealSpec
```solidity
function revealSpec(
    bytes32 commitmentId,
    bytes32 blobHash,
    uint256 nonce
) payable returns (bytes32 specId)
```
Reveals the commitment and creates the spec. Requires minimum bond (0.01 ETH).

### getSpecsForContract
```solidity
function getSpecsForContract(
    address targetContract,
    uint256 offset,
    uint256 limit
) view returns (bytes32[] memory)
```
Returns blob hashes for specs associated with a contract.

## What Happens Next?

Once your blob spec is submitted:

1. **Automatic Proposal**: If you provided the minimum bond (0.01 ETH), the spec is automatically proposed for validation
2. **Reality.eth Validation**: The spec can be validated through Reality.eth oracle
3. **Usage**: Wallets and tools can fetch the blob data using the blob hash to get the ERC-7730 metadata
4. **Blob Availability**: The blob data remains available on the network for ~18 days (4096 epochs)

## Blob Data Retrieval

To retrieve the actual ERC-7730 metadata from the blob:

1. Use an EIP-4844 compatible node with blob pool access
2. Query for blob with hash `0x018d49902c41b1bd2033ba7b25cfbf551ea8e6c57e0f89c2c1763c41e5698f5e`
3. Decode the blob data to get the JSON metadata

## Example Target Contracts

You can use this blob spec with any contract. Some examples:

- USDC on Sepolia: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- WETH on Sepolia: `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`
- Your own deployed contracts

## Troubleshooting

### "Commitment not found" error
- Make sure you're using the correct commitment ID
- Ensure enough time has passed since committing

### "Insufficient bond" error
- Include at least 0.01 ETH value when calling revealSpec

### "Already committed" error
- Each commitment can only be used once
- Use a different nonce for a new commitment

## Summary

Your blob transaction successfully stored ERC-7730 metadata on-chain using EIP-4844. This metadata can now be:
1. Linked to any smart contract via KaiSign
2. Validated through Reality.eth
3. Used by wallets to provide better UX for contract interactions
4. Retrieved from the blob pool while available (~18 days)