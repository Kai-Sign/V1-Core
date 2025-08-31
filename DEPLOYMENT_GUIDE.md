# KaiSign Deployment Guide

## Prerequisites

1. **Install Foundry**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Install Node.js dependencies** (for deployment helper)
   ```bash
   npm install
   ```

3. **Setup Environment Variables** (optional)
   ```bash
   cp .env.example .env
   # Edit .env with your RPC URLs and API keys
   ```

## Deployment Methods

### Method 1: Interactive Deployment Tool (Recommended)

Use the provided Node.js deployment helper for a guided deployment:

```bash
node deployBlob.js
```

This tool will:
- Guide you through network selection
- Help create or use an existing keystore
- Check wallet balance
- Compile and deploy the contract
- Save deployment information

### Method 2: Manual Deployment with Keystore

1. **Create a keystore file** (if you don't have one):
   ```bash
   cast wallet new kaisignblob
   ```
   
   Or import an existing private key:
   ```bash
   cast wallet import kaisignblob --interactive
   ```

2. **Check keystore address and fund it**:
   ```bash
   cast wallet address --keystore kaisignblob
   ```

3. **Deploy to Sepolia**:
   ```bash
   forge script script/DeployKaiSign.s.sol:DeployKaiSign \
     --rpc-url https://rpc.sepolia.org \
     --keystore kaisignblob \
     --broadcast \
     --verify \
     --etherscan-api-key YOUR_ETHERSCAN_KEY
   ```

4. **Deploy to Mainnet**:
   ```bash
   # First update addresses in DeployKaiSign.s.sol for mainnet
   forge script script/DeployKaiSign.s.sol:DeployKaiSign \
     --rpc-url https://eth.llamarpc.com \
     --keystore kaisignblob \
     --broadcast \
     --verify \
     --etherscan-api-key YOUR_ETHERSCAN_KEY
   ```

### Method 3: Deploy with Private Key (Less Secure)

```bash
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
  --rpc-url https://rpc.sepolia.org \
  --private-key YOUR_PRIVATE_KEY \
  --broadcast
```

## Contract Configuration

The deployment script uses these default values:

- **Reality.eth (Sepolia)**: `0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA`
- **Arbitrator**: `0x05B942fAEcfB3924970E3A28e0F230910CEDFF45`
- **Treasury**: `0x7D8730aD11f0D421bd41c6E5584F20c744CBAf29`
- **Min Bond**: `0.01 ETH`
- **Initial Admin**: Deployer address

To customize these values, edit `script/DeployKaiSign.s.sol` before deployment.

## Post-Deployment Workflows

### 1. Submit a Spec (Commit-Reveal Pattern)

```javascript
// Step 1: Commit
const blobHash = "0x..."; // Your blob hash from EIP-4844
const nonce = 12345; // Random nonce
const commitment = keccak256(encodePacked(blobHash, nonce));

await kaisign.commitSpec(commitment, targetContract, chainId);

// Step 2: Wait for commit period (default: 5 minutes)
await delay(5 * 60 * 1000);

// Step 3: Reveal with bond
const commitmentId = keccak256(encodePacked(
  commitment, 
  userAddress, 
  targetContract, 
  chainId, 
  commitTimestamp
));

await kaisign.revealSpec(commitmentId, blobHash, nonce, {
  value: ethers.parseEther("0.01") // MIN_BOND
});
```

### 2. Challenge a Spec

```javascript
// Challenge with Reality.eth question
await kaisign.challengeSpec(specId, questionId);
```

### 3. Query Specs

```javascript
// Get spec details
const spec = await kaisign.specs(specId);

// Get specs for a contract (paginated)
const specs = await kaisign.getSpecsForContract(
  targetContract, 
  offset, 
  limit
);

// Check commitment
const commitmentId = await kaisign.getCommitmentId(
  commitment,
  user,
  targetContract,
  chainId
);
```

### 4. Admin Functions

```javascript
// Add admin (only existing admin)
await kaisign.addAdmin(newAdminAddress);

// Remove admin
await kaisign.removeAdmin(adminAddress);

// Update parameters
await kaisign.updateMinBond(newMinBond);
await kaisign.updateTreasury(newTreasuryAddress);
```

## Verify Deployment

1. **Check contract on Etherscan**:
   ```
   https://sepolia.etherscan.io/address/YOUR_CONTRACT_ADDRESS
   ```

2. **Verify contract state**:
   ```bash
   # Check min bond
   cast call CONTRACT_ADDRESS "minBond()(uint256)" --rpc-url RPC_URL
   
   # Check treasury
   cast call CONTRACT_ADDRESS "treasury()(address)" --rpc-url RPC_URL
   
   # Check if address is admin
   cast call CONTRACT_ADDRESS "admins(address)(bool)" ADMIN_ADDRESS --rpc-url RPC_URL
   ```

## Security Considerations

1. **Keystore Security**:
   - Never commit keystore files to git
   - Use strong passwords for keystore encryption
   - Store keystore backups securely

2. **Contract Parameters**:
   - Ensure Reality.eth address is correct for your network
   - Set appropriate min bond amount
   - Configure trusted arbitrator address

3. **Deployment Verification**:
   - Always verify the deployed bytecode
   - Check constructor parameters on Etherscan
   - Test basic functionality after deployment

## Troubleshooting

### "Insufficient funds" error
- Check wallet balance: `cast balance YOUR_ADDRESS --rpc-url RPC_URL`
- Ensure you have enough ETH for gas + deployment costs

### "Keystore not found" error
- Verify keystore path is correct
- Check file permissions
- Create new keystore if needed: `cast wallet new kaisignblob`

### Compilation errors
- Run `forge clean` and retry
- Check Solidity version: `forge --version`
- Ensure all dependencies are installed: `forge install`

### Verification fails on Etherscan
- Ensure correct Etherscan API key
- Wait a few minutes after deployment
- Manually verify at: https://sepolia.etherscan.io/verifyContract