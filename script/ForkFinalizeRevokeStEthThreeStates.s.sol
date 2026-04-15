// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KaiSignRegistry.sol";
import "../src/PermissionedBToken.sol";
import "../src/interfaces/IRealityETH.sol";

/**
 * @title ForkFinalizeRevokeStEthThreeStates
 * @notice Shows three explicit states for the Sepolia stETH revoke flow:
 * 1. Direct Sepolia RPC snapshot
 * 2. Local Sepolia fork before local answer/finalization
 * 3. Local Sepolia fork after answer + warp + finalizeRevoke
 *
 * This is a local-fork dry run. No broadcast is performed.
 *
 * Run:
 *   anvil --fork-url $SEPOLIA_RPC_URL --chain-id 11155111 --port 8545
 *
 *   SEPOLIA_RPC_URL=$SEPOLIA_RPC_URL \
 *   forge script script/ForkFinalizeRevokeStEthThreeStates.s.sol:ForkFinalizeRevokeStEthThreeStates \
 *     --rpc-url http://127.0.0.1:8545 --ffi -vvv
 */
contract ForkFinalizeRevokeStEthThreeStates is Script {
    address internal constant REGISTRY_ADDR = 0xb910E44893713b072ABC6949fB4441ad09999bC6;
    bytes32 internal constant UID =
        0x0ea5970340f8b61d1fec24adafaaca78fe127021b7d6f7451cb70fc635b65c09;
    address internal constant DEFAULT_ANSWERER = 0xA295020e648d87468aA6BC32c9E13E2497c0244f;

    struct ForkState {
        uint64 currentIdx;
        bytes32 merkleRoot;
        uint256 timestamp;
        bool revoked;
        uint64 revokeIdx;
        uint64 revokeProposedAt;
        uint32 revokeAttempt;
        bytes32 questionId;
        bool questionFinalized;
        uint256 finalizeTs;
        bytes32 bestAnswer;
    }

    function _captureState(KaiSignRegistry registry, IRealityETH reality)
        internal
        view
        returns (ForkState memory s)
    {
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(UID);
        (bytes32 questionId,) = registry.revokeQuestions(UID);

        s.currentIdx = registry.currentIdx();
        s.merkleRoot = registry.merkleRoot();
        s.timestamp = block.timestamp;
        s.revoked = att.revoked;
        s.revokeIdx = att.revokeIdx;
        s.revokeProposedAt = att.revokeProposedAt;
        s.revokeAttempt = att.revokeAttempt;
        s.questionId = questionId;

        if (questionId != bytes32(0)) {
            s.questionFinalized = reality.isFinalized(questionId);
            s.finalizeTs = reality.getFinalizeTS(questionId);
            s.bestAnswer = reality.getBestAnswer(questionId);
        }
    }

    function _printState(string memory label, ForkState memory s) internal view {
        console.log(label);
        console.log("currentIdx:", s.currentIdx);
        console.log("merkleRoot:");
        console.logBytes32(s.merkleRoot);
        console.log("timestamp:", s.timestamp);
        console.log("revoked:", s.revoked);
        console.log("revokeIdx:", s.revokeIdx);
        console.log("revokeProposedAt:", s.revokeProposedAt);
        console.log("revokeAttempt:", s.revokeAttempt);
        console.log("questionId:");
        console.logBytes32(s.questionId);
        console.log("questionFinalized:", s.questionFinalized);
        console.log("finalizeTs:", s.finalizeTs);
        console.log("bestAnswer:");
        console.logBytes32(s.bestAnswer);
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

    function _rpcRpcHex(string[] memory cmd) internal returns (bytes memory out) {
        bytes memory raw = vm.ffi(cmd);
        return vm.parseBytes(_trim(string(raw)));
    }

    function _rpcCall(address target, string memory sig) internal returns (bytes memory out) {
        string memory rpcUrl = vm.envOr(
            "SEPOLIA_RPC_URL",
            string("https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5")
        );
        string[] memory calldataCmd = new string[](3);
        calldataCmd[0] = "cast";
        calldataCmd[1] = "calldata";
        calldataCmd[2] = sig;
        bytes memory data = vm.ffi(calldataCmd);

        string[] memory cmd = new string[](8);
        cmd[0] = "cast";
        cmd[1] = "rpc";
        cmd[2] = "eth_call";
        cmd[3] = string.concat("{\"to\":\"", vm.toString(target), "\",\"data\":\"", _trim(string(data)), "\"}");
        cmd[4] = "latest";
        cmd[5] = "--rpc-url";
        cmd[6] = rpcUrl;
        cmd[7] = "--raw";
        return _rpcRpcHex(cmd);
    }

    function _rpcCall(address target, string memory sig, bytes32 arg) internal returns (bytes memory out) {
        string memory rpcUrl = vm.envOr(
            "SEPOLIA_RPC_URL",
            string("https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5")
        );
        string[] memory calldataCmd = new string[](4);
        calldataCmd[0] = "cast";
        calldataCmd[1] = "calldata";
        calldataCmd[2] = sig;
        calldataCmd[3] = vm.toString(arg);
        bytes memory data = vm.ffi(calldataCmd);

        string[] memory cmd = new string[](8);
        cmd[0] = "cast";
        cmd[1] = "rpc";
        cmd[2] = "eth_call";
        cmd[3] = string.concat("{\"to\":\"", vm.toString(target), "\",\"data\":\"", _trim(string(data)), "\"}");
        cmd[4] = "latest";
        cmd[5] = "--rpc-url";
        cmd[6] = rpcUrl;
        cmd[7] = "--raw";
        return _rpcRpcHex(cmd);
    }

    function _rpcState(address registryAddr, address realityAddr) internal returns (ForkState memory s) {
        bytes memory idxOut = _rpcCall(registryAddr, "currentIdx()(uint64)");
        bytes memory rootOut = _rpcCall(registryAddr, "merkleRoot()(bytes32)");
        bytes memory attOut = _rpcCall(
            registryAddr,
            "getAttestation(bytes32)((bytes32,uint256,bytes32,bytes32,bytes32,address,uint64,uint64,bool,uint64,uint64,address,uint64,uint32))",
            UID
        );
        bytes memory revokeQuestionOut =
            _rpcCall(registryAddr, "revokeQuestions(bytes32)((bytes32,address))", UID);

        string memory rpcUrl = vm.envOr(
            "SEPOLIA_RPC_URL",
            string("https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5")
        );
        string[] memory blockCmd = new string[](3);
        blockCmd[0] = "sh";
        blockCmd[1] = "-c";
        blockCmd[2] = string.concat("printf 'dec:'; cast block latest --field timestamp --rpc-url ", rpcUrl);
        bytes memory timestampOut = vm.ffi(blockCmd);

        s.currentIdx = uint64(_ffiToUint(idxOut));
        s.merkleRoot = _ffiToBytes32(rootOut);
        s.timestamp = _ffiToUint(timestampOut);

        (
            bytes32 uid,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bool revoked,
            ,
            uint64 revokeProposedAt,
            ,
            uint64 revokeIdx,
            uint32 revokeAttempt
        ) = abi.decode(attOut, (bytes32, uint256, bytes32, bytes32, bytes32, address, uint64, uint64, bool, uint64, uint64, address, uint64, uint32));

        (bytes32 questionId,) = abi.decode(revokeQuestionOut, (bytes32, address));

        require(uid == UID, "rpc attestation uid mismatch");
        s.revoked = revoked;
        s.revokeIdx = revokeIdx;
        s.revokeProposedAt = revokeProposedAt;
        s.revokeAttempt = revokeAttempt;
        s.questionId = questionId;

        if (questionId != bytes32(0)) {
            s.questionFinalized = abi.decode(_rpcCall(realityAddr, "isFinalized(bytes32)(bool)", questionId), (bool));
            s.finalizeTs = abi.decode(_rpcCall(realityAddr, "getFinalizeTS(bytes32)(uint32)", questionId), (uint32));
            s.bestAnswer = abi.decode(_rpcCall(realityAddr, "getBestAnswer(bytes32)(bytes32)", questionId), (bytes32));
        }
    }

    function run() external {
        KaiSignRegistry registry = KaiSignRegistry(REGISTRY_ADDR);
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(UID);
        require(att.finalizedAt != 0, "stETH attestation not finalized");
        require(!att.revoked, "stETH attestation already revoked");

        (bytes32 questionId, IRealityETH reality) = registry.revokeQuestions(UID);
        require(questionId != bytes32(0), "no revoke proposal found");

        PermissionedBToken token = PermissionedBToken(address(registry.bondToken()));
        uint256 minBond = registry.minBond();
        address answerer = vm.envOr("ANSWERER", DEFAULT_ANSWERER);

        ForkState memory state1 = _rpcState(REGISTRY_ADDR, address(reality));
        _printState("=== STATE 1: SEPOLIA RPC SNAPSHOT ===", state1);

        ForkState memory state2 = _captureState(registry, reality);
        _printState("=== STATE 2: LOCAL FORK BEFORE ANSWER/FINALIZE ===", state2);

        require(state1.currentIdx == state2.currentIdx, "snapshot/local idx drift");
        require(state1.merkleRoot == state2.merkleRoot, "snapshot/local root drift");
        require(state2.questionId == questionId, "questionId drift");

        if (state2.bestAnswer != bytes32(uint256(1))) {
            vm.startPrank(answerer);
            token.approve(address(reality), minBond);
            reality.submitAnswerERC20(questionId, bytes32(uint256(1)), 0, minBond);
            vm.stopPrank();
            console.log("Submitted local fork answer: YES");
        }

        uint256 finalizeTs = reality.getFinalizeTS(questionId);
        require(finalizeTs != 0, "revoke finalize timestamp not set");

        if (!reality.isFinalized(questionId)) {
            uint256 warped = finalizeTs + 1;
            vm.warp(warped);
            vm.roll(block.number + 1);
            console.log("Warped local fork timestamp to:", warped);
        }

        require(reality.isFinalized(questionId), "revoke question not finalized after warp");

        registry.finalizeRevoke(UID);

        ForkState memory state3 = _captureState(registry, reality);
        _printState("=== STATE 3: LOCAL FORK AFTER ANSWER + WARP + FINALIZE ===", state3);

        require(state3.revoked, "expected revoked attestation");
        require(state3.revokeIdx == state2.currentIdx + 1, "unexpected revoke idx");
        require(state3.currentIdx == state2.currentIdx + 1, "currentIdx did not increment");
        require(state3.merkleRoot != state2.merkleRoot, "merkle root did not change");
        require(state3.revokeProposedAt == 0, "revoke proposal not cleared");
        require(state3.questionId == bytes32(0), "revoke question not cleared");

        console.log("=== THREE-STATE REVOKE CHECK OK ===");
    }
}
