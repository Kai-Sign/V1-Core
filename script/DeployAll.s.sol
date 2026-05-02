// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PermissionedBToken.sol";
import "../src/KaiSignRegistry.sol";

/**
 * @title DeployAll
 * @notice Deploys KaiSign contracts: PermissionedBToken and KaiSignRegistry
 * @dev Reality.eth ERC20 must be deployed separately due to IERC20 import conflicts.
 *
 *      Full deployment flow:
 *      1. Run this script to deploy Token + KaiSign
 *      2. Run DeployRealityERC20.s.sol to deploy Reality.eth
 *      3. Run SetBondToken.s.sol to link them together
 *      4. Run Migrate.s.sol to import merkle state
 */
contract DeployAll is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        console.log("=== KaiSign Deployment (Step 1/4) ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(privateKey);

        // 1. Deploy PermissionedBToken
        PermissionedBToken token = new PermissionedBToken(deployer);
        console.log("1. Token deployed at:", address(token));

        // 2. Deploy KaiSign (bondToken not set yet)
        KaiSignRegistry kaisign = new KaiSignRegistry(
            1,           // universeId
            address(0),  // parentRegistry
            deployer,    // initialOwner
            address(0),  // arbitrator
            0.1 ether    // minBond
        );
        console.log("2. KaiSign deployed at:", address(kaisign));

        // 3. Whitelist KaiSign on token
        token.whitelist(address(kaisign));
        console.log("3. Whitelisted KaiSign on token");

        // 4. Mint tokens to deployer
        token.mint(deployer, 10000 ether);
        console.log("4. Minted 10000 tokens");

        // 5. Approve KaiSign to spend tokens
        token.approve(address(kaisign), type(uint256).max);
        console.log("5. Approved KaiSign to spend tokens");

        vm.stopBroadcast();

        console.log("");
        console.log("=== STEP 1 COMPLETE ===");
        console.log("TOKEN:", address(token));
        console.log("KAISIGN:", address(kaisign));
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Deploy Reality.eth ERC20: forge script script/DeployRealityERC20.s.sol --broadcast");
        console.log("2. Set bond token: forge script script/SetBondToken.s.sol --broadcast");
        console.log("3. Migrate state: forge script script/Migrate.s.sol --broadcast");
    }
}
