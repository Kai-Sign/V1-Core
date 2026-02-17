// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";

/**
 * @title RealityEthForkTest
 * @notice Fork test for KaiSignRegistry + Reality.eth v3.0 integration
 * @dev Run with: forge test --match-contract RealityEthForkTest --fork-url $MAINNET_RPC_URL -vvv
 *
 * Reality.eth v3.0 Addresses:
 * - Mainnet: 0x5b7dD1E86623548AF054A4985F7fc8Ccbb554E2c
 * - Sepolia: 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA
 */
contract RealityEthForkTest is Test {
    // ========== CONSTANTS ==========

    // Reality.eth v3.0 mainnet
    address constant REALITY_ETH_MAINNET = 0x5b7dD1E86623548AF054A4985F7fc8Ccbb554E2c;

    // Reality.eth v3.0 sepolia (for testing without mainnet RPC)
    address constant REALITY_ETH_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;

    // No arbitrator for faster testing (questions finalize after timeout without arbitration)
    address constant NO_ARBITRATOR = address(0);

    // Use this for testing (set to mainnet or sepolia based on your RPC)
    // For mainnet fork: REALITY_ETH_MAINNET
    // For sepolia fork: REALITY_ETH_SEPOLIA
    address constant REALITY_ETH = REALITY_ETH_SEPOLIA;

    uint256 constant MIN_BOND = 0.01 ether;
    uint32 constant DEFAULT_TIMEOUT = 48 hours;
    bytes32 constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,uint256 idx,bool revoked)");

    // ========== STATE ==========

    KaiSignRegistry public registry;
    IRealityETH public realityETH;

    address public deployer;
    address public proposer;
    address public challenger;
    address public voter;

    // Test data
    bytes32 public testBlobHash;
    bytes32 public testMetadataHash;
    bytes32 public testExtcodehash;
    uint256 public testChainId;

    // ========== SETUP ==========

    function setUp() public {
        // Fork Sepolia (or mainnet if MAINNET_RPC_URL is set)
        // Try SEPOLIA_RPC_URL first, fallback to MAINNET_RPC_URL
        string memory rpcUrl = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            rpcUrl = vm.envString("MAINNET_RPC_URL");
        }
        vm.createSelectFork(rpcUrl);

        // Create test addresses
        deployer = makeAddr("deployer");
        proposer = makeAddr("proposer");
        challenger = makeAddr("challenger");
        voter = makeAddr("voter");

        // Fund test accounts
        vm.deal(deployer, 100 ether);
        vm.deal(proposer, 100 ether);
        vm.deal(challenger, 100 ether);
        vm.deal(voter, 100 ether);

        // Set up test data
        testBlobHash = keccak256("test-blob-hash");
        testMetadataHash = keccak256("test-metadata-content");
        testExtcodehash = keccak256("test-extcodehash");
        testChainId = 1; // Mainnet

        // Deploy KaiSignRegistry connected to real Reality.eth
        vm.startPrank(deployer);
        registry = new KaiSignRegistry(
            1,                    // universeId
            address(0),           // parentRegistry (none)
            deployer,             // initialOwner
            REALITY_ETH,          // Reality.eth v3.0
            NO_ARBITRATOR,        // no arbitrator - faster finalization
            MIN_BOND              // minBond
        );
        vm.stopPrank();

        // Get Reality.eth interface
        realityETH = IRealityETH(REALITY_ETH);

        // Log setup info
        console.log("=== Fork Test Setup ===");
        console.log("Reality.eth:", REALITY_ETH);
        console.log("Registry:", address(registry));
        console.log("Template ID:", registry.templateId());
        console.log("Min Bond:", MIN_BOND);
    }

    // ========== HELPER FUNCTIONS ==========

    function _commitAndReveal(
        address _proposer,
        bytes32 _blobHash,
        bytes32 _metadataHash,
        bytes32 _extcodehash,
        uint256 _chainId,
        uint256 _bond
    ) internal returns (bytes32 uid, bytes32 questionId) {
        // Use a fixed nonce
        uint256 nonce = 12345;

        // Debug: log input values
        console.log("=== Commit-Reveal Debug ===");
        console.log("blobHash:", vm.toString(_blobHash));
        console.log("nonce:", nonce);

        // Commit
        vm.startPrank(_proposer);
        bytes32 commitment = keccak256(abi.encodePacked(_blobHash, nonce));
        console.log("commitment hash:", vm.toString(commitment));
        console.log("block.timestamp at commit:", block.timestamp);

        bytes32 commitmentId = registry.commitSpec(commitment, _chainId, _extcodehash);
        console.log("commitmentId:", vm.toString(commitmentId));

        // Get stored commitment data
        (address committer, uint64 commitTimestamp, uint256 chainId, bytes32 extcodehash, bool isRevealed) = registry.commitments(commitmentId);
        console.log("stored committer:", committer);
        console.log("stored commitTimestamp:", commitTimestamp);
        console.log("stored chainId:", chainId);
        console.log("stored extcodehash:", vm.toString(extcodehash));

        // Compute what reveal will compute
        bytes32 expectedCommitment = keccak256(abi.encodePacked(_blobHash, nonce));
        console.log("expectedCommitment:", vm.toString(expectedCommitment));

        bytes32 reconstructedId = keccak256(abi.encodePacked(
            expectedCommitment,
            committer,
            chainId,
            extcodehash,
            uint256(commitTimestamp)
        ));
        console.log("reconstructedId:", vm.toString(reconstructedId));
        console.log("match:", reconstructedId == commitmentId);

        // Reveal with bond (same nonce)
        uid = registry.revealSpec{value: _bond}(commitmentId, _blobHash, nonce, _metadataHash);
        vm.stopPrank();

        // Get questionId
        questionId = registry.questionIds(uid);

        console.log("Created attestation UID:", vm.toString(uid));
        console.log("Reality.eth Question ID:", vm.toString(questionId));
    }

    function _submitAnswer(bytes32 questionId, bool answer, uint256 bond) internal {
        bytes32 answerBytes = answer ? bytes32(uint256(1)) : bytes32(uint256(0));

        vm.prank(voter);
        realityETH.submitAnswer{value: bond}(questionId, answerBytes, 0);

        console.log("Submitted answer:", answer ? "APPROVE (1)" : "REJECT (0)");
        console.log("Bond:", bond);
    }

    // ========== TEST: Template Creation ==========

    function test_TemplateCreation() public view {
        uint256 templateId = registry.templateId();

        console.log("Template ID:", templateId);
        assertTrue(templateId > 0, "Template should be created");
    }

    // ========== TEST: Commit-Reveal Flow ==========

    function test_CommitRevealFlow() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        // Commit
        vm.prank(proposer);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        assertTrue(commitmentId != bytes32(0), "Commitment ID should not be zero");

        // Check commitment data
        (
            address committer,
            uint64 commitTimestamp,
            uint256 chainId,
            bytes32 extcodehash,
            bool isRevealed
        ) = registry.commitments(commitmentId);

        assertEq(committer, proposer, "Committer should match");
        assertEq(chainId, testChainId, "Chain ID should match");
        assertEq(extcodehash, testExtcodehash, "Extcodehash should match");
        assertFalse(isRevealed, "Should not be revealed yet");

        console.log("Commitment created:", vm.toString(commitmentId));
    }

    // ========== TEST: Question Creation on Reality.eth ==========

    function test_QuestionCreation() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            proposer,
            testBlobHash,
            testMetadataHash,
            testExtcodehash,
            testChainId,
            MIN_BOND
        );

        // Verify question exists on Reality.eth
        assertTrue(questionId != bytes32(0), "Question ID should not be zero");

        // Check Reality.eth state
        uint256 bond = realityETH.getBond(questionId);
        console.log("Reality.eth bond:", bond);

        // The initial proposer's answer should be stored
        // Note: askQuestionWithMinBond doesn't submit an answer, just creates question
        // So bond should be 0 initially (no answers yet)
    }

    // ========== TEST: Answer Submission & Escalation ==========

    function test_AnswerSubmission() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            proposer,
            testBlobHash,
            testMetadataHash,
            testExtcodehash,
            testChainId,
            MIN_BOND
        );

        // Submit first answer: APPROVE (1)
        _submitAnswer(questionId, true, MIN_BOND);

        bytes32 bestAnswer = realityETH.getBestAnswer(questionId);
        assertEq(uint256(bestAnswer), 1, "Best answer should be APPROVE (1)");

        // Submit counter-answer: REJECT (0) with higher bond
        vm.prank(challenger);
        realityETH.submitAnswer{value: MIN_BOND * 2}(
            questionId,
            bytes32(uint256(0)),  // REJECT
            MIN_BOND              // max_previous
        );

        bestAnswer = realityETH.getBestAnswer(questionId);
        assertEq(uint256(bestAnswer), 0, "Best answer should now be REJECT (0)");

        // Submit final answer: APPROVE (1) with even higher bond
        vm.prank(voter);
        realityETH.submitAnswer{value: MIN_BOND * 4}(
            questionId,
            bytes32(uint256(1)),  // APPROVE
            MIN_BOND * 2          // max_previous
        );

        bestAnswer = realityETH.getBestAnswer(questionId);
        assertEq(uint256(bestAnswer), 1, "Best answer should be APPROVE (1) again");

        console.log("Escalation complete. Final answer: APPROVE");
    }

    // ========== TEST: Finalize Approved ==========

    function test_FinalizeApproved() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            proposer,
            testBlobHash,
            testMetadataHash,
            testExtcodehash,
            testChainId,
            MIN_BOND
        );

        // Submit APPROVE answer
        _submitAnswer(questionId, true, MIN_BOND);

        // Check not finalized yet
        assertFalse(realityETH.isFinalized(questionId), "Should not be finalized yet");

        // Warp time past timeout (48 hours + 1 second)
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        // Now should be finalized
        assertTrue(realityETH.isFinalized(questionId), "Should be finalized after timeout");

        // Get result
        bytes32 result = realityETH.resultFor(questionId);
        assertEq(uint256(result), 1, "Result should be APPROVE (1)");

        // Finalize on registry (need merkle proof - use empty for first attestation)
        bytes32 leaf = keccak256(abi.encode(
            LEAF_TYPEHASH,
            testChainId,
            testExtcodehash,
            testMetadataHash,
            uint64(1),  // idx
            false       // not revoked
        ));

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(proposer);
        registry.finalize(uid, leaf, proof);  // For first attestation, leaf == root

        // Verify attestation is finalized and indexed
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.finalizedAt > 0, "Should be finalized");
        assertFalse(att.revoked, "Should not be revoked");
        assertEq(att.idx, 1, "Should have idx 1");

        console.log("Attestation finalized and indexed!");
        console.log("idx:", att.idx);
        console.log("finalizedAt:", att.finalizedAt);
    }

    // ========== TEST: Finalize Rejected ==========

    function test_FinalizeRejected() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            proposer,
            testBlobHash,
            testMetadataHash,
            testExtcodehash,
            testChainId,
            MIN_BOND
        );

        // Submit REJECT answer
        _submitAnswer(questionId, false, MIN_BOND);

        // Warp time past timeout
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        // Get result
        bytes32 result = realityETH.resultFor(questionId);
        assertEq(uint256(result), 0, "Result should be REJECT (0)");

        // Finalize on registry
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(proposer);
        registry.finalize(uid, bytes32(0), proof);

        // Verify attestation is finalized but NOT indexed
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.finalizedAt > 0, "Should be finalized");
        assertTrue(att.revoked, "Should be revoked (rejected)");
        assertEq(att.idx, 0, "Should have idx 0 (not indexed)");

        // Verify not in index
        bytes32[] memory specs = registry.getSpecsForBytecode(testChainId, testExtcodehash);
        assertEq(specs.length, 0, "Should not be indexed");

        console.log("Attestation rejected - not indexed!");
    }

    // ========== TEST: Full Flow with Incentive Pool ==========

    function test_FullFlowWithIncentives() public {
        // This test demonstrates the full flow but without actual IncentivePool
        // (would need to deploy IncentivePool and set it up)

        console.log("\n=== Full Flow Test ===\n");

        // 1. Commit
        console.log("1. Committing spec...");
        uint256 nonce = 54321;  // Fixed nonce
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.prank(proposer);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        console.log("   Commitment ID:", vm.toString(commitmentId));

        // 2. Reveal with bond
        console.log("2. Revealing spec with", MIN_BOND, "ETH bond...");
        vm.prank(proposer);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        bytes32 questionId = registry.questionIds(uid);
        console.log("   UID:", vm.toString(uid));
        console.log("   Question ID:", vm.toString(questionId));

        // 3. Submit answer
        console.log("3. Submitting APPROVE answer...");
        _submitAnswer(questionId, true, MIN_BOND);

        // 4. Wait for timeout
        console.log("4. Warping time by 48 hours...");
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        // 5. Finalize
        console.log("5. Finalizing...");
        bytes32 leaf = keccak256(abi.encode(
            LEAF_TYPEHASH,
            testChainId,
            testExtcodehash,
            testMetadataHash,
            uint64(1),
            false
        ));
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(proposer);
        registry.finalize(uid, leaf, proof);

        // 6. Verify
        console.log("6. Verifying...");
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        console.log("   Finalized:", att.finalizedAt > 0);
        console.log("   Indexed:", att.idx > 0);
        console.log("   Revoked:", att.revoked);

        assertTrue(att.finalizedAt > 0 && att.idx > 0 && !att.revoked, "Full flow should succeed");
        console.log("\n=== Full Flow Complete! ===\n");
    }

    // ========== TEST: Revocation Flow ==========

    function test_RevocationFlow() public {
        // First, create and approve an attestation
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            proposer,
            testBlobHash,
            testMetadataHash,
            testExtcodehash,
            testChainId,
            MIN_BOND
        );

        // Approve it
        _submitAnswer(questionId, true, MIN_BOND);
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        bytes32 leaf = keccak256(abi.encode(
            LEAF_TYPEHASH,
            testChainId,
            testExtcodehash,
            testMetadataHash,
            uint64(1),
            false
        ));
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(proposer);
        registry.finalize(uid, leaf, proof);

        // Now propose revocation
        console.log("\n=== Revocation Flow ===\n");

        vm.prank(challenger);
        registry.proposeRevoke{value: MIN_BOND}(uid);

        bytes32 revokeQuestionId = registry.revokeQuestionIds(uid);
        console.log("Revoke Question ID:", vm.toString(revokeQuestionId));

        // Submit REVOKE answer (true = revoke)
        vm.prank(voter);
        realityETH.submitAnswer{value: MIN_BOND}(
            revokeQuestionId,
            bytes32(uint256(1)),  // REVOKE
            0
        );

        // Wait for timeout
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        // Finalize revoke
        vm.prank(challenger);
        registry.finalizeRevoke(uid);

        // Verify revoked
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.revoked, "Should be revoked");

        console.log("Attestation revoked successfully!");
    }
}
