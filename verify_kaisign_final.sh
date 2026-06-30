#!/bin/bash

# KaiSign Contract Verification Script (Final attempt)
# Contract Address: 0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719
# Network: Sepolia (Chain ID: 11155111)

echo "Verifying KaiSign contract..."
echo "Address: 0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719"
echo "Chain: Sepolia"

# Try verification with exact settings from foundry.toml
forge verify-contract 0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719 \
  --chain-id 11155111 \
  --etherscan-api-key GV7AQG968MWYI3YVGF75WPRVYMR28VR6MP \
  --compiler-version v0.8.20+commit.a1b79de6 \
  --constructor-args 0x000000000000000000000000af33dcb6e8c5c4d9ddf579f53031b514d19449ca00000000000000000000000005b942faecfb3924970e3a28e0f230910cedff450000000000000000000000007d8730ad11f0d421bd41c6e5584f20c744cbaf29000000000000000000000000000000000000000000000000002386f26fc1000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000001804c8ab1f12e6bbf3894d4083f33e07309d1f38 \
  --num-of-optimizations 200 \
  --via-ir \
  --watch \
  src/KaiSign.sol:KaiSign

echo "Verification submitted. Check status at: https://sepolia.etherscan.io/address/0x4dfea0c2b472a14cd052a8f9df9f19fa5cf03719"
