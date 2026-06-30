#!/bin/bash

# Quick test different compiler versions
CONTRACT="0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719"
ARGS="0x000000000000000000000000af33dcb6e8c5c4d9ddf579f53031b514d19449ca00000000000000000000000005b942faecfb3924970e3a28e0f230910cedff450000000000000000000000007d8730ad11f0d421bd41c6e5584f20c744cbaf29000000000000000000000000000000000000000000000000002386f26fc1000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000001804c8ab1f12e6bbf3894d4083f33e07309d1f38"

echo "Testing v0.8.19..."
forge verify-contract $CONTRACT --chain-id 11155111 --etherscan-api-key GV7AQG968MWYI3YVGF75WPRVYMR28VR6MP --compiler-version v0.8.19+commit.7dd6d404 --constructor-args $ARGS --num-of-optimizations 200 src/KaiSign.sol:KaiSign &

echo "Testing v0.8.21..."
forge verify-contract $CONTRACT --chain-id 11155111 --etherscan-api-key GV7AQG968MWYI3YVGF75WPRVYMR28VR6MP --compiler-version v0.8.21+commit.d9974bed --constructor-args $ARGS --num-of-optimizations 200 src/KaiSign.sol:KaiSign &

echo "Testing 1 optimization run..."
forge verify-contract $CONTRACT --chain-id 11155111 --etherscan-api-key GV7AQG968MWYI3YVGF75WPRVYMR28VR6MP --compiler-version v0.8.20+commit.a1b79de6 --constructor-args $ARGS --num-of-optimizations 1 src/KaiSign.sol:KaiSign &

wait
echo "All attempts submitted!"
