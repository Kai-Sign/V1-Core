// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RecoveryBatchBase.s.sol";

/**
 * @title BatchFinalizeRecovered
 * @notice Finalizes any ready attestations in the pending recovery batch.
 *         Safe to rerun; already-finalized entries are skipped.
 *
 * Input:
 *   deployments/sepolia-recovery-pending.json
 */
contract BatchFinalizeRecovered is RecoveryBatchBase {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        string memory pendingPath = vm.envOr("PENDING_PATH", _defaultPendingPath());
        (BatchConfig memory cfg, PendingEntry[] memory entries) = _loadPendingEntries(pendingPath);

        KaiSignRegistry registry = KaiSignRegistry(cfg.registry);
        IRealityETH reality = IRealityETH(cfg.reality);

        console.log("=== FINALIZE RECOVERED BATCH ===");
        console.log("Pending file:", pendingPath);
        console.log("Registry:", cfg.registry);
        console.log("Entries:", entries.length);
        console.log("merkleRoot (before):");
        console.logBytes32(registry.merkleRoot());
        console.log("currentIdx (before):", registry.currentIdx());

        vm.startBroadcast(privateKey);
        for (uint256 i = 0; i < entries.length; ++i) {
            IKaiSignRegistry.Attestation memory att = registry.getAttestation(entries[i].uid);
            if (att.finalizedAt != 0) {
                console.log("Skip already finalized idx", entries[i].idx);
                continue;
            }

            bool ready = reality.isFinalized(entries[i].questionId);
            if (!ready) {
                console.log("Skip not ready idx", entries[i].idx);
                continue;
            }

            registry.finalize(entries[i].uid);
            console.log("Finalized idx", entries[i].idx);
        }
        vm.stopBroadcast();

        console.log("merkleRoot (after):");
        console.logBytes32(registry.merkleRoot());
        console.log("currentIdx (after):", registry.currentIdx());
    }
}
