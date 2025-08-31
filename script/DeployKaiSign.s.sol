// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KaiSign} from "../src/KaiSign.sol";

contract DeployKaiSign is Script {
    KaiSign public kaisign;
    
    function run() public {
        vm.startBroadcast();
        
        // Constructor parameters for KaiSign
        address realityETH = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA; // Reality.eth contract on Sepolia
        address arbitrator = 0x05B942fAEcfB3924970E3A28e0F230910CEDFF45; // Arbitrator address
        address treasury = 0x7D8730aD11f0D421bd41c6E5584F20c744CBAf29; // Treasury address
        uint256 minBond = 10000000000000000; // 0.01 ETH
        address[] memory initialAdmins = new address[](1);
        initialAdmins[0] = msg.sender;
        
        bytes32 salt = 0x319d4829c8512c09bedf1688c873a330c0c0888875b02da9f06256b59c99ee36;
        
        // Calculate deterministic address
        address predictedAddress = vm.computeCreate2Address(
            salt,
            keccak256(abi.encodePacked(
                type(KaiSign).creationCode,
                abi.encode(
                    realityETH,
                    arbitrator,
                    treasury,
                    minBond,
                    initialAdmins
                )
            ))
        );
        
        console.log("Predicted address:", predictedAddress);
        
        // Deploy KaiSign with CREATE2 for deterministic address
        kaisign = new KaiSign{salt: salt}(
            realityETH,
            arbitrator,
            treasury,
            minBond,
            initialAdmins
        );
        
        console.log("KaiSign deployed to:", address(kaisign));
        console.log("Address matches prediction:", address(kaisign) == predictedAddress);
        console.log("Salt used:", vm.toString(salt));
        
        vm.stopBroadcast();
    }
}