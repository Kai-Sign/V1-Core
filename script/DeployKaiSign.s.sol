// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KAIToken} from "../src/KAIToken.sol";
import {KAIArbitration} from "../src/KAIArbitration.sol";
import {KAISlashing} from "../src/KAISlashing.sol";
import {KaiSign} from "../src/KaiSign.sol";

/**
 * @title DeployKaiSign
 * @notice Deployment script for the KaiSign system with KAI token arbitration
 * @dev Deploys contracts in order: KAIToken -> KAIArbitration -> KAISlashing -> KaiSign
 *      Then configures permissions between contracts
 *
 * Usage:
 *   forge script script/DeployKaiSign.s.sol:DeployKaiSign --rpc-url $RPC_URL --broadcast
 */
contract DeployKaiSign is Script {
    // Deployed contracts
    KAIToken public kaiToken;
    KAIArbitration public kaiArbitration;
    KAISlashing public kaiSlashing;
    KaiSign public kaisign;

    // Configuration parameters
    struct DeployConfig {
        // KAI Token
        string tokenName;
        string tokenSymbol;
        uint256 initialSupply;
        // KAI Arbitration
        uint32 defaultVotingPeriod;
        uint32 commitRevealWindow;
        uint16 defaultRewardRateBps;
        uint256 minStakePerVote;
        uint256 minTotalStakeThreshold;
        // KaiSign
        address treasury;
        uint256 minBond;
    }

    function run() public {
        // Load configuration from environment or use defaults
        DeployConfig memory config = getConfig();

        vm.startBroadcast();

        // Get deployer address
        address deployer = msg.sender;
        console.log("Deployer:", deployer);

        // Prepare initial admins array
        address[] memory initialAdmins = new address[](1);
        initialAdmins[0] = deployer;

        // =================================================================
        // STEP 1: Deploy KAI Token
        // =================================================================
        console.log("\n--- Deploying KAI Token ---");

        kaiToken = new KAIToken(
            config.tokenName,
            config.tokenSymbol,
            initialAdmins,
            config.initialSupply
        );

        console.log("KAIToken deployed to:", address(kaiToken));
        console.log("  Name:", kaiToken.name());
        console.log("  Symbol:", kaiToken.symbol());
        console.log("  Initial Supply:", config.initialSupply / 1e18, "KAI");

        // =================================================================
        // STEP 2: Deploy KAI Arbitration
        // =================================================================
        console.log("\n--- Deploying KAI Arbitration ---");

        kaiArbitration = new KAIArbitration(
            address(kaiToken),
            config.defaultVotingPeriod,
            config.commitRevealWindow,
            config.defaultRewardRateBps,
            config.minStakePerVote,
            config.minTotalStakeThreshold,
            initialAdmins
        );

        console.log("KAIArbitration deployed to:", address(kaiArbitration));
        console.log("  Voting Period:", config.defaultVotingPeriod / 1 hours, "hours");
        console.log("  Commit Window:", config.commitRevealWindow / 1 hours, "hours");
        console.log("  Reward Rate (bps):", config.defaultRewardRateBps);
        console.log("  Min Stake Per Vote:", config.minStakePerVote / 1e18, "KAI");
        console.log("  Min Total Stake:", config.minTotalStakeThreshold / 1e18, "KAI");

        // =================================================================
        // STEP 3: Deploy KAI Slashing (Fork Challenge System)
        // =================================================================
        console.log("\n--- Deploying KAI Slashing ---");

        kaiSlashing = new KAISlashing(
            address(kaiToken),
            address(kaiArbitration),
            initialAdmins
        );

        console.log("KAISlashing deployed to:", address(kaiSlashing));
        console.log("  Challenge Window: 7 days");
        console.log("  Challenge Bond: 500 KAI");
        console.log("  Slash Percent: 50%");

        // =================================================================
        // STEP 4: Configure Token Permissions
        // =================================================================
        console.log("\n--- Configuring Token Permissions ---");

        kaiToken.grantMinterRole(address(kaiArbitration));
        console.log("Granted MINTER_ROLE to KAIArbitration (for inflation rewards)");

        kaiToken.grantBurnerRole(address(kaiSlashing));
        console.log("Granted BURNER_ROLE to KAISlashing (for slashing)");

        // =================================================================
        // STEP 5: Deploy KaiSign
        // =================================================================
        console.log("\n--- Deploying KaiSign ---");

        kaisign = new KaiSign(
            address(kaiArbitration),
            config.treasury,
            config.minBond,
            initialAdmins
        );

        console.log("KaiSign deployed to:", address(kaisign));
        console.log("  Treasury:", config.treasury);
        console.log("  Min Bond:", config.minBond / 1e15, "finney");

        // =================================================================
        // STEP 6: Configure Arbitration Permissions
        // =================================================================
        console.log("\n--- Configuring Arbitration Permissions ---");

        kaiArbitration.setKaiSignContract(address(kaisign));
        console.log("Set KaiSign contract in KAIArbitration");

        kaiArbitration.setSlashingContract(address(kaiSlashing));
        console.log("Set KAISlashing contract in KAIArbitration");

        vm.stopBroadcast();

        // =================================================================
        // Deployment Summary
        // =================================================================
        console.log("\n========================================");
        console.log("       DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("KAIToken:       ", address(kaiToken));
        console.log("KAIArbitration: ", address(kaiArbitration));
        console.log("KAISlashing:    ", address(kaiSlashing));
        console.log("KaiSign:        ", address(kaisign));
        console.log("========================================");
        console.log("\nNext Steps:");
        console.log("1. Distribute KAI tokens to initial stakers");
        console.log("2. Verify contracts on block explorer");
        console.log("3. Update frontend with new contract addresses");
    }

    /**
     * @notice Get deployment configuration
     * @dev Override values via environment variables or modify defaults here
     */
    function getConfig() internal view returns (DeployConfig memory config) {
        // Try to get treasury from environment, fallback to deployer
        address treasury = vm.envOr("TREASURY_ADDRESS", msg.sender);

        config = DeployConfig({
            // KAI Token Configuration
            tokenName: "Kai Token",
            tokenSymbol: "KAI",
            initialSupply: 1_000_000_000 * 1e18, // 1 billion KAI
            // KAI Arbitration Configuration
            defaultVotingPeriod: 48 hours,
            commitRevealWindow: 12 hours,
            defaultRewardRateBps: 55,         // ~0.055% per cycle → ~10% APR
            minStakePerVote: 100 * 1e18,      // 100 KAI
            minTotalStakeThreshold: 1000 * 1e18, // 1000 KAI
            // KaiSign Configuration
            treasury: treasury,
            minBond: 0.01 ether               // 0.01 ETH
        });

        return config;
    }
}

/**
 * @title DeployKaiSignTestnet
 * @notice Testnet deployment with lower thresholds for testing
 */
contract DeployKaiSignTestnet is Script {
    KAIToken public kaiToken;
    KAIArbitration public kaiArbitration;
    KAISlashing public kaiSlashing;
    KaiSign public kaisign;

    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;
        address[] memory initialAdmins = new address[](1);
        initialAdmins[0] = deployer;

        // Testnet configuration with lower thresholds
        console.log("\n=== TESTNET DEPLOYMENT ===\n");

        // Deploy KAI Token with smaller supply for testing
        kaiToken = new KAIToken(
            "Kai Token (Testnet)",
            "tKAI",
            initialAdmins,
            100_000_000 * 1e18 // 100 million for testnet
        );
        console.log("KAIToken:", address(kaiToken));

        // Deploy KAI Arbitration with faster voting for testing
        kaiArbitration = new KAIArbitration(
            address(kaiToken),
            24 hours,              // Faster voting for testnet
            6 hours,               // Shorter commit window
            55,                    // ~0.055% reward rate per cycle (~10% APR)
            10 * 1e18,             // 10 KAI min stake (lower for testing)
            100 * 1e18,            // 100 KAI min total (lower for testing)
            initialAdmins
        );
        console.log("KAIArbitration:", address(kaiArbitration));

        // Deploy KAI Slashing
        kaiSlashing = new KAISlashing(
            address(kaiToken),
            address(kaiArbitration),
            initialAdmins
        );
        console.log("KAISlashing:", address(kaiSlashing));

        // Grant minter role (for inflation rewards)
        kaiToken.grantMinterRole(address(kaiArbitration));

        // Grant burner role (for slashing)
        kaiToken.grantBurnerRole(address(kaiSlashing));

        // Deploy KaiSign
        kaisign = new KaiSign(
            address(kaiArbitration),
            deployer,             // Treasury = deployer for testnet
            0.001 ether,          // Lower bond for testnet
            initialAdmins
        );
        console.log("KaiSign:", address(kaisign));

        // Set KaiSign in arbitration
        kaiArbitration.setKaiSignContract(address(kaisign));

        // Set KAISlashing in arbitration
        kaiArbitration.setSlashingContract(address(kaiSlashing));

        vm.stopBroadcast();

        console.log("\n=== TESTNET DEPLOYMENT COMPLETE ===");
    }
}
