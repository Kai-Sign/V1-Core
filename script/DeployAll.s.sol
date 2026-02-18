// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PermissionedBToken.sol";
import "../src/KaiSignRegistry.sol";

interface IRealityETHFactory {
    function createInstance(
        address _token,
        uint32 _template_id,
        address _arbitrator,
        uint256 _timeout,
        uint256 _min_bond
    ) external returns (address);

    function instances(
        address _token,
        uint32 _template_id,
        address _arbitrator,
        uint256 _timeout,
        uint256 _min_bond
    ) external view returns (address);
}

contract DeployAll is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // Factory address (checksummed)
        address factory = 0x7d65F6dEFf70D3054a7a0B4CfE5DE4dDe40eE3D8;

        vm.startBroadcast(privateKey);

        // 1. Deploy PermissionedBToken
        PermissionedBToken token = new PermissionedBToken(deployer);
        console.log("Token deployed at:", address(token));

        // 2. Create Reality.eth ERC20 instance
        IRealityETHFactory factoryContract = IRealityETHFactory(factory);
        factoryContract.createInstance(
            address(token),
            0,
            address(0),
            86400,
            0.1 ether
        );
        address realityERC20 = factoryContract.instances(
            address(token),
            0,
            address(0),
            86400,
            0.1 ether
        );
        console.log("Reality.eth ERC20 at:", realityERC20);

        // 3. Deploy KaiSign (ERC20 only mode)
        KaiSignRegistry kaisign = new KaiSignRegistry(
            1,           // universeId
            address(0),  // parentRegistry
            deployer,    // initialOwner
            address(0),  // arbitrator
            0.1 ether    // minBond
        );
        console.log("KaiSign deployed at:", address(kaisign));

        // 4. Set bond token and ERC20 reality
        kaisign.setBondToken(address(token), realityERC20);
        console.log("Set bond token");

        // 5. Whitelist KaiSign and Reality.eth on token
        token.whitelist(address(kaisign));
        token.whitelist(realityERC20);
        console.log("Whitelisted receivers");

        // 6. Mint tokens
        token.mint(deployer, 1000 ether);
        console.log("Minted 1000 tokens");

        // 7. Approve KaiSign
        token.approve(address(kaisign), type(uint256).max);
        console.log("Approved KaiSign");

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("TOKEN:", address(token));
        console.log("REALITY_ERC20:", realityERC20);
        console.log("KAISIGN:", address(kaisign));
    }
}
