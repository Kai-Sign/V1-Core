// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "../src/KaiSignRegistry.sol";

/**
 * @title Migrate
 * @notice Migrate the SMT root from a precomputed off-chain reconstruction.
 * @dev Reads script/seed-frontier.json and imports the .smtRoot field.
 *
 *      Tree state itself is NOT imported — only the root. Off-chain consumers
 *      reconstruct the full tree from event history (or external DA) to
 *      generate proofs for subsequent finalize / finalizeRevoke calls.
 *
 *      Run: NEW_REGISTRY=0x... forge script script/Migrate.s.sol --broadcast
 *
 *      Required artifact shape (script/seed-frontier.json):
 *        {
 *          "smtRoot": "0x..."   // bytes32 SMT root computed off-chain
 *        }
 *
 *      Env override: SMT_ROOT=0x... bypasses the artifact and migrates that
 *      root directly. Useful when the backend hasn't published the artifact yet.
 */
contract Migrate is Script {
    using stdJson for string;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newAddr = vm.envAddress("NEW_REGISTRY");

        bytes32 newRoot = vm.envOr("SMT_ROOT", bytes32(0));
        if (newRoot == bytes32(0)) {
            string memory artifactPath = string.concat(vm.projectRoot(), "/script/seed-frontier.json");
            string memory json = vm.readFile(artifactPath);
            newRoot = json.readBytes32(".smtRoot");
            console.log("Artifact:", artifactPath);
        } else {
            console.log("Using SMT_ROOT env override");
        }

        require(newRoot != bytes32(0), "newRoot is zero");

        console.log("=== MIGRATION SCRIPT ===");
        console.log("New registry:", newAddr);
        console.log("Imported smtRoot:");
        console.logBytes32(newRoot);

        KaiSignRegistry newReg = KaiSignRegistry(newAddr);
        require(newReg.smtRoot() == bytes32(0), "New contract already has smt root");
        console.log("\nNew contract smtRoot is zero (ready for migration)");

        vm.startBroadcast(privateKey);
        newReg.migrate(newRoot);
        vm.stopBroadcast();

        bytes32 migratedRoot = newReg.smtRoot();

        console.log("\n=== MIGRATION RESULT ===");
        console.log("On-chain smtRoot:");
        console.logBytes32(migratedRoot);

        require(migratedRoot == newRoot, "MIGRATED_ROOT_MISMATCH");

        console.log("\n=== MIGRATION VERIFIED OK ===");
    }
}
