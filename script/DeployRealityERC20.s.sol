// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "../src/external/RealityETH_ERC20_v3_2.sol";
import "../src/external/RealityETH_ERC20_Factory.sol";

contract DeployRealityERC20 is Script {
    // Our deployed PermissionedBToken on Sepolia
    address constant PERMISSIONED_BTOKEN = 0xc14526C362dC6C6Ff707d9cB66c7aBAc02da5a28;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy RealityETH_ERC20 as library implementation
        RealityETH_ERC20_v3_2 library_ = new RealityETH_ERC20_v3_2();
        console.log("RealityETH_ERC20 library deployed:", address(library_));

        // 2. Deploy Factory with library address
        RealityETH_ERC20_Factory factory = new RealityETH_ERC20_Factory(address(library_));
        console.log("RealityETH_ERC20_Factory deployed:", address(factory));

        // 3. Create instance for our PermissionedBToken
        factory.createInstance(PERMISSIONED_BTOKEN);
        address realityInstance = factory.deployments(PERMISSIONED_BTOKEN);
        console.log("RealityETH_ERC20 instance for pBTOKEN:", realityInstance);

        vm.stopBroadcast();
    }
}
