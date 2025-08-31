#!/bin/bash

echo "Running KaiSign Blob Reveal Script"
echo "==================================="
echo ""
echo "This will reveal your blob commitment and pay the 0.01 ETH bond."
echo ""

if [ -z "$1" ]; then
    echo "Usage: ./run_reveal.sh <COMMITMENT_ID>"
    echo "Example: ./run_reveal.sh 0x6fc49946e9c9aa3f05074c7cfb292358b9e689962aede354d7dde22b827faca2"
    exit 1
fi

export COMMITMENT_ID=$1

echo "Using Commitment ID: $COMMITMENT_ID"
echo ""

forge script script/RevealBlob.s.sol:RevealBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 --keystore $HOME/.foundry/keystores/kaisignblob --broadcast --value 0.01ether -vvv