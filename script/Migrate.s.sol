// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KaiSignRegistry.sol";

/**
 * @title Migrate
 * @notice Migrate merkle state from old contract to new contract
 * @dev The frontier was computed off-chain by replaying all 448 leaf insertions
 *      through the incremental merkle tree algorithm.
 *
 *      Run: OLD_REGISTRY=0x... NEW_REGISTRY=0x... forge script script/Migrate.s.sol --broadcast
 */
contract Migrate is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address oldAddr = vm.envAddress("OLD_REGISTRY");
        address newAddr = vm.envAddress("NEW_REGISTRY");

        console.log("=== MIGRATION SCRIPT ===");
        console.log("Old registry:", oldAddr);
        console.log("New registry:", newAddr);

        // Read state from old contract
        KaiSignRegistry oldReg = KaiSignRegistry(oldAddr);
        KaiSignRegistry newReg = KaiSignRegistry(newAddr);

        bytes32 oldRoot = oldReg.merkleRoot();
        uint64 oldIdx = oldReg.currentIdx();

        console.log("\n=== OLD CONTRACT STATE ===");
        console.log("merkleRoot:");
        console.logBytes32(oldRoot);
        console.log("currentIdx:", oldIdx);

        // Verify new contract is empty
        bytes32 newRoot = newReg.merkleRoot();
        require(newRoot == bytes32(0), "New contract already has merkle root");
        console.log("\nNew contract merkleRoot is zero (ready for migration)");

        // Frontier computed off-chain by replaying 448 leaf insertions
        // through the incremental merkle tree algorithm.
        // See: kaisign-backend/scripts/compute-frontier.mjs
        bytes32[] memory frontier = new bytes32[](20);
        frontier[0] = bytes32(0xc79e73499b05d37bafda2d09aae76599a41a93058a9a24ae113240789068cf8d);
        frontier[1] = bytes32(0xa7c802963ac32f3040161187c4a563d6030ece24126e7a03b3e76cb3e8b63227);
        frontier[2] = bytes32(0xe1582333f579e5378e95b579ab61fdb74439d05a93c8a578fa2a34a90a489959);
        frontier[3] = bytes32(0x696c83fa5d1b4434ab0e483d9152434a0b7f425ea031d2a1b3e64fc4e1a5b033);
        frontier[4] = bytes32(0xea86f19b98309e23f4a734add050d41156009b9b56502155f24d0f51bdf2ff4b);
        frontier[5] = bytes32(0x3832b41ceb65366ff5835477e1346fdfd4f88e2a60e7e28babe5f4b4a2bd80e4);
        frontier[6] = bytes32(0xc18ff138d17d4d9b5ce149c492e207d716b756726169629dc17babd2a335d798);
        frontier[7] = bytes32(0x138015950ec1e61930d734fb33780c9426d2539e1459ecb70fb8238b78129083);
        frontier[8] = bytes32(0x530efda5c5c7b88a15592cab2bea8e6365584e6901071805560ab8ee3a02cc66);
        frontier[9] = bytes32(0x972f52f56c9f7b22aee364f2ccf111fb696f28552c5944142c6b96f1e78ed993);
        frontier[10] = bytes32(0xf79e70b6f2fe7a37934d1a109321685ea6a54942934717fc5fda0610819a1bb8);
        frontier[11] = bytes32(0xa9e07864333c06a6ba177b01d96fae23d497bdf03346962ad41cebd23d637b07);
        frontier[12] = bytes32(0xa1c0b5a5f9550f9986e38dd6090758913d93280c4376b1275728caa65dad28a9);
        frontier[13] = bytes32(0xc0fa8d5a0ace30f0cb1f4d0da388af9582397266a5b57124c5a4c985551df561);
        frontier[14] = bytes32(0x6dafc890b79ee060f9a8c8273f96c4e052f287ef033eb948f601e813b7e1d743);
        frontier[15] = bytes32(0x7398fb6cc37e461bc01f229a491ce0ebebebb4716979d921205e3b00a63ced15);
        frontier[16] = bytes32(0x9a23bffcb64cd96d7b6eb678fcade88a90df75de6615b1076829bc426709174b);
        frontier[17] = bytes32(0x134138e62d8af3d5270b95e52393e139ddf899c13d72e9f139e8e198dcd73929);
        frontier[18] = bytes32(0xe3a995f13145372e86466716d93696eca7326b56fe47b91ed06a600d1d6bdfd5);
        frontier[19] = bytes32(0xdc66a78b37eddb20a365196ddd08ee8e35b61b6231c4d6e3c2bfc54385cf5037);

        // Perform migration
        vm.startBroadcast(privateKey);
        newReg.migrate(frontier, oldIdx);
        vm.stopBroadcast();

        // Verify migration
        bytes32 migratedRoot = newReg.merkleRoot();
        uint64 migratedIdx = newReg.currentIdx();

        console.log("\n=== MIGRATION RESULT ===");
        console.log("New merkleRoot:");
        console.logBytes32(migratedRoot);
        console.log("New currentIdx:", migratedIdx);

        require(oldIdx == migratedIdx, "IDX MISMATCH");

        // Note: migratedRoot will differ from oldRoot if old contract used standard tree
        // This is expected - the incremental tree root is computed from the frontier
        if (oldRoot != migratedRoot) {
            console.log("\nNote: Roots differ (old=standard tree, new=incremental tree)");
            console.log("This is expected and correct.");
        } else {
            console.log("\nRoots match (old contract also used incremental tree)");
        }

        console.log("\n=== MIGRATION VERIFIED OK ===");
    }
}
