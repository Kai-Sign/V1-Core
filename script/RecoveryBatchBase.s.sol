// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KaiSignRegistry.sol";
import "../src/PermissionedBToken.sol";
import "../src/interfaces/IRealityETH.sol";

abstract contract RecoveryBatchBase is Script {
    error DuplicateRecoveryTarget(uint256 chainId, bytes32 extcodehash, uint256 firstIndex, uint256 secondIndex);

    struct BatchEntry {
        string path;
        uint256 idx;
        uint256 chainId;
        bytes32 extcodehash;
        bytes32 metadataHash;
        uint256 nonce;
        bytes32 blobHash;
    }

    struct CommitEntry {
        string path;
        uint256 idx;
        uint256 chainId;
        bytes32 extcodehash;
        bytes32 metadataHash;
        uint256 nonce;
        bytes32 blobHash;
        bytes32 commitmentId;
    }

    struct RevealEntry {
        string path;
        uint256 idx;
        uint256 chainId;
        bytes32 extcodehash;
        bytes32 metadataHash;
        uint256 nonce;
        bytes32 blobHash;
        bytes32 commitmentId;
        bytes32 uid;
    }

    struct PendingEntry {
        string path;
        uint256 idx;
        uint256 chainId;
        bytes32 extcodehash;
        bytes32 metadataHash;
        bytes32 uid;
        bytes32 questionId;
    }

    struct BatchConfig {
        address registry;
        address reality;
        address btoken;
        uint256 startIdx;
        uint256 endIdx;
        uint256 count;
    }

    function _defaultBatchPath() internal pure returns (string memory) {
        return "deployments/sepolia-recovery-batch.json";
    }

    function _defaultCommitPath() internal pure returns (string memory) {
        return "deployments/sepolia-recovery-commits.json";
    }

    function _defaultRevealPath() internal pure returns (string memory) {
        return "deployments/sepolia-recovery-reveals.json";
    }

    function _defaultPendingPath() internal pure returns (string memory) {
        return "deployments/sepolia-recovery-pending.json";
    }

    function _loadBatchConfig(string memory filePath) internal view returns (BatchConfig memory cfg) {
        string memory json = vm.readFile(filePath);
        cfg.registry = vm.parseJsonAddress(json, ".registry");
        cfg.reality = vm.parseJsonAddress(json, ".realityETH");
        cfg.btoken = vm.parseJsonAddress(json, ".btoken");
        cfg.startIdx = vm.parseJsonUint(json, ".startIdx");
        cfg.endIdx = vm.parseJsonUint(json, ".endIdx");
        cfg.count = vm.parseJsonUint(json, ".count");
    }

    function _loadBatchEntries(string memory filePath) internal view returns (BatchConfig memory cfg, BatchEntry[] memory entries) {
        string memory json = vm.readFile(filePath);
        cfg.registry = vm.parseJsonAddress(json, ".registry");
        cfg.reality = vm.parseJsonAddress(json, ".realityETH");
        cfg.btoken = vm.parseJsonAddress(json, ".btoken");
        cfg.startIdx = vm.parseJsonUint(json, ".startIdx");
        cfg.endIdx = vm.parseJsonUint(json, ".endIdx");
        cfg.count = vm.parseJsonUint(json, ".count");
        entries = new BatchEntry[](cfg.count);

        for (uint256 i = 0; i < cfg.count; ++i) {
            string memory prefix = string.concat(".entries[", vm.toString(i), "]");
            entries[i] = BatchEntry({
                path: vm.parseJsonString(json, string.concat(prefix, ".path")),
                idx: vm.parseJsonUint(json, string.concat(prefix, ".idx")),
                chainId: vm.parseJsonUint(json, string.concat(prefix, ".chainId")),
                extcodehash: vm.parseJsonBytes32(json, string.concat(prefix, ".extcodehash")),
                metadataHash: vm.parseJsonBytes32(json, string.concat(prefix, ".metadataHash")),
                nonce: vm.parseJsonUint(json, string.concat(prefix, ".nonce")),
                blobHash: vm.parseJsonBytes32(json, string.concat(prefix, ".blobHash"))
            });
        }

        _requireUniqueTargets(entries);
    }

    function _loadCommitEntries(string memory filePath) internal view returns (BatchConfig memory cfg, CommitEntry[] memory entries) {
        string memory json = vm.readFile(filePath);
        cfg.registry = vm.parseJsonAddress(json, ".registry");
        cfg.reality = vm.parseJsonAddress(json, ".realityETH");
        cfg.btoken = vm.parseJsonAddress(json, ".btoken");
        cfg.startIdx = vm.parseJsonUint(json, ".startIdx");
        cfg.endIdx = vm.parseJsonUint(json, ".endIdx");
        cfg.count = vm.parseJsonUint(json, ".count");
        entries = new CommitEntry[](cfg.count);

        for (uint256 i = 0; i < cfg.count; ++i) {
            string memory prefix = string.concat(".entries[", vm.toString(i), "]");
            entries[i] = CommitEntry({
                path: vm.parseJsonString(json, string.concat(prefix, ".path")),
                idx: vm.parseJsonUint(json, string.concat(prefix, ".idx")),
                chainId: vm.parseJsonUint(json, string.concat(prefix, ".chainId")),
                extcodehash: vm.parseJsonBytes32(json, string.concat(prefix, ".extcodehash")),
                metadataHash: vm.parseJsonBytes32(json, string.concat(prefix, ".metadataHash")),
                nonce: vm.parseJsonUint(json, string.concat(prefix, ".nonce")),
                blobHash: vm.parseJsonBytes32(json, string.concat(prefix, ".blobHash")),
                commitmentId: vm.parseJsonBytes32(json, string.concat(prefix, ".commitmentId"))
            });
        }

        _requireUniqueTargets(entries);
    }

    function _loadRevealEntries(string memory filePath) internal view returns (BatchConfig memory cfg, RevealEntry[] memory entries) {
        string memory json = vm.readFile(filePath);
        cfg.registry = vm.parseJsonAddress(json, ".registry");
        cfg.reality = vm.parseJsonAddress(json, ".realityETH");
        cfg.btoken = vm.parseJsonAddress(json, ".btoken");
        cfg.startIdx = vm.parseJsonUint(json, ".startIdx");
        cfg.endIdx = vm.parseJsonUint(json, ".endIdx");
        cfg.count = vm.parseJsonUint(json, ".count");
        entries = new RevealEntry[](cfg.count);

        for (uint256 i = 0; i < cfg.count; ++i) {
            string memory prefix = string.concat(".entries[", vm.toString(i), "]");
            entries[i] = RevealEntry({
                path: vm.parseJsonString(json, string.concat(prefix, ".path")),
                idx: vm.parseJsonUint(json, string.concat(prefix, ".idx")),
                chainId: vm.parseJsonUint(json, string.concat(prefix, ".chainId")),
                extcodehash: vm.parseJsonBytes32(json, string.concat(prefix, ".extcodehash")),
                metadataHash: vm.parseJsonBytes32(json, string.concat(prefix, ".metadataHash")),
                nonce: vm.parseJsonUint(json, string.concat(prefix, ".nonce")),
                blobHash: vm.parseJsonBytes32(json, string.concat(prefix, ".blobHash")),
                commitmentId: vm.parseJsonBytes32(json, string.concat(prefix, ".commitmentId")),
                uid: vm.parseJsonBytes32(json, string.concat(prefix, ".uid"))
            });
        }

        _requireUniqueTargets(entries);
    }

    function _loadPendingEntries(string memory filePath) internal view returns (BatchConfig memory cfg, PendingEntry[] memory entries) {
        string memory json = vm.readFile(filePath);
        cfg.registry = vm.parseJsonAddress(json, ".registry");
        cfg.reality = vm.parseJsonAddress(json, ".realityETH");
        cfg.btoken = vm.parseJsonAddress(json, ".btoken");
        cfg.startIdx = vm.parseJsonUint(json, ".startIdx");
        cfg.endIdx = vm.parseJsonUint(json, ".endIdx");
        cfg.count = vm.parseJsonUint(json, ".count");
        entries = new PendingEntry[](cfg.count);

        for (uint256 i = 0; i < cfg.count; ++i) {
            string memory prefix = string.concat(".entries[", vm.toString(i), "]");
            entries[i] = PendingEntry({
                path: vm.parseJsonString(json, string.concat(prefix, ".path")),
                idx: vm.parseJsonUint(json, string.concat(prefix, ".idx")),
                chainId: vm.parseJsonUint(json, string.concat(prefix, ".chainId")),
                extcodehash: vm.parseJsonBytes32(json, string.concat(prefix, ".extcodehash")),
                metadataHash: vm.parseJsonBytes32(json, string.concat(prefix, ".metadataHash")),
                uid: vm.parseJsonBytes32(json, string.concat(prefix, ".uid")),
                questionId: vm.parseJsonBytes32(json, string.concat(prefix, ".questionId"))
            });
        }

        _requireUniqueTargets(entries);
    }

    function _requireUniqueTargets(BatchEntry[] memory entries) internal pure {
        for (uint256 i = 0; i < entries.length; ++i) {
            for (uint256 j = i + 1; j < entries.length; ++j) {
                if (entries[i].chainId == entries[j].chainId && entries[i].extcodehash == entries[j].extcodehash) {
                    revert DuplicateRecoveryTarget(entries[i].chainId, entries[i].extcodehash, entries[i].idx, entries[j].idx);
                }
            }
        }
    }

    function _requireUniqueTargets(CommitEntry[] memory entries) internal pure {
        for (uint256 i = 0; i < entries.length; ++i) {
            for (uint256 j = i + 1; j < entries.length; ++j) {
                if (entries[i].chainId == entries[j].chainId && entries[i].extcodehash == entries[j].extcodehash) {
                    revert DuplicateRecoveryTarget(entries[i].chainId, entries[i].extcodehash, entries[i].idx, entries[j].idx);
                }
            }
        }
    }

    function _requireUniqueTargets(RevealEntry[] memory entries) internal pure {
        for (uint256 i = 0; i < entries.length; ++i) {
            for (uint256 j = i + 1; j < entries.length; ++j) {
                if (entries[i].chainId == entries[j].chainId && entries[i].extcodehash == entries[j].extcodehash) {
                    revert DuplicateRecoveryTarget(entries[i].chainId, entries[i].extcodehash, entries[i].idx, entries[j].idx);
                }
            }
        }
    }

    function _requireUniqueTargets(PendingEntry[] memory entries) internal pure {
        for (uint256 i = 0; i < entries.length; ++i) {
            for (uint256 j = i + 1; j < entries.length; ++j) {
                if (entries[i].chainId == entries[j].chainId && entries[i].extcodehash == entries[j].extcodehash) {
                    revert DuplicateRecoveryTarget(entries[i].chainId, entries[i].extcodehash, entries[i].idx, entries[j].idx);
                }
            }
        }
    }
}
