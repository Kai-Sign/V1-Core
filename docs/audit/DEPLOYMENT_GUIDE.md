# Deployment Guide - KaiSign v1.0.0

## Deployment Configuration

All deployment parameters and scripts are maintained in:
- **Deployment Script**: `/script/DeployKaiSign.s.sol`
- **Configuration**: Uses CREATE2 for deterministic addresses

### Current Deployment Parameters (Sepolia)

As configured in the deployment script:
- **Reality.eth**: `0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA`
- **Arbitrator**: `0x05B942fAEcfB3924970E3A28e0F230910CEDFF45`
- **Treasury**: `0x7D8730aD11f0D421bd41c6E5584F20c744CBAf29`
- **Min Bond**: 0.01 ETH
- **Salt**: `0x319d4829c8512c09bedf1688c873a330c0c0888875b02da9f06256b59c99ee36`

### Deployment Status

| Network | Status | Contract Address | Block | Verified |
|---------|--------|------------------|-------|----------|
| Mainnet | Not Deployed | - | - | - |
| Sepolia | Ready | Deterministic via CREATE2 | - | Pending |
| Local | Testing | Variable | - | N/A |

## Prerequisites

### Required Tools
- Foundry (forge, cast, anvil)
- Git
- Access to Ethereum RPC endpoints
- Funded deployer wallet

### Environment Setup
```bash
# Required environment variables
MAINNET_RPC_URL=        # Ethereum mainnet RPC
SEPOLIA_RPC_URL=        # Sepolia testnet RPC
ETHERSCAN_API_KEY=      # For contract verification
REALITY_ETH_ADDRESS=    # Reality.eth v3.0 deployment
ARBITRATOR_ADDRESS=     # Arbitrator contract address

# Keystore path (more secure than private key)
KEYSTORE_PATH=          # Path to your keystore file
```

## Keystore Setup

### Creating a Keystore File
```bash
# Create a new keystore with cast
cast wallet new ~/.foundry/keystores/deployer

# Or import existing private key to keystore
cast wallet import deployer --interactive
# Enter private key when prompted
# Enter password for keystore encryption

# Verify keystore
cast wallet list
```

### Using Hardware Wallet (Recommended for Mainnet)
```bash
# Using Ledger
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --ledger \
    --hd-paths "m/44'/60'/0'/0/0" \
    --sender <YOUR_ADDRESS>

# Using Trezor
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --trezor \
    --hd-paths "m/44'/60'/0'/0/0" \
    --sender <YOUR_ADDRESS>
```

## Deployment Process

### 1. Local Testing Deployment (Anvil)

```bash
# Start local node
anvil --fork-url $MAINNET_RPC_URL

# Deploy to local node using keystore
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --rpc-url http://localhost:8545 \
    --account deployer \
    --password-file ~/.foundry/.password \
    --broadcast
```

### 2. Testnet Deployment (Sepolia)

```bash
# Deploy to Sepolia with keystore
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --rpc-url $SEPOLIA_RPC_URL \
    --account deployer \
    --password-file ~/.foundry/.password \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv

# Alternative: Interactive password prompt (more secure)
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --rpc-url $SEPOLIA_RPC_URL \
    --account deployer \
    --interactive \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv

# Verify if not auto-verified
forge verify-contract \
    --chain-id 11155111 \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,address,uint256)" $REALITY_ETH_ADDRESS $ARBITRATOR_ADDRESS $MIN_BOND) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.20 \
    <DEPLOYED_ADDRESS> \
    src/KaiSign.sol:KaiSign
```

### 3. Mainnet Deployment

