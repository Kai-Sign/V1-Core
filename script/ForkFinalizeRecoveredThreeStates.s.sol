// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KaiSignRegistry.sol";
import "../src/interfaces/IRealityETH.sol";
import "./RecoveryBatchBase.s.sol";

/**
 * @title ForkFinalizeRecoveredThreeStates
 * @notice Shows three explicit states for the recovered Sepolia batch:
 * 1. Direct Sepolia RPC snapshot
 * 2. Local Sepolia fork before time travel/finalization
 * 3. Local Sepolia fork after warp + finalize
 *
 * This is a local-fork dry run. No broadcast is performed.
 *
 * Run:
 *   anvil --fork-url $SEPOLIA_RPC_URL --chain-id 11155111 --port 8545
 *
 *   SEPOLIA_RPC_URL=$SEPOLIA_RPC_URL \
 *   forge script script/ForkFinalizeRecoveredThreeStates.s.sol:ForkFinalizeRecoveredThreeStates \
 *     --rpc-url http://127.0.0.1:8545 --ffi -vvv
 */
contract ForkFinalizeRecoveredThreeStates is Script, RecoveryBatchBase {
    struct ForkState {
        uint64 currentIdx;
        bytes32 merkleRoot;
        uint256 timestamp;
    }

    function _captureState(KaiSignRegistry registry) internal view returns (ForkState memory s) {
        s.currentIdx = registry.currentIdx();
        s.merkleRoot = registry.merkleRoot();
        s.timestamp = block.timestamp;
    }

    function _printState(string memory label, ForkState memory s) internal view {
        console.log(label);
        console.log("currentIdx:", s.currentIdx);
        console.log("merkleRoot:");
        console.logBytes32(s.merkleRoot);
        console.log("timestamp:", s.timestamp);
    }

    function _trim(string memory value) internal pure returns (string memory) {
        bytes memory raw = bytes(value);
        uint256 len = raw.length;
        while (len > 0) {
            bytes1 c = raw[len - 1];
            if (c == "\n" || c == "\r" || c == " " || c == "\t") {
                len--;
            } else {
                break;
            }
        }

        bytes memory out = new bytes(len);
        for (uint256 i = 0; i < len; ++i) out[i] = raw[i];
        return string(out);
    }

    function _stripDecPrefix(bytes memory raw) internal pure returns (bytes memory out) {
        if (raw.length >= 4 && raw[0] == "d" && raw[1] == "e" && raw[2] == "c" && raw[3] == ":") {
            out = new bytes(raw.length - 4);
            for (uint256 i = 4; i < raw.length; ++i) out[i - 4] = raw[i];
            return out;
        }
        return raw;
    }

    function _isAsciiNumber(bytes memory data) internal pure returns (bool) {
        if (data.length == 0) return false;
        for (uint256 i = 0; i < data.length; ++i) {
            bytes1 c = data[i];
            bool ok = (c >= "0" && c <= "9") || c == "x" || c == "X" || c == "a" || c == "b" || c == "c"
                || c == "d" || c == "e" || c == "f" || c == "A" || c == "B" || c == "C" || c == "D" || c == "E"
                || c == "F" || c == "\n" || c == "\r";
            if (!ok) return false;
        }
        return true;
    }

    function _ffiToUint(bytes memory raw) internal view returns (uint256) {
        raw = _stripDecPrefix(raw);

        if (_isAsciiNumber(raw)) {
            return vm.parseUint(_trim(string(raw)));
        }

        uint256 out;
        for (uint256 i = 0; i < raw.length; ++i) {
            out = (out << 8) | uint8(raw[i]);
        }
        return out;
    }

    function _ffiToBytes32(bytes memory raw) internal view returns (bytes32 out) {
        if (raw.length == 32) {
            assembly {
                out := mload(add(raw, 32))
            }
            return out;
        }

        return vm.parseBytes32(_trim(string(raw)));
    }

    function _rpcState(address registryAddr) internal returns (ForkState memory s) {
        string memory rpcUrl = vm.envOr(
            "SEPOLIA_RPC_URL",
            string("https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5")
        );

        string[] memory currentIdxCmd = new string[](3);
        currentIdxCmd[0] = "sh";
        currentIdxCmd[1] = "-c";
        currentIdxCmd[2] = string.concat(
            "printf 'dec:'; cast call ",
            vm.toString(registryAddr),
            " 'currentIdx()(uint64)' --rpc-url ",
            rpcUrl
        );

        string[] memory merkleRootCmd = new string[](6);
        merkleRootCmd[0] = "cast";
        merkleRootCmd[1] = "call";
        merkleRootCmd[2] = vm.toString(registryAddr);
        merkleRootCmd[3] = "merkleRoot()(bytes32)";
        merkleRootCmd[4] = "--rpc-url";
        merkleRootCmd[5] = rpcUrl;

        string[] memory blockCmd = new string[](3);
        blockCmd[0] = "sh";
        blockCmd[1] = "-c";
        blockCmd[2] =
            string.concat("printf 'dec:'; cast block latest --field timestamp --rpc-url ", rpcUrl);

        bytes memory currentIdxOut = vm.ffi(currentIdxCmd);
        bytes memory merkleRootOut = vm.ffi(merkleRootCmd);
        bytes memory timestampOut = vm.ffi(blockCmd);

        s.currentIdx = uint64(_ffiToUint(currentIdxOut));
        s.merkleRoot = _ffiToBytes32(merkleRootOut);
        s.timestamp = _ffiToUint(timestampOut);
    }

    function run() external {
        (BatchConfig memory cfg, PendingEntry[] memory entries) = _loadPendingEntries(_defaultPendingPath());

        KaiSignRegistry registry = KaiSignRegistry(cfg.registry);
        IRealityETH reality = IRealityETH(cfg.reality);

        ForkState memory state1 = _rpcState(cfg.registry);
        _printState("=== STATE 1: SEPOLIA RPC SNAPSHOT ===", state1);

        ForkState memory state2 = _captureState(registry);
        _printState("=== STATE 2: LOCAL FORK BEFORE FINALIZE ===", state2);

        require(state1.currentIdx == state2.currentIdx, "snapshot/local idx drift");
        require(state1.merkleRoot == state2.merkleRoot, "snapshot/local root drift");

        bool allReady = true;
        for (uint256 i = 0; i < entries.length; ++i) {
            if (!reality.isFinalized(entries[i].questionId)) {
                allReady = false;
                break;
            }
        }

        if (!allReady) {
            uint256 warped = block.timestamp + 3 days;
            vm.warp(warped);
            vm.roll(block.number + 1);
            console.log("Warped local fork timestamp to:", warped);
        }

        uint256 readyCount = 0;
        for (uint256 i = 0; i < entries.length; ++i) {
            if (reality.isFinalized(entries[i].questionId)) readyCount++;
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

        ForkState memory state3 = _captureState(registry);
        _printState("=== STATE 3: LOCAL FORK AFTER WARP + FINALIZE ===", state3);

        console.log("Finalized in local fork run:", finalizedNow);

        require(state3.merkleRoot != state2.merkleRoot, "merkle root did not change");
        require(state3.currentIdx == state2.currentIdx + uint64(entries.length), "unexpected currentIdx delta");
        require(state3.currentIdx == uint64(cfg.endIdx), "did not reach expected final idx");

        console.log("=== THREE-STATE CHECK OK ===");
    }
}
