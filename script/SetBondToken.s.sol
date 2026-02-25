// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KaiSignRegistry.sol";
import "../src/PermissionedBToken.sol";

/**
 * @title SetBondToken
 * @notice Links KaiSignRegistry with Token and Reality.eth ERC20
 * @dev Step 3 of full deployment flow
 *
 *      Usage:
 *      PRIVATE_KEY=0x... KAISIGN=0x... BTOKEN=0x... REALITY_ERC20=0x... forge script script/SetBondToken.s.sol --broadcast --rpc-url $SEPOLIA_RPC_URL
 */
contract SetBondToken is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address kaisignAddr = vm.envAddress("KAISIGN");
        address tokenAddr = vm.envAddress("BTOKEN");
        address realityAddr = vm.envAddress("REALITY_ERC20");

        console.log("=== Set Bond Token (Step 3/4) ===");
        console.log("KaiSign:", kaisignAddr);
        console.log("Token:", tokenAddr);
        console.log("Reality.eth ERC20:", realityAddr);

        vm.startBroadcast(privateKey);

        // 1. Set bond token on KaiSign
        KaiSignRegistry kaisign = KaiSignRegistry(kaisignAddr);
        kaisign.setBondToken(tokenAddr, realityAddr);
        console.log("1. Set bond token on KaiSign");

        // 2. Whitelist Reality.eth on token
        PermissionedBToken token = PermissionedBToken(tokenAddr);
        token.whitelist(realityAddr);
        console.log("2. Whitelisted Reality.eth on token");

        // Fix RM-6: KaiSignRegistry calls safeTransferFrom — must be whitelisted
        token.whitelist(kaisignAddr);
        console.log("3. Whitelisted KaiSignRegistry on token");

        vm.stopBroadcast();

        console.log("");
        console.log("=== STEP 3 COMPLETE ===");
        console.log("KaiSign is now linked to Token and Reality.eth ERC20 (both whitelisted)");
        console.log("");
        console.log("NEXT: Run Migrate.s.sol to import merkle state");
    }
}
