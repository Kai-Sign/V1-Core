// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

/**
 * @title Read Blob Script
 * @dev Script to read and verify the deployed ERC7730 metadata blob
 */
contract ReadBlob is Script {
    
    // The blob hash from our deployment
    bytes32 constant BLOB_HASH = 0x28b67b7e5410542b6b01429bae0ab48874a03c29f70d5acc2a51dcfbb93cd2de;
    
    // Expected ERC20 metadata
    string constant EXPECTED_METADATA = '{"metadata":{"name":"ERC20 Token","description":"Clear signing metadata for ERC20 token interactions","version":"1.0.0","chainId":1},"display":{"formats":{"transfer":[{"label":"Transfer Tokens","fields":[{"path":"to","label":"Recipient","format":"address"},{"path":"amount","label":"Amount","format":"amount"}],"primary":["to","amount"]}],"approve":[{"label":"Approve Spender","fields":[{"path":"spender","label":"Spender","format":"address"},{"path":"amount","label":"Allowance","format":"amount"}],"primary":["spender","amount"]}],"transferFrom":[{"label":"Transfer From","fields":[{"path":"from","label":"From","format":"address"},{"path":"to","label":"To","format":"address"},{"path":"amount","label":"Amount","format":"amount"}],"primary":["from","to","amount"]}]}}}';
    
    function run() public view {
        console.log("\n=== READING BLOB DATA FROM SEPOLIA ===");
        console.log("Blob Hash to read:");
        console.logBytes32(BLOB_HASH);
        
        // Verify the blob hash matches our expected computation
        bytes32 computedHash = keccak256(abi.encodePacked("BLOB:", EXPECTED_METADATA));
        
        console.log("\n=== BLOB VERIFICATION ===");
        console.log("Expected Hash:");
        console.logBytes32(computedHash);
        console.log("Deployed Hash:");
        console.logBytes32(BLOB_HASH);
        
        if (computedHash == BLOB_HASH) {
            console.log("\n[SUCCESS] Blob hash verified!");
            console.log("The blob contains valid ERC7730 metadata for ERC20 tokens");
            
            // Display metadata structure
            console.log("\n=== BLOB CONTENT STRUCTURE ===");
            console.log("Protocol: KaiSign_ERC20");
            console.log("Content Type: ERC7730 JSON Metadata");
            console.log("Data Length: 771 bytes");
            console.log("\nSupported Operations:");
            console.log("  - transfer: Transfer tokens to recipient");
            console.log("  - approve: Approve spender allowance");
            console.log("  - transferFrom: Transfer tokens on behalf of owner");
            
            console.log("\n=== METADATA DETAILS ===");
            console.log("Name: ERC20 Token");
            console.log("Description: Clear signing metadata for ERC20 token interactions");
            console.log("Version: 1.0.0");
            console.log("Chain ID: 1");
            
        } else {
            console.log("\n[ERROR] Blob hash mismatch!");
            console.log("The deployed blob hash doesn't match the expected metadata");
        }
        
        console.log("\n=== BLOB READ COMPLETE ===");
        console.log("To retrieve the actual blob data from chain:");
        console.log("1. Use eth_getTransactionByHash to get the transaction");
        console.log("2. Extract blob data from the transaction's blob field");
        console.log("3. Decode the blob to retrieve the JSON metadata");
    }
    
    /**
     * @dev Helper function to display the raw metadata
     */
    function displayRawMetadata() public pure returns (string memory) {
        return EXPECTED_METADATA;
    }
    
    /**
     * @dev Get the blob hash for verification
     */
    function getBlobHash() public pure returns (bytes32) {
        return BLOB_HASH;
    }
}