```bash
# IMPORTANT: Double-check all parameters before mainnet deployment

# Simulation first (no broadcast)
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --rpc-url $MAINNET_RPC_URL \
    --account deployer \
    --interactive \
    -vvvv

# Actual deployment with hardware wallet (RECOMMENDED)
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --rpc-url $MAINNET_RPC_URL \
    --ledger \
    --hd-paths "m/44'/60'/0'/0/0" \
    --sender <YOUR_ADDRESS> \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --slow \
    -vvvv

# Alternative: Deployment with keystore
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --rpc-url $MAINNET_RPC_URL \
    --account deployer \
    --interactive \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --slow \
    -vvvv

# Save deployment artifacts
cp broadcast/DeployKaiSign.s.sol/1/run-latest.json deployments/mainnet-$(date +%Y%m%d-%H%M%S).json
```

## Post-Deployment Configuration

### 1. Access Control Setup

```bash
# Grant admin role to multisig (using keystore)
cast send <KAISIGN_ADDRESS> \
    "grantRole(bytes32,address)" \
    $(cast keccak "ADMIN_ROLE") \
    <MULTISIG_ADDRESS> \
    --rpc-url $MAINNET_RPC_URL \
    --account deployer \
    --interactive

# Renounce deployer admin role (after multisig setup)
cast send <KAISIGN_ADDRESS> \
    "renounceRole(bytes32,address)" \
    $(cast keccak "ADMIN_ROLE") \
    <DEPLOYER_ADDRESS> \
    --rpc-url $MAINNET_RPC_URL \
    --account deployer \
    --interactive
```

### 2. Initial Configuration

```bash
# Set minimum bond if needed to change
cast send <KAISIGN_ADDRESS> \
    "setMinBond(uint256)" \
    $(cast to-wei 0.01 ether) \
    --rpc-url $MAINNET_RPC_URL \
    --account admin \
    --interactive

# Verify configuration
cast call <KAISIGN_ADDRESS> "minBond()" --rpc-url $MAINNET_RPC_URL
cast call <KAISIGN_ADDRESS> "realityETH()" --rpc-url $MAINNET_RPC_URL
cast call <KAISIGN_ADDRESS> "arbitrator()" --rpc-url $MAINNET_RPC_URL
cast call <KAISIGN_ADDRESS> "VERSION()" --rpc-url $MAINNET_RPC_URL
```

## Security Best Practices

### Keystore Management
```bash
# Secure keystore location
chmod 600 ~/.foundry/keystores/*
chmod 700 ~/.foundry/keystores

# Backup keystore (encrypt the backup)
tar -czf keystores-backup-$(date +%Y%m%d).tar.gz ~/.foundry/keystores/
gpg -c keystores-backup-*.tar.gz
# Store encrypted backup in secure location

# Never commit keystores to git
echo "keystores/" >> .gitignore
echo "*.keystore" >> .gitignore
echo ".password" >> .gitignore
```

### Password File Security
```bash
# Create password file with proper permissions
echo "your-secure-password" > ~/.foundry/.password
chmod 600 ~/.foundry/.password

# Alternative: Use environment variable
export KEYSTORE_PASSWORD="your-secure-password"
```

### Multi-Signature Deployment Process
For production deployments, use a multi-step process:

1. **Prepare Transaction**
```bash
# Generate deployment calldata
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --rpc-url $MAINNET_RPC_URL \
    --json \
    --silent \
    > deployment-calldata.json
```

2. **Submit to Multisig**
- Import calldata to Safe/Gnosis multisig
- Collect required signatures
- Execute deployment transaction

## Network Configuration

### Supported Networks

| Network | Chain ID | Reality.eth Address | Recommended RPC |
|---------|----------|-------------------|-----------------|
| Mainnet | 1 | 0x5b7dD1E86623548AF054A4985F7fc8Ccbb554E2c | Alchemy/Infura |
| Sepolia | 11155111 | [Check Reality.eth docs] | Alchemy/Infura |
| Local | 31337 | [Deploy locally] | http://localhost:8545 |

### Gas Configuration

```bash
# Recommended gas settings for mainnet
--with-gas-price 30gwei  # Adjust based on network conditions
--gas-limit 3000000       # Conservative limit

# Check current gas prices
cast gas-price --rpc-url $MAINNET_RPC_URL
```

## Deployment Verification

