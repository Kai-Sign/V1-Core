#!/bin/bash

# KaiSign Deployment Script
# Uses the keystore file at ~/.foundry/keystores/kaisignblob

set -e

echo "🚀 KaiSign Deployment Script"
echo "=============================="
echo ""

# Default values
KEYSTORE_PATH="$HOME/.foundry/keystores/kaisignblob"
RPC_URL="${RPC_URL:-https://rpc.sepolia.org}"
ETHERSCAN_KEY="${ETHERSCAN_API_KEY:-}"

# Check if keystore exists
if [ ! -f "$KEYSTORE_PATH" ]; then
    echo "❌ Keystore not found at: $KEYSTORE_PATH"
    echo "Create it with: cast wallet new $KEYSTORE_PATH"
    exit 1
fi

# Get wallet address
echo "📋 Deployment Details:"
WALLET_ADDRESS=$(cast wallet address --keystore "$KEYSTORE_PATH")
echo "Deployer: $WALLET_ADDRESS"

# Check balance
BALANCE=$(cast balance "$WALLET_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo "Balance: $BALANCE wei"

# Convert balance to ETH for comparison
BALANCE_ETH=$(echo "$BALANCE" | awk '{printf "%.6f", $1/1e18}')
echo "Balance: $BALANCE_ETH ETH"

if (( $(echo "$BALANCE_ETH < 0.01" | bc -l) )); then
    echo "⚠️  Warning: Low balance. You need at least 0.01 ETH for deployment."
fi

echo ""
echo "Network: Sepolia"
echo "RPC URL: $RPC_URL"
echo ""

# Compile
echo "🔨 Compiling contracts..."
forge build

echo ""
echo "📤 Deploying KaiSign..."

# Deploy command
if [ -n "$ETHERSCAN_KEY" ]; then
    echo "✅ Etherscan verification enabled"
    forge script script/DeployKaiSign.s.sol:DeployKaiSign \
        --rpc-url "$RPC_URL" \
        --keystore "$KEYSTORE_PATH" \
        --broadcast \
        --verify \
        --etherscan-api-key "$ETHERSCAN_KEY" \
        -vvv
else
    echo "⚠️  No Etherscan API key provided, skipping verification"
    forge script script/DeployKaiSign.s.sol:DeployKaiSign \
        --rpc-url "$RPC_URL" \
        --keystore "$KEYSTORE_PATH" \
        --broadcast \
        -vvv
fi

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Check the broadcast folder for deployment details:"
echo "broadcast/DeployKaiSign.s.sol/11155111/run-latest.json"