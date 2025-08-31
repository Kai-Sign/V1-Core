#!/bin/bash

echo "Running KaiSign Blob Commit Script"
echo "==================================="
echo ""
echo "This will commit your blob hash to the KaiSign contract."
echo "You'll need to wait at least 5 minutes before revealing."
echo ""

forge script script/InteractWithBlob.s.sol:InteractWithBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 --keystore $HOME/.foundry/keystores/kaisignblob --broadcast -vvv