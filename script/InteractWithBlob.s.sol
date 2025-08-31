// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KaiSign} from "../src/KaiSign.sol";

contract InteractWithBlob is Script {
    // Your blob hash from the transaction
    bytes32 constant BLOB_HASH = 0x0196d7c56bbc18b22ea2ac4e65b968e39c918bfed9f7ac0c0fccabda8d0e2239;
    
    // Metadata hash (keccak256 of the ERC-7730 JSON)
    bytes32 constant METADATA_HASH = 0xb269bee2273ffe631057a429f0aed9a094c89c5038ed014aa8abee2bcd991f17;
    
    // KaiSign contract address (update this after deployment)
    address constant KAISIGN_ADDRESS =  0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719;
    
    // Target contract to add spec for
    address constant TARGET_CONTRACT = 0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719;
    
    // Chain ID for the target contract
    uint256 constant CHAIN_ID = 11155111; // Sepolia
    
    // Random nonce for commit-reveal
    uint256 constant NONCE = 12345;
    
    function run() public {
        // Get the KaiSign contract
        KaiSign kaisign = KaiSign(KAISIGN_ADDRESS);
        
        address deployer = msg.sender; // When using keystore, msg.sender is the deployer
        
        console.log("=== KAISIGN BLOB INTERACTION ===");
        console.log("Deployer:", deployer);
        console.log("KaiSign:", KAISIGN_ADDRESS);
        console.log("Blob Hash:");
        console.logBytes32(BLOB_HASH);
        console.log("Target Contract:", TARGET_CONTRACT);
        console.log("Chain ID:", CHAIN_ID);
        
        vm.startBroadcast();
        
        // Step 1: Commit using metadataHash (not blobHash) to prevent front-running
        bytes32 commitment = keccak256(abi.encodePacked(METADATA_HASH, NONCE));
        console.log("\nStep 1: Committing with metadata hash...");
        console.log("Metadata Hash:");
        console.logBytes32(METADATA_HASH);
        console.log("Commitment:");
        console.logBytes32(commitment);
        
        kaisign.commitSpec(commitment, TARGET_CONTRACT, CHAIN_ID);
        
        console.log("\n⚠️  IMPORTANT: The commitment ID shown below is estimated!");
        console.log("The actual commitment ID will be different due to block timestamp.");
        console.log("Get the real commitment ID from the transaction logs on Etherscan.");
        console.log("Look for the LogCommitSpec event's indexed commitmentId parameter.");
        
        // This is just an estimate - actual will differ
        uint64 estimatedTimestamp = uint64(block.timestamp);
        bytes32 estimatedCommitmentId = keccak256(abi.encodePacked(
            commitment,
            deployer,
            TARGET_CONTRACT,
            CHAIN_ID,
            estimatedTimestamp
        ));
        
        console.log("\nEstimated Commitment ID (DO NOT USE):");
        console.logBytes32(estimatedCommitmentId);
        console.log("Estimated timestamp:", estimatedTimestamp);
        
        console.log("\nWait at least 5 minutes before revealing!");
        console.log("Run the reveal script after waiting period.");
        
        vm.stopBroadcast();
        
        // Save commitment details for reveal script
        console.log("\n=== AFTER TRANSACTION IS MINED ===");
        console.log("1. Go to Etherscan and find your transaction");
        console.log("2. Click on 'Logs' tab");
        console.log("3. Find LogCommitSpec event");
        console.log("4. Copy the commitmentId (topic[2])");
        console.log("5. Export it: export COMMITMENT_ID=<the-actual-id>");
        console.log("\nValues to remember:");
        console.log("Nonce:", NONCE);
        console.log("Metadata Hash:", vm.toString(METADATA_HASH));
    }
}

