#!/bin/bash
# =============================================================================
# KaiSign Local Fork Server
# =============================================================================
# One-click script to start a local Anvil fork with test attestations
#
# Usage:
#   ./script/run-local-fork.sh                     # Default: CoW ETH Flow
#   ./script/run-local-fork.sh path/to/metadata.json  # Custom metadata
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ANVIL_PORT=8545
RPC_URL="http://localhost:$ANVIL_PORT"
SEPOLIA_RPC="${SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
METADATA_FILE="${1:-$SCRIPT_DIR/metadata/cow-ethflow.json}"

# Addresses
REGISTRY="0xC203e8C22eFCA3C9218a6418f6d4281Cb7744dAa"
REALITY_ETH="0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA"

# Anvil's default test account
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
SENDER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Mock Reality.eth bytecode
MOCK_BYTECODE="0x608060408181526004361015610013575f80fd5b5f91823560e01c908163484b93c4146100c8575080637f8d429e146100ac57806383bf46091461006a5763d09cc57e1461004b575f80fd5b34610066576020366003190112610066576020905160018152f35b5080fd5b5034610066576020366003190112610066576004359167ffffffffffffffff83116100a957506100a06020923690600401610171565b50505160018152f35b80fd5b5034610066576020366003190112610066576020905160018152f35b90508260e03660031901126100a95767ffffffffffffffff9160243583811161016d576100f9903690600401610171565b50506044356001600160a01b038116036100665763ffffffff6064358181160361016d57608435908116036100665760208101914283523360601b8583015260348252606082019382851090851117610159575082602094525190208152f35b634e487b7160e01b81526041600452602490fd5b8280fd5b9181601f8401121561019f5782359167ffffffffffffffff831161019f576020838186019501011161019f57565b5f80fdfea2646970667358221220653abfdafd89b3446946bc46f68148776f8a427040fdbbdce8fe2d408148e8f764736f6c63430008140033"

# Leaf typehash (must match KaiSignRegistry)
LEAF_TYPEHASH="0x3069f2a9b882b9a74e8a6aa90a9297f984921c08f5e63b359fe8583b43d74b80"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            KaiSign Local Fork Server                         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
for cmd in anvil forge cast jq; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd not found. Install Foundry: curl -L https://foundry.paradigm.xyz | bash${NC}"
        exit 1
    fi
done

if [ ! -f "$METADATA_FILE" ]; then
    echo -e "${RED}Error: Metadata file not found: $METADATA_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Dependencies OK${NC}"
echo -e "${GREEN}✓ Metadata file: $METADATA_FILE${NC}"

# Kill any existing Anvil process
echo ""
if lsof -i :$ANVIL_PORT &> /dev/null; then
    echo -e "${YELLOW}Killing existing process on port $ANVIL_PORT...${NC}"
    kill $(lsof -t -i :$ANVIL_PORT) 2>/dev/null || true
    sleep 1
fi

# Start Anvil fork
echo -e "${YELLOW}Starting Anvil fork of Sepolia...${NC}"
ANVIL_LOG=$(mktemp)

anvil \
    --fork-url "$SEPOLIA_RPC" \
    --chain-id 11155111 \
    --port $ANVIL_PORT \
    --accounts 1 \
    --balance 10000 \
    > "$ANVIL_LOG" 2>&1 &

ANVIL_PID=$!

# Wait for Anvil
for i in {1..30}; do
    if curl -s $RPC_URL -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' &> /dev/null; then
        echo -e "${GREEN}✓ Anvil started (PID: $ANVIL_PID)${NC}"
        break
    fi
    [ $i -eq 30 ] && { echo -e "${RED}Error: Anvil failed to start${NC}"; cat "$ANVIL_LOG"; exit 1; }
    sleep 0.5
done

# Replace Reality.eth with mock
echo ""
echo -e "${YELLOW}Replacing Reality.eth with mock...${NC}"
curl -s $RPC_URL -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setCode\",\"params\":[\"$REALITY_ETH\",\"$MOCK_BYTECODE\"],\"id\":1}" > /dev/null
echo -e "${GREEN}✓ Reality.eth mocked${NC}"

