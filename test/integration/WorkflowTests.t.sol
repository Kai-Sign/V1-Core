// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";

/**
 * @title WorkflowTests
 * @notice End-to-end workflow tests for KaiSignRegistry
 * @dev Adapted from V1 PracticalWorkflowTest.t.sol for V2 with Reality.eth integration
 */
contract WorkflowTests is Test {
    // ========== CONSTANTS ==========
    address constant REALITY_ETH_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;
    address constant NO_ARBITRATOR = address(0);
    uint256 constant MIN_BOND = 0.01 ether;
    uint32 constant DEFAULT_TIMEOUT = 48 hours;
    bytes32 constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,uint256 idx,bool revoked)");

    // ========== STATE ==========
    KaiSignRegistry public registry;
    IRealityETH public realityETH;

    address public owner;
    address public specProvider;
    address public voter1;
    address public voter2;
    address public revoker;

    // ========== SETUP ==========

    function setUp() public {
        string memory rpcUrl = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpcUrl);

        owner = makeAddr("owner");
        specProvider = makeAddr("specProvider");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        revoker = makeAddr("revoker");

        vm.deal(owner, 100 ether);
        vm.deal(specProvider, 100 ether);
        vm.deal(voter1, 100 ether);
        vm.deal(voter2, 100 ether);
        vm.deal(revoker, 100 ether);

        vm.startPrank(owner);
        address[] memory attesters = new address[](2);
        attesters[0] = specProvider;
        attesters[1] = revoker;

        registry = new KaiSignRegistry(
            1, address(0), owner, attesters,
            REALITY_ETH_SEPOLIA, NO_ARBITRATOR, MIN_BOND
        );
        vm.stopPrank();

        realityETH = IRealityETH(REALITY_ETH_SEPOLIA);
    }

    // ========== WORKFLOW 1: COMPLETE APPROVAL FLOW ==========

    function test_Workflow_CompleteApprovalFlow() public {
        console.log("\n=== Workflow: Complete Approval Flow ===\n");

        // Test data
        bytes32 blobHash = keccak256("erc7730-metadata-json");
        bytes32 metadataHash = keccak256("erc7730-metadata-content");
        bytes32 extcodehash = keccak256("uniswap-v3-router-bytecode");
        uint256 chainId = 1;
        uint256 nonce = block.timestamp;

        // Step 1: Provider commits spec
        console.log("Step 1: Commit spec");
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));

        vm.prank(specProvider);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);

        assertTrue(commitmentId != bytes32(0), "Commitment should be created");
        console.log("   Commitment ID:", vm.toString(commitmentId));

        // Step 2: Provider reveals spec with bond
        console.log("Step 2: Reveal spec with", MIN_BOND, "ETH bond");

        vm.prank(specProvider);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, blobHash, nonce, metadataHash);

        assertTrue(uid != bytes32(0), "UID should be created");
        console.log("   UID:", vm.toString(uid));

        bytes32 questionId = registry.questionIds(uid);
        console.log("   Question ID:", vm.toString(questionId));

        // Step 3: Community votes APPROVE
        console.log("Step 3: Community votes APPROVE");

        vm.prank(voter1);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0);
        console.log("   voter1 submitted APPROVE with", MIN_BOND);

        vm.prank(voter2);
        realityETH.submitAnswer{value: MIN_BOND * 2}(questionId, bytes32(uint256(1)), MIN_BOND);
        console.log("   voter2 submitted APPROVE with", MIN_BOND * 2);

        // Step 4: Wait for timeout
        console.log("Step 4: Wait for timeout (48 hours)");
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        assertTrue(realityETH.isFinalized(questionId), "Question should be finalized");
        bytes32 result = realityETH.resultFor(questionId);
        assertEq(uint256(result), 1, "Result should be APPROVE");

        // Step 5: Finalize on registry
        console.log("Step 5: Finalize on registry");

        bytes32 leaf = keccak256(abi.encode(LEAF_TYPEHASH, chainId, extcodehash, metadataHash, uint64(1), false));
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(specProvider);
        registry.finalize(uid, leaf, proof);

        // Step 6: Verify final state
        console.log("Step 6: Verify final state");

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.finalizedAt > 0, "Should be finalized");
        assertEq(att.idx, 1, "Should be indexed at position 1");
        assertFalse(att.revoked, "Should not be revoked");

        // Verify indexed
        bytes32[] memory specs = registry.getSpecsForBytecode(chainId, extcodehash);
        assertEq(specs.length, 1, "Should have 1 spec");
        assertEq(specs[0], uid, "Should be our UID");

        (bytes32 latestUid, bool valid) = registry.getLatestSpecForBytecode(chainId, extcodehash);
        assertEq(latestUid, uid, "Latest should be our UID");
        assertTrue(valid, "Should be valid");

        console.log("   finalizedAt:", att.finalizedAt);
        console.log("   idx:", att.idx);
        console.log("   revoked:", att.revoked);

        console.log("\n=== Approval Flow Complete ===\n");
    }

    // ========== WORKFLOW 2: REJECTION FLOW ==========

    function test_Workflow_RejectionFlow() public {
        console.log("\n=== Workflow: Rejection Flow ===\n");

        bytes32 blobHash = keccak256("bad-metadata");
        bytes32 metadataHash = keccak256("bad-metadata-content");
        bytes32 extcodehash = keccak256("some-contract");
        uint256 chainId = 1;
        uint256 nonce = block.timestamp;

        // Step 1: Submit spec
        console.log("Step 1: Submit spec");

        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        vm.prank(specProvider);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);

        vm.prank(specProvider);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, blobHash, nonce, metadataHash);

        bytes32 questionId = registry.questionIds(uid);
        console.log("   UID:", vm.toString(uid));

        // Step 2: Community votes REJECT
        console.log("Step 2: Community votes REJECT");

        vm.prank(voter1);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(0)), 0);
        console.log("   voter1 submitted REJECT");

        // Step 3: Wait for timeout
        console.log("Step 3: Wait for timeout");
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        bytes32 result = realityETH.resultFor(questionId);
        assertEq(uint256(result), 0, "Result should be REJECT");

        // Step 4: Finalize
        console.log("Step 4: Finalize rejected spec");

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(specProvider);
        registry.finalize(uid, bytes32(0), proof);

        // Step 5: Verify NOT indexed
        console.log("Step 5: Verify NOT indexed");

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.finalizedAt > 0, "Should be finalized");
        assertEq(att.idx, 0, "Should NOT be indexed (idx=0)");
        assertTrue(att.revoked, "Should be marked as revoked");

        bytes32[] memory specs = registry.getSpecsForBytecode(chainId, extcodehash);
        assertEq(specs.length, 0, "Should have no indexed specs");

        console.log("   finalizedAt:", att.finalizedAt);
        console.log("   idx:", att.idx);
        console.log("   revoked:", att.revoked);

        console.log("\n=== Rejection Flow Complete ===\n");
    }

    // ========== WORKFLOW 3: REVOCATION FLOW ==========

    function test_Workflow_RevocationFlow() public {
        console.log("\n=== Workflow: Revocation Flow ===\n");

        bytes32 blobHash = keccak256("initially-good-metadata");
        bytes32 metadataHash = keccak256("initially-good-metadata-content");
        bytes32 extcodehash = keccak256("target-contract");
        uint256 chainId = 1;
        uint256 nonce = block.timestamp;

        // Step 1: Submit and approve spec
        console.log("Step 1: Submit and approve spec");

        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        vm.prank(specProvider);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);

        vm.prank(specProvider);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, blobHash, nonce, metadataHash);

        bytes32 questionId = registry.questionIds(uid);

        vm.prank(voter1);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0);

        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        bytes32 leaf = keccak256(abi.encode(LEAF_TYPEHASH, chainId, extcodehash, metadataHash, uint64(1), false));
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(specProvider);
        registry.finalize(uid, leaf, proof);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertEq(att.idx, 1, "Should be indexed");
        assertFalse(att.revoked, "Should not be revoked yet");

        console.log("   Spec approved and indexed at idx:", att.idx);

        // Step 2: Someone proposes revocation
        console.log("Step 2: Propose revocation");

        vm.prank(revoker);
        registry.proposeRevoke{value: MIN_BOND}(uid);

        bytes32 revokeQuestionId = registry.revokeQuestionIds(uid);
        assertTrue(revokeQuestionId != bytes32(0), "Revoke question should be created");
        console.log("   Revoke Question ID:", vm.toString(revokeQuestionId));

        // Step 3: Community votes to revoke
        console.log("Step 3: Community votes to REVOKE");

        vm.prank(voter1);
        realityETH.submitAnswer{value: MIN_BOND}(revokeQuestionId, bytes32(uint256(1)), 0);
        console.log("   voter1 voted to REVOKE");

        // Step 4: Wait and finalize revoke
        console.log("Step 4: Wait and finalize revoke");

        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        vm.prank(revoker);
        registry.finalizeRevoke(uid);

        // Step 5: Verify revoked
        console.log("Step 5: Verify revoked");

        att = registry.getAttestation(uid);
        assertTrue(att.revoked, "Should be revoked");

        // Check latest spec validity
        (, bool valid) = registry.getLatestSpecForBytecode(chainId, extcodehash);
        assertFalse(valid, "Latest spec should be invalid (revoked)");

        console.log("   revoked:", att.revoked);
        console.log("   Latest spec valid:", valid);

        console.log("\n=== Revocation Flow Complete ===\n");
    }

    // ========== WORKFLOW 4: ESCALATION BATTLE ==========

    function test_Workflow_EscalationBattle() public {
        console.log("\n=== Workflow: Escalation Battle ===\n");

        bytes32 blobHash = keccak256("controversial-metadata");
        bytes32 metadataHash = keccak256("controversial-metadata-content");
        bytes32 extcodehash = keccak256("controversial-contract");
        uint256 chainId = 1;
        uint256 nonce = block.timestamp;

        // Submit spec
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        vm.prank(specProvider);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);

        vm.prank(specProvider);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, blobHash, nonce, metadataHash);

        bytes32 questionId = registry.questionIds(uid);
        console.log("Spec submitted, questionId:", vm.toString(questionId));

        // Escalation battle
        console.log("\n--- Escalation Battle ---");

        // Round 1: voter1 says APPROVE
        vm.prank(voter1);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0);
        console.log("Round 1: voter1 APPROVE with", MIN_BOND);

        bytes32 currentAnswer = realityETH.getBestAnswer(questionId);
        assertEq(uint256(currentAnswer), 1, "Current answer should be APPROVE");

        // Round 2: voter2 says REJECT with higher bond
        vm.prank(voter2);
        realityETH.submitAnswer{value: MIN_BOND * 2}(questionId, bytes32(uint256(0)), MIN_BOND);
        console.log("Round 2: voter2 REJECT with", MIN_BOND * 2);

        currentAnswer = realityETH.getBestAnswer(questionId);
        assertEq(uint256(currentAnswer), 0, "Current answer should be REJECT");

        // Round 3: voter1 escalates back to APPROVE
        vm.prank(voter1);
        realityETH.submitAnswer{value: MIN_BOND * 4}(questionId, bytes32(uint256(1)), MIN_BOND * 2);
        console.log("Round 3: voter1 APPROVE with", MIN_BOND * 4);

        currentAnswer = realityETH.getBestAnswer(questionId);
        assertEq(uint256(currentAnswer), 1, "Final answer should be APPROVE");

        // Wait for timeout
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        bytes32 result = realityETH.resultFor(questionId);
        assertEq(uint256(result), 1, "Result should be APPROVE");

        console.log("\nFinal result: APPROVE");
        console.log("Total bonds committed: ~", MIN_BOND * 7);

        // Finalize
        bytes32 leaf = keccak256(abi.encode(LEAF_TYPEHASH, chainId, extcodehash, metadataHash, uint64(1), false));
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(specProvider);
        registry.finalize(uid, leaf, proof);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.idx > 0, "Should be indexed after APPROVE win");

        console.log("\n=== Escalation Battle Complete ===\n");
    }

    // ========== WORKFLOW 5: MULTIPLE SPECS SAME CONTRACT ==========

    function test_Workflow_MultipleSpecsSameContract() public {
        console.log("\n=== Workflow: Multiple Specs Same Contract ===\n");

        bytes32 extcodehash = keccak256("shared-contract-bytecode");
        uint256 chainId = 1;

        // Submit first spec
        bytes32 blobHash1 = keccak256("spec-v1");
        bytes32 metadataHash1 = keccak256("spec-v1-metadata-content");
        uint256 nonce1 = block.timestamp;

        bytes32 commitment1 = keccak256(abi.encodePacked(blobHash1, nonce1));
        vm.prank(specProvider);
        bytes32 commitmentId1 = registry.commitSpec(commitment1, chainId, extcodehash);
        vm.prank(specProvider);
        bytes32 uid1 = registry.revealSpec{value: MIN_BOND}(commitmentId1, blobHash1, nonce1, metadataHash1);

        bytes32 questionId1 = registry.questionIds(uid1);
        vm.prank(voter1);
        realityETH.submitAnswer{value: MIN_BOND}(questionId1, bytes32(uint256(1)), 0);
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        bytes32 leaf1 = keccak256(abi.encode(LEAF_TYPEHASH, chainId, extcodehash, metadataHash1, uint64(1), false));
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(specProvider);
        registry.finalize(uid1, leaf1, proof);

        console.log("Spec 1 approved, UID:", vm.toString(uid1));

        // Submit second spec (improved version)
        bytes32 blobHash2 = keccak256("spec-v2-improved");
        bytes32 metadataHash2 = keccak256("spec-v2-metadata-content");
        uint256 nonce2 = block.timestamp + 1;

        bytes32 commitment2 = keccak256(abi.encodePacked(blobHash2, nonce2));
        vm.prank(specProvider);
        bytes32 commitmentId2 = registry.commitSpec(commitment2, chainId, extcodehash);
        vm.prank(specProvider);
        bytes32 uid2 = registry.revealSpec{value: MIN_BOND}(commitmentId2, blobHash2, nonce2, metadataHash2);

        bytes32 questionId2 = registry.questionIds(uid2);
        vm.prank(voter1);
        realityETH.submitAnswer{value: MIN_BOND}(questionId2, bytes32(uint256(1)), 0);
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        bytes32 leaf2 = keccak256(abi.encode(LEAF_TYPEHASH, chainId, extcodehash, metadataHash2, uint64(2), false));
        vm.prank(specProvider);
        registry.finalize(uid2, leaf2, proof);

        console.log("Spec 2 approved, UID:", vm.toString(uid2));

        // Verify both are indexed
        bytes32[] memory specs = registry.getSpecsForBytecode(chainId, extcodehash);
        assertEq(specs.length, 2, "Should have 2 specs");

        // Latest should be spec 2
        (bytes32 latestUid, bool valid) = registry.getLatestSpecForBytecode(chainId, extcodehash);
        assertEq(latestUid, uid2, "Latest should be spec 2");
        assertTrue(valid, "Should be valid");

        console.log("Total specs for contract:", specs.length);
        console.log("Latest spec:", vm.toString(latestUid));

        console.log("\n=== Multiple Specs Complete ===\n");
    }
}
