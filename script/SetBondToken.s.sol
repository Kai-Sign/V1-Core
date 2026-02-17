// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KaiSignRegistry.sol";

contract SetBondToken is Script {
    // Latest deployed registry on Sepolia
    address constant REGISTRY = 0xC203e8C22eFCA3C9218a6418f6d4281Cb7744dAa;

    // Reality.eth v3.0 Sepolia (same address works for ERC20 mode in testing)
    address constant REALITY_ETH_ERC20 = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bTokenAddress = vm.envAddress("BTOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        KaiSignRegistry registry = KaiSignRegistry(REGISTRY);
        registry.setBondToken(bTokenAddress, REALITY_ETH_ERC20);

        console.log("Bond token set:");
        console.log("  Registry:", REGISTRY);
        console.log("  bToken:", bTokenAddress);
        console.log("  Reality.eth ERC20:", REALITY_ETH_ERC20);

        vm.stopBroadcast();
    }
}
