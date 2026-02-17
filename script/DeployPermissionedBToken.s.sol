// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PermissionedBToken.sol";

contract DeployPermissionedBToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        PermissionedBToken token = new PermissionedBToken(owner);

        console.log("PermissionedBToken deployed:", address(token));

        vm.stopBroadcast();
    }
}
