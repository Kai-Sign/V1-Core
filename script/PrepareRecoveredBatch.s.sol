// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RecoveryBatchBase.s.sol";

/**
 * @title PrepareRecoveredBatch
 * @notice Builds a recoverable batch from script/seed-frontier.json for the
 *         Option A organic reveal path on Sepolia.
 *
 * Env:
 *   START_IDX  optional, defaults to deployments/sepolia.json seed.currentIdx + 1
 *   BATCH_SIZE optional, defaults to 5
 *
 * Output:
 *   deployments/sepolia-recovery-batch.json
 */
contract PrepareRecoveredBatch is RecoveryBatchBase {
    function run() external {
        string memory deployJson = vm.readFile("deployments/sepolia.json");
        string memory seedJson = vm.readFile("script/seed-frontier.json");

        address registry = vm.parseJsonAddress(deployJson, ".contracts.kaiSignRegistry");
        address reality = vm.parseJsonAddress(deployJson, ".contracts.realityETH_ERC20_instance");
        address btoken = vm.parseJsonAddress(deployJson, ".contracts.permissionedBToken");

        uint256 seededIdx = vm.parseJsonUint(deployJson, ".seed.currentIdx");
        uint256 totalLeaves = vm.parseJsonUint(seedJson, ".currentIdx");
        uint256 startIdx = vm.envOr("START_IDX", seededIdx + 1);
        uint256 batchSize = vm.envOr("BATCH_SIZE", uint256(5));

        require(startIdx > seededIdx, "startIdx must exceed seeded currentIdx");
        require(startIdx <= totalLeaves, "startIdx beyond seed frontier");
        require(batchSize > 0, "batch size is zero");

        uint256 endIdx = startIdx + batchSize - 1;
        if (endIdx > totalLeaves) endIdx = totalLeaves;
        uint256 count = endIdx - startIdx + 1;
        uint256[] memory seenChainIds = new uint256[](count);
        bytes32[] memory seenExtcodehashes = new bytes32[](count);
        uint256[] memory seenIdxs = new uint256[](count);
        uint256 seenCount = 0;

        bytes memory out = abi.encodePacked(
            "{\n",
            "  \"registry\": \"", vm.toString(registry), "\",\n",
            "  \"realityETH\": \"", vm.toString(reality), "\",\n",
            "  \"btoken\": \"", vm.toString(btoken), "\",\n",
            "  \"startIdx\": ", vm.toString(startIdx), ",\n",
            "  \"endIdx\": ", vm.toString(endIdx), ",\n",
            "  \"count\": ", vm.toString(count), ",\n",
            "  \"entries\": [\n"
        );

        for (uint256 idx = startIdx; idx <= endIdx; ++idx) {
            uint256 leafPos = idx - 1;
            string memory prefix = string.concat(".leaves[", vm.toString(leafPos), "]");
            string memory path = vm.parseJsonString(seedJson, string.concat(prefix, ".path"));
            uint256 chainId = vm.parseJsonUint(seedJson, string.concat(prefix, ".chainId"));
            bytes32 extcodehash = vm.parseJsonBytes32(seedJson, string.concat(prefix, ".extcodehash"));
            bytes32 metadataHash = vm.parseJsonBytes32(seedJson, string.concat(prefix, ".metadataHash"));
            uint256 nonce = uint256(keccak256(abi.encodePacked("kaisign-recovery", path, idx)));

            for (uint256 i = 0; i < seenCount; ++i) {
                if (seenChainIds[i] == chainId && seenExtcodehashes[i] == extcodehash) {
                    revert DuplicateRecoveryTarget(chainId, extcodehash, seenIdxs[i], idx);
                }
            }
            seenChainIds[seenCount] = chainId;
            seenExtcodehashes[seenCount] = extcodehash;
            seenIdxs[seenCount] = idx;
            seenCount++;

            out = abi.encodePacked(
                out,
                "    {",
                "\"path\": \"", path, "\", ",
                "\"idx\": ", vm.toString(idx), ", ",
                "\"chainId\": ", vm.toString(chainId), ", ",
                "\"extcodehash\": \"", vm.toString(extcodehash), "\", ",
                "\"metadataHash\": \"", vm.toString(metadataHash), "\", ",
                "\"nonce\": \"", vm.toString(nonce), "\", ",
                "\"blobHash\": \"", vm.toString(metadataHash), "\"",
                "}",
                idx < endIdx ? ",\n" : "\n"
            );
        }

        out = abi.encodePacked(out, "  ]\n", "}\n");

        vm.writeFile(_defaultBatchPath(), string(out));

        console.log("=== PREPARED RECOVERY BATCH ===");
        console.log("Registry:", registry);
        console.log("startIdx:", startIdx);
        console.log("endIdx:", endIdx);
        console.log("count:", count);
        console.log("Wrote", _defaultBatchPath());
    }
}
