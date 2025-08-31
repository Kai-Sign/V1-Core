// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KaiSign} from "../src/KaiSign.sol";

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
        address deployer = msg.sender;
        
        // Get commitment ID from environment (default is from the actual event logs)
        bytes32 commitmentId = vm.envOr("COMMITMENT_ID", bytes32(0x9cfa86847d4d2929a9425a8fd969592c5e164e2fb52d87bab3a428e373d9cd79));
        
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
        
        vm.stopBroadcast();
        
        console.log("\nBlob spec successfully submitted to KaiSign!");
    }
}