# Compute metadata hash
echo ""
echo -e "${YELLOW}Computing metadata hash...${NC}"
METADATA_HASH=$(cast keccak "$(cat "$METADATA_FILE")")
echo -e "${GREEN}✓ Metadata hash: $METADATA_HASH${NC}"

# Default test values (CoW ETH Flow on mainnet)
TARGET_ADDRESS="${TARGET_ADDRESS:-0xbA3cB449bD2B4ADddBc894D8697F5170800EAdeC}"
TARGET_CHAIN_ID="${TARGET_CHAIN_ID:-1}"

# Compute REAL extcodehash from mainnet
echo -e "${YELLOW}Fetching real extcodehash from mainnet...${NC}"
MAINNET_RPC="${MAINNET_RPC_URL:-https://eth.llamarpc.com}"
BYTECODE=$(cast code $TARGET_ADDRESS --rpc-url "$MAINNET_RPC" 2>/dev/null)
if [ -z "$BYTECODE" ] || [ "$BYTECODE" = "0x" ]; then
    echo -e "${RED}Error: Could not fetch bytecode for $TARGET_ADDRESS from mainnet${NC}"
    kill $ANVIL_PID 2>/dev/null
    exit 1
fi
EXTCODEHASH=$(cast keccak "$BYTECODE")
echo -e "${GREEN}✓ Extcodehash: $EXTCODEHASH${NC}"

# Get current state
CURRENT_IDX=$(cast call $REGISTRY "currentIdx()(uint64)" --rpc-url $RPC_URL)
CURRENT_ROOT=$(cast call $REGISTRY "merkleRoot()(bytes32)" --rpc-url $RPC_URL)
echo -e "${GREEN}✓ Current idx: $CURRENT_IDX${NC}"
echo -e "${GREEN}✓ Current root: $CURRENT_ROOT${NC}"

# Step 1: Commit
echo ""
echo -e "${YELLOW}Step 1: Creating commitment...${NC}"
BLOB_HASH=$(cast keccak "test-blob-local-fork")
NONCE=12345
# commitment = keccak256(abi.encodePacked(blobHash, nonce))
# abi.encodePacked(bytes32, uint256) = 64 bytes concatenated
NONCE_HEX=$(printf "0x%064x" $NONCE)
PACKED=$(cast concat-hex $BLOB_HASH $NONCE_HEX)
COMMITMENT=$(cast keccak $PACKED)
echo -e "  Blob hash: $BLOB_HASH"
echo -e "  Nonce hex: $NONCE_HEX"
echo -e "  Commitment: $COMMITMENT"

TX1=$(cast send $REGISTRY "commitSpec(bytes32,uint256,bytes32)" \
    "$COMMITMENT" "$TARGET_CHAIN_ID" "$EXTCODEHASH" \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --json 2>&1)

if echo "$TX1" | jq -e '.status == "0x1"' > /dev/null 2>&1; then
    # Get commitmentId from logs
    COMMITMENT_ID=$(echo "$TX1" | jq -r '.logs[0].topics[2]')
    echo -e "${GREEN}✓ Commitment created: $COMMITMENT_ID${NC}"
else
    echo -e "${RED}Error in commitSpec: $TX1${NC}"
    kill $ANVIL_PID 2>/dev/null
    exit 1
fi

# Step 2: Reveal
echo ""
echo -e "${YELLOW}Step 2: Revealing spec...${NC}"
echo -e "  CommitmentID: $COMMITMENT_ID"
echo -e "  BlobHash: $BLOB_HASH"
echo -e "  Nonce: $NONCE"
echo -e "  MetadataHash: $METADATA_HASH"

TX2=$(cast send $REGISTRY "revealSpec(bytes32,bytes32,uint256,bytes32)" \
    "$COMMITMENT_ID" "$BLOB_HASH" "$NONCE" "$METADATA_HASH" \
    --value 0.001ether \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --json 2>&1)

echo -e "  TX2 result: $(echo "$TX2" | head -c 200)"

