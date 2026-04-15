// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RecoveryBatchBase.s.sol";

/**
 * @title BatchRevealRecovered
 * @notice Reveals the committed recovery batch with minBond-sized bonds.
 *
 * Input:
 *   deployments/sepolia-recovery-commits.json
 *
 * Output:
 *   deployments/sepolia-recovery-reveals.json
 */
contract BatchRevealRecovered is RecoveryBatchBase {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (BatchConfig memory cfg, CommitEntry[] memory entries) = _loadCommitEntries(_defaultCommitPath());

        KaiSignRegistry registry = KaiSignRegistry(cfg.registry);
        uint256 minBond = registry.minBond();
        bytes32[] memory uids = new bytes32[](entries.length);

        console.log("=== REVEAL RECOVERED BATCH ===");
        console.log("Registry:", cfg.registry);
        console.log("Entries:", entries.length);
        console.log("minBond:", minBond);

        vm.startBroadcast(privateKey);
        for (uint256 i = 0; i < entries.length; ++i) {
            uids[i] = registry.revealSpec(
                entries[i].commitmentId,
                entries[i].blobHash,
                entries[i].nonce,
                entries[i].metadataHash,
                minBond
            );
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
                "\"commitmentId\": \"", vm.toString(entries[i].commitmentId), "\", ",
                "\"uid\": \"", vm.toString(uids[i]), "\"",
                "}",
                i + 1 < entries.length ? ",\n" : "\n"
            );
        }

        out = abi.encodePacked(out, "  ]\n", "}\n");
        vm.writeFile(_defaultRevealPath(), string(out));
        console.log("Wrote", _defaultRevealPath());
        console.log("Next: wait >= 1 Sepolia block, then run BatchVoteRecovered.s.sol");
    }
}
