// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PermissionedBToken.sol";
import "../src/KaiSignRegistry.sol";

contract DeployRegistry is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        console.log("Deployer:", deployer);

        vm.startBroadcast(privateKey);

        // 1. Deploy PermissionedBToken
        PermissionedBToken token = new PermissionedBToken(deployer);
        console.log("Token deployed at:", address(token));

        // 2. Deploy KaiSign (ERC20 only mode)
        KaiSignRegistry kaisign = new KaiSignRegistry(
            20,          // treeDepth
            1,           // universeId
            address(0),  // parentRegistry
            deployer,    // initialOwner
            address(0),  // arbitrator
            0.1 ether    // minBond (in token units)
        );
        console.log("KaiSign deployed at:", address(kaisign));

        // 3. Mint tokens to deployer
        token.mint(deployer, 10000 ether);
        console.log("Minted 10000 tokens to deployer");

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("TOKEN:", address(token));
        console.log("KAISIGN:", address(kaisign));
        console.log("");
        console.log("Next steps:");
        console.log("1. Deploy RealityETH_ERC20 instance for this token");
        console.log("2. Call kaisign.setBondToken(token, realityERC20)");
        console.log("3. Whitelist kaisign and realityERC20 on token");
    }
}
