#!/bin/bash

# Exhaustive KaiSign Contract Verification Script
# Will try all possible compiler settings combinations

CONTRACT_ADDRESS="0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719"
CHAIN_ID="11155111"
API_KEY="GV7AQG968MWYI3YVGF75WPRVYMR28VR6MP"
CONSTRUCTOR_ARGS="0x000000000000000000000000af33dcb6e8c5c4d9ddf579f53031b514d19449ca00000000000000000000000005b942faecfb3924970e3a28e0f230910cedff450000000000000000000000007d8730ad11f0d421bd41c6e5584f20c744cbaf29000000000000000000000000000000000000000000000000002386f26fc1000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000001804c8ab1f12e6bbf3894d4083f33e07309d1f38"

# Array of compiler versions to try
VERSIONS=(
    "v0.8.20+commit.a1b79de6"
    "v0.8.19+commit.7dd6d404"
    "v0.8.21+commit.d9974bed"
    "v0.8.18+commit.87f61d96"
    "v0.8.17+commit.8df45f5f"
)

# Array of optimization runs to try
OPTIMIZATION_RUNS=(200 1000 10000 1)

# Array of via-ir settings
VIA_IR_SETTINGS=("" "--via-ir")

echo "Starting exhaustive verification attempts..."
echo "Contract: $CONTRACT_ADDRESS"
echo "Network: Sepolia"
echo ""

attempt=1

for version in "${VERSIONS[@]}"; do
    for opt_runs in "${OPTIMIZATION_RUNS[@]}"; do
        for via_ir in "${VIA_IR_SETTINGS[@]}"; do
            echo "=== ATTEMPT $attempt ==="
            echo "Compiler: $version"
            echo "Optimization runs: $opt_runs"
            echo "Via IR: ${via_ir:-false}"
            echo ""
            
            # Build the command
            cmd="forge verify-contract $CONTRACT_ADDRESS \
                --chain-id $CHAIN_ID \
                --etherscan-api-key $API_KEY \
                --compiler-version $version \
                --constructor-args $CONSTRUCTOR_ARGS \
                --num-of-optimizations $opt_runs"
            
            if [ -n "$via_ir" ]; then
                cmd="$cmd $via_ir"
            fi
            
            cmd="$cmd src/KaiSign.sol:KaiSign"
            
            # Execute the command
            echo "Running: $cmd"
            echo ""
            
            if eval $cmd 2>&1 | tee /tmp/verify_output_$attempt.log; then
                # Extract GUID from output if verification was submitted
                guid=$(grep "GUID:" /tmp/verify_output_$attempt.log | cut -d'`' -f2)
                if [ -n "$guid" ]; then
                    echo "Verification submitted with GUID: $guid"
                    echo "Checking status..."
                    sleep 10
                    
                    # Check verification result
                    if forge verify-check $guid --chain-id $CHAIN_ID --etherscan-api-key $API_KEY 2>&1 | grep -q "Pass - Verified"; then
                        echo "🎉 SUCCESS! Contract verified with:"
                        echo "  Compiler: $version"
                        echo "  Optimization: $opt_runs runs"
                        echo "  Via IR: ${via_ir:-false}"
                        echo "  GUID: $guid"
                        exit 0
                    else
                        echo "❌ Verification failed for this combination"
                    fi
                fi
            fi
            
            echo ""
            echo "---"
            echo ""
            ((attempt++))
            sleep 5
        done
    done
done

echo "All combinations attempted. Contract verification failed with all settings."
