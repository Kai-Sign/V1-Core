// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KaiSignRegistry} from "../src/KaiSignRegistry.sol";
import {IRealityETH} from "../src/interfaces/IRealityETH.sol";

/**
 * @title MockRealityETH
 * @notice Always returns finalized=true and result=1 (approved)
 */
contract MockRealityETH {
    function isFinalized(bytes32) external pure returns (bool) {
        return true;
    }

    function resultFor(bytes32) external pure returns (bytes32) {
        return bytes32(uint256(1)); // 1 = approved
    }

    // Stub other functions that might be called
    function createTemplate(string calldata) external pure returns (uint256) {
        return 1;
    }

    function askQuestionWithMinBond(
        uint256,
        string calldata,
        address,
        uint32,
        uint32,
        uint256,
        uint256
    ) external payable returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }
}

/**
 * @title LocalForkServer
 * @notice Adds a test attestation to a local Anvil fork of Sepolia
 * @dev Replaces Reality.eth with a mock that approves immediately
 *
 * Usage:
 *   # Start Anvil fork first, then:
 *   forge script script/LocalForkServer.s.sol:LocalForkServer \
 *     --rpc-url http://localhost:8545 \
 *     --broadcast \
 *     -vvv
 *
 * Environment variables:
 *   METADATA_FILE - Path to JSON metadata file (default: script/metadata/cow-ethflow.json)
 *   TARGET_ADDRESS - Contract address to attest (default: 0xba3cb449bd2b4adddbc894d8697f5170800eadec)
 *   TARGET_CHAIN_ID - Chain ID for the contract (default: 1 for mainnet)
 */
