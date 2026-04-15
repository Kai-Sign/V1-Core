// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KaiSignRegistry.sol";
import "../src/interfaces/IRealityETH.sol";
import "./RecoveryBatchBase.s.sol";

/**
 * @title ForkFinalizeRecovered
 * @notice Dry-run finalization of the recovered Sepolia batch on a local fork.
 *
 * This script is intended for a forked Sepolia execution only. It does not
 * broadcast and does not touch real chain state. It reads the consolidated
 * `deployments/sepolia-recovery-pending.json`, advances fork time if needed,
 * finalizes all 30 recovered attestations locally, and proves that:
 * 1. the Merkle root changes,
 * 2. currentIdx advances by the recovered batch count, and
 * 3. every recovered attestation ends in a finalized, approved state.
 *
 * Run:
 *   forge script script/ForkFinalizeRecovered.s.sol:ForkFinalizeRecovered \
 *     --fork-url $SEPOLIA_RPC_URL -vvv
 */
contract ForkFinalizeRecovered is Script, RecoveryBatchBase {
    function run() external {
        (BatchConfig memory cfg, PendingEntry[] memory entries) = _loadPendingEntries(_defaultPendingPath());

        KaiSignRegistry registry = KaiSignRegistry(cfg.registry);
        IRealityETH reality = IRealityETH(cfg.reality);

        bytes32 rootBefore = registry.merkleRoot();
        uint64 idxBefore = registry.currentIdx();
        uint256 tsBefore = block.timestamp;

        console.log("=== FORK FINALIZE RECOVERED ===");
        console.log("Registry:", cfg.registry);
        console.log("Recovered entries:", entries.length);
        console.log("currentIdx (before):", idxBefore);
        console.log("merkleRoot (before):");
        console.logBytes32(rootBefore);
        console.log("fork timestamp (before):", tsBefore);

        bool allReady = true;
        for (uint256 i = 0; i < entries.length; ++i) {
            if (!reality.isFinalized(entries[i].questionId)) {
                allReady = false;
                break;
            }
        }

        if (!allReady) {
            uint256 warped = tsBefore + 3 days;
            vm.warp(warped);
            vm.roll(block.number + 1);
            console.log("Warped fork timestamp to:", warped);
        }

        uint256 readyCount = 0;
        for (uint256 i = 0; i < entries.length; ++i) {
            if (reality.isFinalized(entries[i].questionId)) {
                readyCount++;
            } else {
                console.log("Still not finalized on fork for idx", entries[i].idx);
            }
        }
        require(readyCount == entries.length, "not all recovery questions finalized after warp");

        uint256 finalizedNow = 0;
        for (uint256 i = 0; i < entries.length; ++i) {
            IKaiSignRegistry.Attestation memory beforeAtt = registry.getAttestation(entries[i].uid);
            if (beforeAtt.finalizedAt != 0) continue;

            registry.finalize(entries[i].uid);
            finalizedNow++;

            IKaiSignRegistry.Attestation memory afterAtt = registry.getAttestation(entries[i].uid);
            require(afterAtt.finalizedAt != 0, "attestation not finalized");
            require(!afterAtt.revoked, "expected approved attestation");
            require(afterAtt.idx == entries[i].idx, "unexpected assigned idx");
            require(afterAtt.metadataHash == entries[i].metadataHash, "metadata hash drift");
            require(afterAtt.chainId == entries[i].chainId, "chainId drift");
            require(afterAtt.extcodehash == entries[i].extcodehash, "extcodehash drift");
        }

        bytes32 rootAfter = registry.merkleRoot();
        uint64 idxAfter = registry.currentIdx();

        console.log("Finalized in fork run:", finalizedNow);
        console.log("currentIdx (after):", idxAfter);
        console.log("merkleRoot (after):");
        console.logBytes32(rootAfter);

        require(rootAfter != rootBefore, "merkle root did not change");
        require(idxAfter == idxBefore + uint64(entries.length), "unexpected currentIdx delta");
        require(idxAfter == uint64(cfg.endIdx), "did not reach expected final idx");

        console.log("=== FORK FINALIZE OK ===");
    }
}
