// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MetadataRegistry} from "../src/MetadataRegistry.sol";

contract DeployMetadataRegistry is Script {
    MetadataRegistry public metadataRegistry;
    
    function run() public {
        vm.startBroadcast();
        
        bytes32 salt = 0x319d4829c8512c09bedf1688c873a330c0c0888875b02da9f06256b59c99ee36;
        
        // Calculate deterministic address
        address predictedAddress = vm.computeCreate2Address(
            salt,
            keccak256(abi.encodePacked(
                type(MetadataRegistry).creationCode,
                abi.encode(msg.sender)
            ))
        );
        
        console.log("Predicted address:", predictedAddress);
        
        // Deploy MetadataRegistry with CREATE2 for deterministic address
        metadataRegistry = new MetadataRegistry{salt: salt}();
        
        console.log("MetadataRegistry deployed to:", address(metadataRegistry));
        console.log("Address matches prediction:", address(metadataRegistry) == predictedAddress);
        console.log("Initial owner:", msg.sender);
        console.log("Salt used:", vm.toString(salt));
        
        vm.stopBroadcast();
    }
}