// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RecoveryBatchBase.s.sol";

/**
 * @title BatchVoteRecovered
 * @notice Submits YES answers on Reality.eth for a revealed recovery batch.
 *
 * Input:
 *   deployments/sepolia-recovery-reveals.json
 *
 * Output:
 *   deployments/sepolia-recovery-pending.json
 */
contract BatchVoteRecovered is RecoveryBatchBase {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (BatchConfig memory cfg, RevealEntry[] memory entries) = _loadRevealEntries(_defaultRevealPath());

        KaiSignRegistry registry = KaiSignRegistry(cfg.registry);
        IRealityETH reality = IRealityETH(cfg.reality);
        uint256 voteBond = registry.minBond() * 2;
        bytes32[] memory questionIds = new bytes32[](entries.length);

        console.log("=== VOTE RECOVERED BATCH ===");
        console.log("Registry:", cfg.registry);
        console.log("Entries:", entries.length);
        console.log("voteBond:", voteBond);

        vm.startBroadcast(privateKey);
        for (uint256 i = 0; i < entries.length; ++i) {
            (bytes32 questionId,) = registry.questions(entries[i].uid);
            questionIds[i] = questionId;
            reality.submitAnswerERC20(questionId, bytes32(uint256(1)), 0, voteBond);
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
                "\"uid\": \"", vm.toString(entries[i].uid), "\", ",
                "\"questionId\": \"", vm.toString(questionIds[i]), "\"",
                "}",
                i + 1 < entries.length ? ",\n" : "\n"
            );
        }

        out = abi.encodePacked(out, "  ]\n", "}\n");
        vm.writeFile(_defaultPendingPath(), string(out));
        console.log("Wrote", _defaultPendingPath());
        console.log("Next: wait ~48h for Reality.eth timeout, then run BatchFinalizeRecovered.s.sol");
    }
}
