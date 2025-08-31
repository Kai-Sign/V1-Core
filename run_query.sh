#!/bin/bash

echo "Running KaiSign Blob Query Script"
echo "=================================="
echo ""
echo "This will query all blob specs for the target contract."
echo ""

forge script script/InteractWithBlob.s.sol:QueryBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 -vvv