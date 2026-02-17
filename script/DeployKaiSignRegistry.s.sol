// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KaiSignRegistry} from "../src/KaiSignRegistry.sol";

/**
 * @title DeployKaiSignRegistry
 * @notice Deployment script for KaiSignRegistry v2 with Reality.eth integration
 * @dev Deploys to Sepolia testnet with Reality.eth v3.0
 *
 * Usage:
 *   source ../Kai-Sign-Builder/.env
 *   forge script script/DeployKaiSignRegistry.s.sol:DeployKaiSignRegistry \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     -vvv
 */
contract DeployKaiSignRegistry is Script {
    // Reality.eth v3.0 Sepolia
    address constant REALITY_ETH_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;
    address constant NO_ARBITRATOR = address(0);
    uint256 constant MIN_BOND = 0.001 ether;

    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;
        console.log("Deployer:", deployer);

        // Prepare initial attesters array (empty for now, can add later)
        address[] memory initialAttesters = new address[](0);

        console.log("\n--- Deploying KaiSignRegistry v2 ---");

        KaiSignRegistry registry = new KaiSignRegistry(
            1,                          // universeId
            address(0),                 // parentRegistry (root)
            deployer,                   // initialOwner
            initialAttesters,           // initialAttesters (empty)
            REALITY_ETH_SEPOLIA,        // Reality.eth
            NO_ARBITRATOR,              // arbitrator (none)
            MIN_BOND                    // minBond
        );

        console.log("KaiSignRegistry deployed to:", address(registry));
        console.log("  Universe ID:", registry.universeId());
        console.log("  Parent Registry:", registry.parentRegistry());
        console.log("  Owner:", registry.owner());
        console.log("  Reality.eth:", address(registry.realityETH()));
        console.log("  Min Bond:", registry.minBond(), "wei");
        console.log("  Template ID:", registry.templateId());

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("       DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("KaiSignRegistry:", address(registry));
        console.log("========================================");
        console.log("\nNext Steps:");
        console.log("1. Update autonomous-submitter.js with new address");
        console.log("2. Test submission with: node ../Kai-Sign-Builder/scripts/autonomous-submitter.js");
        console.log("3. Verify contract (when ready): forge verify-contract");
    }
}