contract RevealBlob is Script {
    // Your blob hash from the transaction
    bytes32 constant BLOB_HASH = 0x0196d7c56bbc18b22ea2ac4e65b968e39c918bfed9f7ac0c0fccabda8d0e2239;
    
    // Metadata hash (keccak256 of the ERC-7730 JSON)
    bytes32 constant METADATA_HASH = 0xb269bee2273ffe631057a429f0aed9a094c89c5038ed014aa8abee2bcd991f17;
    
    // KaiSign contract address
    address constant KAISIGN_ADDRESS = 0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719; 
    
    // Target contract  
    address constant TARGET_CONTRACT = 0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719;
    
    // Nonce used in commit
    uint256 constant NONCE = 12345;
    
    // Minimum bond required
    uint256 constant MIN_BOND = 0.01 ether;
    
    function run() public {
        // For testing, use the commitment ID that would be generated
        // In production, get this from the commit transaction
        address deployer = msg.sender; // When using keystore
        
        // Calculate the commitment ID based on known values
        // Use metadataHash for commitment (same as in commit phase)
        bytes32 commitment = keccak256(abi.encodePacked(METADATA_HASH, NONCE));
        uint64 commitTimestamp = uint64(block.timestamp - 6 minutes); // Assume committed 6 minutes ago
        
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment,
            deployer,
            TARGET_CONTRACT,  
            uint256(11155111), // Sepolia chain ID
            commitTimestamp
        ));
        
        // Or override with environment variable if provided
        bytes32 envCommitmentId = vm.envOr("COMMITMENT_ID", bytes32(0));
        if (envCommitmentId != bytes32(0)) {
            commitmentId = envCommitmentId;
        }
        
        console.log("Using Commitment ID:");
        console.logBytes32(commitmentId);
        
        KaiSign kaisign = KaiSign(KAISIGN_ADDRESS);
        
        console.log("=== REVEALING BLOB SPEC ===");
        console.log("Deployer:", deployer);
        console.log("Commitment ID:");
        console.logBytes32(commitmentId);
        console.log("Blob Hash:");
        console.logBytes32(BLOB_HASH);
        console.log("Metadata Hash:");
        console.logBytes32(METADATA_HASH);
        console.log("Nonce:", NONCE);
        console.log("Bond:", MIN_BOND);
        
        vm.startBroadcast();
        
        // Reveal with bond - now using 4 parameters
        // blobHash for storage, metadataHash for verification
        console.log("\nRevealing spec with bond...");
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(
            commitmentId,
            BLOB_HASH,      // blobHash for spec storage
            METADATA_HASH,  // metadataHash for commitment verification
            NONCE
        );
        
        console.log("\nSpec revealed successfully!");
        console.log("Spec ID:");
        console.logBytes32(specId);
        
        // Check the spec status - specs mapping returns individual fields
        (
            uint64 createdTimestamp,
            uint64 proposedTimestamp,
            KaiSign.Status status,
            uint80 totalBonds,
            uint32 reserved,
            address creator,
            address targetContract,
            bytes32 blobHash,
            bytes32 questionId,
            bytes32 incentiveId,
            uint256 chainId
        ) = kaisign.specs(specId);
        
        console.log("\nSpec Details:");
        console.log("Creator:", creator);
        console.log("Target:", targetContract);
        console.log("Chain ID:", chainId);
        console.log("Status:", uint256(status));
        console.log("Total Bonds:", totalBonds);
        console.log("Created Timestamp:", createdTimestamp);
        console.log("Blob Hash:");
        console.logBytes32(blobHash);
        
        vm.stopBroadcast();
        
        console.log("\nBlob spec successfully submitted to KaiSign!");
        console.log("The ERC-7730 metadata is now linked to the contract.");
    }
}

contract QueryBlob is Script {
    // KaiSign contract address
    address constant KAISIGN_ADDRESS = 0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719; 
    
    // Target contract to query
    address constant TARGET_CONTRACT = 0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719;
    
    // Chain ID
    uint256 constant CHAIN_ID = 11155111; // Sepolia
    
    function run() public view {
        KaiSign kaisign = KaiSign(KAISIGN_ADDRESS);
        
        console.log("=== QUERYING BLOB SPECS ===");
        console.log("KaiSign:", KAISIGN_ADDRESS);
        console.log("Target Contract:", TARGET_CONTRACT);
        console.log("Chain ID:", CHAIN_ID);
        
        // Get specs for the contract
        bytes32[] memory blobHashes = kaisign.getSpecsByContract(TARGET_CONTRACT, CHAIN_ID);
        
        console.log("\nFound", blobHashes.length, "blob specs:");
        
        for (uint i = 0; i < blobHashes.length; i++) {
            console.log("\nBlob", i + 1, ":");
            console.logBytes32(blobHashes[i]);
            
            // The blob hash 0x0196d7c56bbc18b22ea2ac4e65b968e39c918bfed9f7ac0c0fccabda8d0e2239
            // contains the ERC-7730 metadata that can be retrieved from the blob pool
            
            if (blobHashes[i] == 0x0196d7c56bbc18b22ea2ac4e65b968e39c918bfed9f7ac0c0fccabda8d0e2239) {
                console.log("  -> This is our ERC-7730 metadata blob!");
            }
        }
        
        if (blobHashes.length == 0) {
            console.log("No specs found for this contract yet.");
            console.log("Run the commit and reveal scripts first.");
        }
    }
}