### Automated Verification
```bash
# Verify with constructor arguments
forge verify-contract \
    <DEPLOYED_ADDRESS> \
    src/KaiSign.sol:KaiSign \
    --chain sepolia \
    --constructor-args $(cast abi-encode "constructor(address,address,uint256)" $REALITY_ETH_ADDRESS $ARBITRATOR_ADDRESS $MIN_BOND) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch
```

### Manual Verification Steps
1. Go to Etherscan
2. Navigate to contract address
3. Click "Verify and Publish"
4. Select:
   - Compiler Type: Solidity (Single file)
   - Compiler Version: v0.8.20+commit.a1b79de6
   - License: Apache-2.0
5. Enable optimization with 200 runs
6. Paste flattened source code
7. Add constructor arguments (ABI-encoded)

## Monitoring & Maintenance

### Health Checks
```bash
# Check contract balance
cast balance <KAISIGN_ADDRESS> --rpc-url $MAINNET_RPC_URL

# Check admin role holders
cast call <KAISIGN_ADDRESS> \
    "getRoleMemberCount(bytes32)" \
    $(cast keccak "ADMIN_ROLE") \
    --rpc-url $MAINNET_RPC_URL

# Check pause status
cast call <KAISIGN_ADDRESS> "paused()" --rpc-url $MAINNET_RPC_URL

# Monitor total specs
cast call <KAISIGN_ADDRESS> "totalSpecs()" --rpc-url $MAINNET_RPC_URL
```

### Event Monitoring Script
```bash
# Monitor all events
cast logs \
    --address <KAISIGN_ADDRESS> \
    --from-block latest \
    --rpc-url $MAINNET_RPC_URL \
    --follow
```

### Emergency Procedures

#### Pause Contract
```bash
# Using keystore
cast send <KAISIGN_ADDRESS> \
    "pause()" \
    --rpc-url $MAINNET_RPC_URL \
    --account admin \
    --interactive

# Using hardware wallet
cast send <KAISIGN_ADDRESS> \
    "pause()" \
    --rpc-url $MAINNET_RPC_URL \
    --ledger
```

#### Unpause Contract
```bash
cast send <KAISIGN_ADDRESS> \
    "unpause()" \
    --rpc-url $MAINNET_RPC_URL \
    --account admin \
    --interactive
```

## Deployment Checklist

### Pre-Deployment
- [ ] Code audit completed
- [ ] All tests passing
- [ ] Keystore created and backed up
- [ ] Hardware wallet ready (for mainnet)
- [ ] RPC endpoints configured
- [ ] Gas prices checked
- [ ] Deployer wallet funded
- [ ] Reality.eth address verified
- [ ] Arbitrator address confirmed
- [ ] Multisig wallet prepared

### During Deployment
- [ ] Simulation run successful
- [ ] Constructor parameters verified
- [ ] Gas price appropriate
- [ ] Transaction confirmed
- [ ] Contract address noted

### Post-Deployment
- [ ] Contract verified on Etherscan
- [ ] Admin roles configured
- [ ] Ownership transferred to multisig
- [ ] Initial parameters set
- [ ] Events being monitored
- [ ] Deployment artifacts saved
- [ ] Documentation updated
- [ ] Team notified
- [ ] Public announcement prepared

## Troubleshooting

### Common Issues

**Issue**: "Keystore not found"
```bash
# List available accounts
cast wallet list

# Verify keystore path
ls -la ~/.foundry/keystores/
```

**Issue**: "Insufficient funds"
```bash
# Check deployer balance
cast balance <DEPLOYER_ADDRESS> --rpc-url $MAINNET_RPC_URL

# Estimate deployment cost
forge script script/DeployKaiSign.s.sol:DeployKaiSign \
    --rpc-url $MAINNET_RPC_URL \
    --estimate
```

**Issue**: "Transaction underpriced"
```bash
# Increase gas price
--with-gas-price 50gwei
# Or use priority fee
--priority-gas-price 2gwei
```