if echo "$TX2" | jq -e '.status == "0x1"' > /dev/null 2>&1; then
    # Get ATT_UID from logs (LogRevealSpec event, topic[2] is uid)
    ATT_UID=$(echo "$TX2" | jq -r '.logs[0].topics[2]')
    echo -e "${GREEN}✓ Revealed, ATT_UID: $ATT_UID${NC}"
else
    echo -e "${RED}Error in revealSpec${NC}"
    echo "$TX2" | jq '.' 2>/dev/null || echo "$TX2"
    kill $ANVIL_PID 2>/dev/null
    exit 1
fi

# Step 3: Compute merkle proof and finalize
echo ""
echo -e "${YELLOW}Step 3: Finalizing attestation...${NC}"
NEW_IDX=$((CURRENT_IDX + 1))

# Compute leaf: keccak256(abi.encode(LEAF_TYPEHASH, chainId, extcodehash, metadataHash, idx, false))
LEAF=$(cast keccak "$(cast abi-encode 'f(bytes32,uint256,bytes32,bytes32,uint64,bool)' \
    $LEAF_TYPEHASH $TARGET_CHAIN_ID $EXTCODEHASH $METADATA_HASH $NEW_IDX false)")
echo -e "  Leaf: $LEAF"

# Compute new merkle root
# For idx=1: root = leaf
# For idx=2: root = hash(leaf1, leaf2) where leaf1 = currentRoot
# For idx>=3: simplified append
if [ "$NEW_IDX" -eq 1 ]; then
    NEW_ROOT=$LEAF
    PROOF="[]"
elif [ "$NEW_IDX" -eq 2 ]; then
    NEW_ROOT=$(cast keccak "$(cast concat-hex $CURRENT_ROOT $LEAF)")
    PROOF="[\"$CURRENT_ROOT\"]"
else
    POSITION=$((NEW_IDX - 1))
    if [ $((POSITION % 2)) -eq 0 ]; then
        NEW_ROOT=$(cast keccak "$(cast concat-hex $LEAF $CURRENT_ROOT)")
    else
        NEW_ROOT=$(cast keccak "$(cast concat-hex $CURRENT_ROOT $LEAF)")
    fi
    PROOF="[\"$CURRENT_ROOT\"]"
fi
echo -e "  New root: $NEW_ROOT"
echo -e "  Proof: $PROOF"

# Convert proof array for cast send
if [ "$PROOF" = "[]" ]; then
    PROOF_ARG="[]"
else
    PROOF_ARG="[$CURRENT_ROOT]"
fi

TX3=$(cast send $REGISTRY "finalize(bytes32,bytes32,bytes32[])" \
    "$ATT_UID" "$NEW_ROOT" "$PROOF_ARG" \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --json 2>&1)

if echo "$TX3" | jq -e '.status == "0x1"' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Attestation finalized!${NC}"
else
    echo -e "${RED}Error in finalize: $TX3${NC}"
    # Show more details
    echo "$TX3" | jq '.' 2>/dev/null || echo "$TX3"
    kill $ANVIL_PID 2>/dev/null
    exit 1
fi

# Verify final state
echo ""
FINAL_IDX=$(cast call $REGISTRY "currentIdx()(uint64)" --rpc-url $RPC_URL)
FINAL_ROOT=$(cast call $REGISTRY "merkleRoot()(bytes32)" --rpc-url $RPC_URL)

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                       SUCCESS!                                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ATT_UID: ${BLUE}$ATT_UID${NC}"
echo -e "  Final idx: $FINAL_IDX"
echo -e "  Final root: $FINAL_ROOT"
echo ""
echo -e "${BLUE}Anvil running on localhost:$ANVIL_PORT (PID: $ANVIL_PID)${NC}"
echo ""
echo -e "${YELLOW}To use with KaiSign Extension:${NC}"
echo -e "  localStorage.setItem('kaisign_local_rpc', 'http://localhost:$ANVIL_PORT')"
echo ""
echo -e "${YELLOW}To stop:${NC} kill $ANVIL_PID"
echo ""
echo -e "${BLUE}Press Ctrl+C to stop Anvil and exit${NC}"

cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${NC}"
    kill $ANVIL_PID 2>/dev/null || true
    rm -f "$ANVIL_LOG"
}
trap cleanup EXIT

wait $ANVIL_PID
