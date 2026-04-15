// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RecoveryBatchBase.s.sol";

/**
 * @title BatchCommitRecovered
 * @notice Commits the prepared recovery batch and writes commitmentIds for the
 *         later reveal step.
 *
 * Input:
 *   deployments/sepolia-recovery-batch.json
 *
 * Output:
 *   deployments/sepolia-recovery-commits.json
 */
contract BatchCommitRecovered is RecoveryBatchBase {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (BatchConfig memory cfg, BatchEntry[] memory entries) = _loadBatchEntries(_defaultBatchPath());

        KaiSignRegistry registry = KaiSignRegistry(cfg.registry);
        PermissionedBToken token = PermissionedBToken(cfg.btoken);

        bytes32[] memory commitmentIds = new bytes32[](entries.length);

        console.log("=== COMMIT RECOVERED BATCH ===");
        console.log("Registry:", cfg.registry);
        console.log("Entries:", entries.length);

        vm.startBroadcast(privateKey);
        token.approve(cfg.reality, type(uint256).max);
        token.approve(cfg.registry, type(uint256).max);

        for (uint256 i = 0; i < entries.length; ++i) {
            bytes32 commitment = keccak256(abi.encode(entries[i].blobHash, entries[i].nonce));
            commitmentIds[i] = registry.commitSpec(commitment, entries[i].chainId, entries[i].extcodehash);
        }
        vm.stopBroadcast();

        bytes memory out = abi.encodePacked(
            "{\n",
            "  \"registry\": \"", vm.toString(cfg.registry), "\",\n",
            "  \"realityETH\": \"", vm.toString(cfg.reality), "\",\n",
            "  \"btoken\": \"", vm.toString(cfg.btoken), "\",\n",
            "  \"startIdx\": ", vm.toString(cfg.startIdx), ",\n",
            "  \"endIdx\": ", vm.toString(cfg.endIdx), ",\n",
            "  \"count\": ", vm.toString(cfg.count), ",\n",
            "  \"entries\": [\n"
        );

        for (uint256 i = 0; i < entries.length; ++i) {
            out = abi.encodePacked(
                out,
                "    {",
                "\"path\": \"", entries[i].path, "\", ",
                "\"idx\": ", vm.toString(entries[i].idx), ", ",
                "\"chainId\": ", vm.toString(entries[i].chainId), ", ",
                "\"extcodehash\": \"", vm.toString(entries[i].extcodehash), "\", ",
                "\"metadataHash\": \"", vm.toString(entries[i].metadataHash), "\", ",
                "\"nonce\": \"", vm.toString(entries[i].nonce), "\", ",
                "\"blobHash\": \"", vm.toString(entries[i].blobHash), "\", ",
                "\"commitmentId\": \"", vm.toString(commitmentIds[i]), "\"",
                "}",
                i + 1 < entries.length ? ",\n" : "\n"
            );
        }

        out = abi.encodePacked(out, "  ]\n", "}\n");
        vm.writeFile(_defaultCommitPath(), string(out));
        console.log("Wrote", _defaultCommitPath());
        console.log("Next: wait >= 1 Sepolia block, then run BatchRevealRecovered.s.sol");
    }
}