contract LocalForkServer is Script {
    // KaiSignRegistry on Sepolia (forked)
    address constant REGISTRY = 0xC203e8C22eFCA3C9218a6418f6d4281Cb7744dAa;

    // Reality.eth v3.0 Sepolia
    address constant REALITY_ETH = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;

    // Default test contract: CoW ETH Flow on mainnet
    address constant DEFAULT_TARGET = 0xbA3cB449bD2B4ADddBc894D8697F5170800EAdeC;
    uint256 constant DEFAULT_CHAIN_ID = 1;

    // Leaf typehash (must match KaiSignRegistry)
    bytes32 constant LEAF_TYPEHASH = keccak256(
        "RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,uint256 idx,bool revoked)"
    );

    function run() public {
        // Load configuration
        string memory metadataFile = vm.envOr("METADATA_FILE", string("script/metadata/cow-ethflow.json"));
        address targetAddress = vm.envOr("TARGET_ADDRESS", DEFAULT_TARGET);
        uint256 targetChainId = vm.envOr("TARGET_CHAIN_ID", DEFAULT_CHAIN_ID);

        console.log("=== Local Fork Server ===");
        console.log("Registry:", REGISTRY);
        console.log("Metadata file:", metadataFile);
        console.log("Target address:", targetAddress);
        console.log("Target chain ID:", targetChainId);

        // Read metadata and compute hash
        string memory metadata = vm.readFile(metadataFile);
        bytes32 metadataHash = keccak256(bytes(metadata));
        console.log("Metadata hash:");
        console.logBytes32(metadataHash);

        // Get extcodehash of target contract
        bytes32 extcodehash = _getExtcodehash(targetAddress, targetChainId);
        console.log("Extcodehash:");
        console.logBytes32(extcodehash);

        KaiSignRegistry registry = KaiSignRegistry(REGISTRY);

        // Get current state
        uint64 currentIdx = registry.currentIdx();
        bytes32 currentRoot = registry.merkleRoot();
        console.log("Current idx:", currentIdx);
        console.log("Current merkle root:");
        console.logBytes32(currentRoot);

        // Note: Reality.eth is replaced with mock by run-local-fork.sh before this runs
        // Note: Timestamp is fixed by run-local-fork.sh using evm_setNextBlockTimestamp

        vm.startBroadcast();

        // Step 1: Create a commitment
        // Use fixed values (not block.timestamp) so they match between simulation and broadcast
        bytes32 blobHash = keccak256(abi.encodePacked("test-blob-local-fork"));
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));

        console.log("\n--- Step 2: Commit ---");
        bytes32 commitmentId = registry.commitSpec(commitment, targetChainId, extcodehash);
        console.log("Commitment ID:");
        console.logBytes32(commitmentId);

        // Step 2: Reveal the spec (creates Reality.eth question)
        console.log("\n--- Step 2: Reveal ---");
        bytes32 uid = registry.revealSpec{value: 0.001 ether}(
            commitmentId,
            blobHash,
            nonce,
            metadataHash
        );
        console.log("Attestation UID:");
        console.logBytes32(uid);

        // Step 3: Compute merkle proof and finalize
        console.log("\n--- Step 3: Finalize ---");

        // Compute the new leaf
        uint64 newIdx = currentIdx + 1;
        bytes32 leaf = keccak256(abi.encode(
            LEAF_TYPEHASH,
            targetChainId,
            extcodehash,
            metadataHash,
            newIdx,
            false  // not revoked
        ));
        console.log("New leaf:");
        console.logBytes32(leaf);

        // Compute new merkle root and proof
        (bytes32 newRoot, bytes32[] memory proof) = _computeMerkleUpdate(
            currentRoot,
            currentIdx,
            leaf,
            newIdx
        );
        console.log("New merkle root:");
        console.logBytes32(newRoot);
        console.log("Proof length:", proof.length);

        // Finalize (mock Reality.eth will return approved)
        registry.finalize(uid, newRoot, proof);

        vm.stopBroadcast();

        // Verify final state
        console.log("\n=== FINAL STATE ===");
        console.log("New current idx:", registry.currentIdx());
        console.log("New merkle root:");
        console.logBytes32(registry.merkleRoot());

        console.log("\n=== SUCCESS ===");
        console.log("Attestation finalized!");
        console.log("UID:");
        console.logBytes32(uid);
        console.log("\nTo use in browser:");
        console.log("  localStorage.setItem('kaisign_local_rpc', 'http://localhost:8545')");
    }

    /**
     * @dev Get extcodehash for a contract
     */
    function _getExtcodehash(address target, uint256 chainId) internal view returns (bytes32) {
        // If we're on the same chain, use actual extcodehash
        if (block.chainid == chainId) {
            bytes32 hash;
            assembly {
                hash := extcodehash(target)
            }
            return hash;
        }

        // For cross-chain, use env var or known value
        bytes32 envHash = vm.envOr("TARGET_EXTCODEHASH", bytes32(0));
        if (envHash != bytes32(0)) {
            return envHash;
        }

        // Fallback: deterministic hash for testing
        return keccak256(abi.encodePacked("test-extcodehash-", target, chainId));
    }

    /**
     * @dev Compute merkle root update for appending a new leaf
     */
    function _computeMerkleUpdate(
        bytes32 currentRoot,
        uint64, // currentIdx unused
        bytes32 newLeaf,
        uint64 newIdx
    ) internal pure returns (bytes32 newRoot, bytes32[] memory proof) {
        // For the first leaf (idx=1), the root is just the leaf itself
        if (newIdx == 1) {
            return (newLeaf, new bytes32[](0));
        }

        // For idx=2: hash(leaf1, leaf2) where leaf1 = currentRoot
        if (newIdx == 2) {
            proof = new bytes32[](1);
            proof[0] = currentRoot;
            newRoot = keccak256(abi.encodePacked(currentRoot, newLeaf));
            return (newRoot, proof);
        }

        // For idx >= 3: simplified append using previous root as sibling
        uint256 position = newIdx - 1;
        proof = new bytes32[](1);
        proof[0] = currentRoot;

        if (position % 2 == 0) {
            newRoot = keccak256(abi.encodePacked(newLeaf, currentRoot));
        } else {
            newRoot = keccak256(abi.encodePacked(currentRoot, newLeaf));
        }

        return (newRoot, proof);
    }
}
