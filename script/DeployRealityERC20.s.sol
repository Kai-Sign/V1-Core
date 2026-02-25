// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "../src/external/RealityETH_ERC20_v3_2.sol";
import "../src/external/RealityETH_ERC20_Factory.sol";

/**
 * @title DeployRealityERC20
 * @notice Deploys Reality.eth ERC20 for a given token
 * @dev Step 2 of full deployment flow
 *
 *      Usage:
 *      PRIVATE_KEY=0x... PERMISSIONED_BTOKEN=0x... forge script script/DeployRealityERC20.s.sol --broadcast --rpc-url $SEPOLIA_RPC_URL
 */
contract DeployRealityERC20 is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address token = vm.envAddress("PERMISSIONED_BTOKEN");

        console.log("=== Reality.eth ERC20 Deployment (Step 2/4) ===");
        console.log("Token:", token);

        vm.startBroadcast(privateKey);

        // 1. Deploy RealityETH_ERC20 library
        RealityETH_ERC20_v3_2 library_ = new RealityETH_ERC20_v3_2();
        console.log("1. RealityETH_ERC20 library deployed:", address(library_));

        // 2. Deploy Factory with library address
        RealityETH_ERC20_Factory factory = new RealityETH_ERC20_Factory(address(library_));
        console.log("2. RealityETH_ERC20_Factory deployed:", address(factory));

        // 3. Create instance for our token
        factory.createInstance(token);
        address realityInstance = factory.deployments(token);
        console.log("3. RealityETH_ERC20 instance created:", realityInstance);

        vm.stopBroadcast();

        console.log("");
        console.log("=== STEP 2 COMPLETE ===");
        console.log("REALITY_ERC20:", realityInstance);
        console.log("");
        console.log("NEXT: Run SetBondToken.s.sol with these addresses");
    }
}
