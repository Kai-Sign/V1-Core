// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";
import {PermissionedBToken} from "../../src/PermissionedBToken.sol";
import {RealityETH_ERC20_v3_2} from "../../src/external/RealityETH_ERC20_v3_2.sol";
import {RealityETH_ERC20_Factory} from "../../src/external/RealityETH_ERC20_Factory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockToken
 * @notice Simple ERC20 for testing (has decimals() and symbol() for factory)
 */
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 10_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title TestPermissionedBToken
 * @notice Wrapper that exposes burn for RM-7 test
 */
contract TestPermissionedBToken is PermissionedBToken {
    constructor(address _owner) PermissionedBToken(_owner) {}

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/**
 * @title AuditFixesTest
 * @notice Tests for all 9 audit fixes (RH-1, RH-2, RM-1, RM-2, RM-4, RM-6, RM-7, RL-1, RL-2, M-4)
 * @dev Uses mainnet fork with a fresh RealityETH_ERC20 instance for real integration testing
 */
contract AuditFixesTest is Test {
    // ========== CONSTANTS ==========
    address constant NO_ARBITRATOR = address(0);
    uint256 constant MIN_BOND = 100 ether;
    uint32 constant DEFAULT_TIMEOUT = 48 hours;

    // ========== STATE ==========
    KaiSignRegistry public registry;
    MockToken public token;
    IRealityETH public realityETH;

    address public owner;
    address public attester1;
    address public attester2;
    address public revoker;

    // ========== EVENTS (for expectEmit) ==========
    event MerkleRootUpdated(bytes32 indexed newRoot, uint64 atIdx);
    event LogNewQuestion(
        bytes32 indexed question_id,
        address indexed user,
        uint256 template_id,
        string question,
        bytes32 indexed content_hash,
        address arbitrator,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint256 created
    );

    // ========== SETUP ==========

    function setUp() public {
        // Fork mainnet (deploy fresh RealityETH_ERC20 via factory for real integration)
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        owner = makeAddr("owner");
        attester1 = makeAddr("attester1");
        attester2 = makeAddr("attester2");
        revoker = makeAddr("revoker");

        vm.deal(owner, 100 ether);
        vm.deal(attester1, 100 ether);
        vm.deal(attester2, 100 ether);
        vm.deal(revoker, 100 ether);

        // Deploy mock token
        vm.prank(owner);
        token = new MockToken();

        // Distribute tokens
        vm.startPrank(owner);
        token.transfer(attester1, 1_000_000 ether);
        token.transfer(attester2, 1_000_000 ether);
        token.transfer(revoker, 1_000_000 ether);
        vm.stopPrank();

        // Deploy a fresh RealityETH_ERC20 instance via factory
        vm.startPrank(owner);
        RealityETH_ERC20_v3_2 lib = new RealityETH_ERC20_v3_2();
        RealityETH_ERC20_Factory factory = new RealityETH_ERC20_Factory(address(lib));
        factory.createInstance(address(token));
        address realityAddr = factory.deployments(address(token));
        realityETH = IRealityETH(realityAddr);
        vm.stopPrank();

        // Deploy registry
        vm.startPrank(owner);
        registry = new KaiSignRegistry(
            20,              // treeDepth
            1,               // universeId
            address(0),      // parentRegistry
            owner,           // initialOwner
            NO_ARBITRATOR,   // arbitrator
            MIN_BOND         // minBond
        );
        registry.setBondToken(address(token), address(realityETH));
        vm.stopPrank();
    }

    // ========== HELPERS ==========

    function _commitAndReveal(
        address attester,
        bytes32 blobHash,
        bytes32 metadataHash,
        bytes32 extcodehash,
        uint256 chainId,
        uint256 nonce
    ) internal returns (bytes32 uid, bytes32 questionId) {
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);

        // Warp past MIN_REVEAL_DELAY
        vm.warp(block.timestamp + 2);

        uid = registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, MIN_BOND);
        vm.stopPrank();

        (questionId,) = registry.questions(uid);
    }

    function _answerAndFinalize(bytes32 questionId, bytes32 answer, address answerer) internal {
        // Submit answer via ERC20
        vm.startPrank(answerer);
        token.approve(address(realityETH), MIN_BOND);
        realityETH.submitAnswerERC20(questionId, answer, 0, MIN_BOND);
        vm.stopPrank();

        // Warp past timeout so question finalizes
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);
    }

    function _fullApproveAttestation(
        address attester,
        bytes32 blobHash,
        bytes32 metadataHash,
        bytes32 extcodehash,
        uint256 chainId,
        uint256 nonce
    ) internal returns (bytes32 uid) {
        bytes32 questionId;
        (uid, questionId) = _commitAndReveal(attester, blobHash, metadataHash, extcodehash, chainId, nonce);
        _answerAndFinalize(questionId, bytes32(uint256(1)), attester);
        registry.finalize(uid);
    }

    function _proposeRevokeWithAnswer(address _revoker, bytes32 uid) internal returns (bytes32 revokeQuestionId) {
        vm.startPrank(_revoker);
        token.approve(address(registry), MIN_BOND);
        registry.proposeRevoke(uid, MIN_BOND);
        vm.stopPrank();

        (revokeQuestionId,) = registry.revokeQuestions(uid);
    }

    function _latestRealityQuestion() internal returns (uint256 templateId, string memory questionText) {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 sig =
            keccak256("LogNewQuestion(bytes32,address,uint256,string,bytes32,address,uint32,uint32,uint256,uint256)");

        for (uint256 i = entries.length; i > 0; i--) {
            Vm.Log memory entry = entries[i - 1];
            if (entry.emitter != address(realityETH)) continue;
            if (entry.topics.length == 0 || entry.topics[0] != sig) continue;

            (uint256 emittedTemplateId, string memory question, address arbitrator, uint32 timeout, uint32 openingTs, uint256 nonce, uint256 created) =
                abi.decode(entry.data, (uint256, string, address, uint32, uint32, uint256, uint256));

            // Touch remaining decoded fields so the compiler does not warn about partial decode intent.
            arbitrator;
            timeout;
            openingTs;
            nonce;
            created;

            return (emittedTemplateId, question);
        }

        fail("Reality LogNewQuestion event not found");
        return (0, "");
    }

    // ================================================================
    //  RH-1: revokeAttempt counter for nonce uniqueness
    // ================================================================

    function test_RH1_RevokeAttemptIncrements() public {
        // Approve an attestation
        bytes32 uid = _fullApproveAttestation(
            attester1, keccak256("blob1"), keccak256("meta1"),
            keccak256("code1"), 1, 111
        );

        // revokeAttempt starts at 0
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertEq(att.revokeAttempt, 0, "revokeAttempt should start at 0");

        // First proposeRevoke → revokeAttempt becomes 1
        bytes32 rqId1 = _proposeRevokeWithAnswer(revoker, uid);
        att = registry.getAttestation(uid);
        assertEq(att.revokeAttempt, 1, "revokeAttempt should be 1 after first proposal");

        // Reject the revoke so we can propose again
        _answerAndFinalize(rqId1, bytes32(uint256(0)), revoker);
        registry.finalizeRevoke(uid);

        // After rejection, revokeAttempt stays incremented
        att = registry.getAttestation(uid);
        assertEq(att.revokeAttempt, 1, "revokeAttempt should stay 1 after rejection");

        // Second proposeRevoke → revokeAttempt becomes 2
        _proposeRevokeWithAnswer(revoker, uid);
        att = registry.getAttestation(uid);
        assertEq(att.revokeAttempt, 2, "revokeAttempt should be 2 after second proposal");
    }

    function test_SubmissionQuestionPayload_UsesBlobHashAsField1() public {
        bytes32 blobHash = keccak256("blob-submission-payload");
        bytes32 metadataHash = keccak256("meta-submission-payload");
        bytes32 extcodehash = keccak256("code-submission-payload");
        uint256 chainId = 1;
        uint256 nonce = 555;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.recordLogs();
        vm.startPrank(attester1);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
        vm.warp(block.timestamp + 2);
        registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, MIN_BOND);
        vm.stopPrank();

        (uint256 actualTemplateId, string memory actual) = _latestRealityQuestion();
        string memory delim = unicode"␟";
        string memory expected = string.concat(
            vm.toString(blobHash),
            delim,
            vm.toString(extcodehash),
            delim,
            vm.toString(chainId)
        );

        assertEq(actualTemplateId, registry.templateId(), "submission should use submission template");
        assertEq(actual, expected, "submission payload should be blobHash<delim>extcodehash<delim>chainId");
    }

    function test_RevokeQuestionPayload_UsesUidAsField1() public {
        bytes32 extcodehash = keccak256("code-revoke-payload");
        bytes32 uid = _fullApproveAttestation(
            attester1,
            keccak256("blob-revoke-payload"),
            keccak256("meta-revoke-payload"),
            extcodehash,
            1,
            777
        );

        vm.recordLogs();
        vm.startPrank(revoker);
        token.approve(address(registry), MIN_BOND);
        registry.proposeRevoke(uid, MIN_BOND);
        vm.stopPrank();

        (uint256 actualTemplateId, string memory actual) = _latestRealityQuestion();
        string memory delim = unicode"␟";
        string memory expected = string.concat(
            vm.toString(uid),
            delim,
            vm.toString(extcodehash),
            delim,
            vm.toString(uint256(1))
        );

        assertEq(actualTemplateId, registry.revokeTemplateId(), "revoke should use revoke template");
        assertEq(actual, expected, "raw revoke question payload should match builder output");
    }

    function test_SubmissionAndRevokePayloads_UseSameDelimitedShapeButDifferentTemplates() public {
        bytes32 blobHash = keccak256("blob-shape-compare");
        bytes32 metadataHash = keccak256("meta-shape-compare");
        bytes32 extcodehash = keccak256("code-shape-compare");
        uint256 chainId = 1;
        uint256 nonce = 888;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.recordLogs();
        vm.startPrank(attester1);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
        vm.warp(block.timestamp + 2);
        bytes32 uid = registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, MIN_BOND);
        vm.stopPrank();

        (uint256 submissionTemplateId, string memory submissionPayload) = _latestRealityQuestion();

        bytes32 questionId;
        (questionId,) = registry.questions(uid);
        _answerAndFinalize(questionId, bytes32(uint256(1)), attester1);
        registry.finalize(uid);

        vm.recordLogs();
        vm.startPrank(revoker);
        token.approve(address(registry), MIN_BOND);
        registry.proposeRevoke(uid, MIN_BOND);
        vm.stopPrank();

        (uint256 revokeTemplateId, string memory revokePayload) = _latestRealityQuestion();
        string memory delim = unicode"␟";
        string memory expectedSubmission = string.concat(
            vm.toString(blobHash),
            delim,
            vm.toString(extcodehash),
            delim,
            vm.toString(chainId)
        );
        string memory expectedRevoke = string.concat(
            vm.toString(uid),
            delim,
            vm.toString(extcodehash),
            delim,
            vm.toString(chainId)
        );

        assertEq(submissionTemplateId, registry.templateId(), "submission should use submission template");
        assertEq(revokeTemplateId, registry.revokeTemplateId(), "revoke should use revoke template");
        assertEq(submissionPayload, expectedSubmission, "submission payload should match expected 3-field format");
        assertEq(revokePayload, expectedRevoke, "revoke payload should match expected 3-field format");
        assertTrue(bytes(submissionPayload).length > 0, "submission payload should not be empty");
        assertTrue(bytes(revokePayload).length > 0, "revoke payload should not be empty");
        assertTrue(
            keccak256(bytes(submissionPayload)) != keccak256(bytes(revokePayload)),
            "submission and revoke payloads should differ"
        );
    }

    // ================================================================
    //  RM-2: uid used as nonce in revealSpec (no collision)
    // ================================================================

    function test_RM2_RevealSpecUsesUidAsNonce() public {
        bytes32 blobHash = keccak256("same-blob");
        bytes32 metadataHash = keccak256("same-meta");
        bytes32 extcodehash = keccak256("same-code");
        uint256 chainId = 1;
        uint256 nonce = 42;

        // Two different attesters submit identical specs
        (bytes32 uid1,) = _commitAndReveal(attester1, blobHash, metadataHash, extcodehash, chainId, nonce);
        (bytes32 uid2,) = _commitAndReveal(attester2, blobHash, metadataHash, extcodehash, chainId, nonce);

        // Both succeed with different UIDs
        assertTrue(uid1 != bytes32(0), "uid1 should not be zero");
        assertTrue(uid2 != bytes32(0), "uid2 should not be zero");
        assertTrue(uid1 != uid2, "UIDs should differ for different attesters");
    }

    // ================================================================
    //  RH-2: migratedIdx bounds importMigratedAttestation
    // ================================================================

    function test_RH2_MigrateSetsMigratedIdx() public {
        // Build a frontier (20 zeros for treeDepth=20)
        bytes32[] memory frontier = new bytes32[](20);
        uint64 migrateCount = 5;

        vm.prank(owner);
        registry.migrate(frontier, migrateCount);

        assertEq(registry.migratedIdx(), migrateCount, "migratedIdx should equal migrated count");
        assertEq(registry.currentIdx(), migrateCount, "currentIdx should equal migrated count");
        assertEq(registry.merkleRootIdx(), migrateCount, "merkleRootIdx should equal migrated count");
    }

    function test_RH2_ImportBoundedByMigratedIdx() public {
        // Migrate with idx=2
        bytes32[] memory frontier = new bytes32[](20);
        vm.prank(owner);
        registry.migrate(frontier, 2);

        // Approve a new attestation (this grows currentIdx to 3, but migratedIdx stays 2)
        _fullApproveAttestation(
            attester1, keccak256("blob-new"), keccak256("meta-new"),
            keccak256("code-new"), 1, 999
        );
        assertTrue(registry.currentIdx() > registry.migratedIdx(), "currentIdx should exceed migratedIdx");

        // Try importing with idx=3 (beyond migratedIdx=2) → should revert
        bytes32[] memory proof = new bytes32[](20);
        vm.expectRevert(abi.encodeWithSignature("IdxBeyondMigrated()"));
        registry.importMigratedAttestation(1, keccak256("x"), keccak256("y"), 3, proof);
    }

    // ================================================================
    //  RM-1: configNonce invalidates pending commits
    // ================================================================

    function test_RM1_SetMinBondIncrementsConfigNonce() public {
        uint32 nonceBefore = registry.configNonce();

        vm.prank(owner);
        registry.setMinBond(50 ether);

        assertEq(registry.configNonce(), nonceBefore + 1, "configNonce should increment on setMinBond");
    }

    function test_RM1_CommitInvalidatedBySetMinBond() public {
        bytes32 blobHash = keccak256("blob-rm1");
        bytes32 metadataHash = keccak256("meta-rm1");
        uint256 nonce = 777;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        // Commit
        vm.prank(attester1);
        bytes32 commitmentId = registry.commitSpec(commitment, 1, keccak256("code-rm1"));

        // Owner changes minBond → configNonce increments
        vm.prank(owner);
        registry.setMinBond(50 ether);

        // Warp past reveal delay
        vm.warp(block.timestamp + 2);

        // Reveal should revert with ConfigChanged
        vm.startPrank(attester1);
        token.approve(address(registry), 50 ether);
        vm.expectRevert(abi.encodeWithSignature("ConfigChanged()"));
        registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, 50 ether);
        vm.stopPrank();
    }

    // ================================================================
    //  RM-4: finalize and finalizeRevoke work while paused
    // ================================================================

    function test_RM4_FinalizeWorksWhilePaused() public {
        // Create and answer a question
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            attester1, keccak256("blob-rm4"), keccak256("meta-rm4"),
            keccak256("code-rm4"), 1, 444
        );
        _answerAndFinalize(questionId, bytes32(uint256(1)), attester1);

        // Pause the contract
        vm.prank(owner);
        registry.pause();
        assertTrue(registry.paused(), "Should be paused");

        // finalize() should still work (no whenNotPaused modifier)
        registry.finalize(uid);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.finalizedAt != 0, "Should be finalized while paused");
    }

    function test_RM4_FinalizeRevokeWorksWhilePaused() public {
        // Full approve
        bytes32 uid = _fullApproveAttestation(
            attester1, keccak256("blob-rm4b"), keccak256("meta-rm4b"),
            keccak256("code-rm4b"), 1, 445
        );

        // Propose and answer revoke
        bytes32 rqId = _proposeRevokeWithAnswer(revoker, uid);
        _answerAndFinalize(rqId, bytes32(uint256(1)), revoker);

        // Pause the contract
        vm.prank(owner);
        registry.pause();
        assertTrue(registry.paused(), "Should be paused");

        // finalizeRevoke() should still work
        registry.finalizeRevoke(uid);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.revoked, "Should be revoked while paused");
    }

    // ================================================================
    //  M-4: Ownable2Step (two-step ownership transfer)
    // ================================================================

    function test_M4_TransferOwnershipRequiresAcceptance() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        registry.transferOwnership(newOwner);

        // Owner hasn't changed yet
        assertEq(registry.owner(), owner, "Owner should not change until accepted");
        assertEq(registry.pendingOwner(), newOwner, "pendingOwner should be set");
    }

    function test_M4_OnlyPendingOwnerCanAccept() public {
        address newOwner = makeAddr("newOwner");
        address randomAddr = makeAddr("random");

        vm.prank(owner);
        registry.transferOwnership(newOwner);

        // Random address cannot accept
        vm.prank(randomAddr);
        vm.expectRevert();
        registry.acceptOwnership();

        // Pending owner can accept
        vm.prank(newOwner);
        registry.acceptOwnership();
        assertEq(registry.owner(), newOwner, "newOwner should now be owner");
    }

    // ================================================================
    //  RL-2: MerkleRootUpdated event emission
    // ================================================================

    function test_RL2_FinalizeEmitsMerkleRootUpdated() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            attester1, keccak256("blob-rl2"), keccak256("meta-rl2"),
            keccak256("code-rl2"), 1, 222
        );
        _answerAndFinalize(questionId, bytes32(uint256(1)), attester1);

        vm.expectEmit(false, false, false, true);
        emit MerkleRootUpdated(bytes32(0), 1); // root value will differ, check atIdx
        registry.finalize(uid);
    }

    function test_RL2_FinalizeRevokeEmitsMerkleRootUpdated() public {
        bytes32 uid = _fullApproveAttestation(
            attester1, keccak256("blob-rl2b"), keccak256("meta-rl2b"),
            keccak256("code-rl2b"), 1, 223
        );

        bytes32 rqId = _proposeRevokeWithAnswer(revoker, uid);
        _answerAndFinalize(rqId, bytes32(uint256(1)), revoker);

        vm.expectEmit(false, false, false, true);
        emit MerkleRootUpdated(bytes32(0), 2); // idx=2 (first was approve at 1)
        registry.finalizeRevoke(uid);
    }

    function test_RL2_MigrateEmitsMerkleRootUpdated() public {
        bytes32[] memory frontier = new bytes32[](20);

        vm.expectEmit(false, false, false, false);
        emit MerkleRootUpdated(bytes32(0), 0);

        vm.prank(owner);
        registry.migrate(frontier, 3);
    }

    // ================================================================
    //  RM-7: PermissionedBToken burn works (address(0) not whitelisted)
    // ================================================================

    function test_RM7_BurnSucceeds() public {
        vm.startPrank(owner);
        TestPermissionedBToken bToken = new TestPermissionedBToken(owner);
        bToken.mint(attester1, 1000 ether);
        vm.stopPrank();

        uint256 balBefore = bToken.balanceOf(attester1);

        // Burn should not revert despite address(0) not being whitelisted
        bToken.burn(attester1, 500 ether);

        assertEq(bToken.balanceOf(attester1), balBefore - 500 ether, "Balance should decrease after burn");
    }

    // ================================================================
    //  RM-6: Registry must be whitelisted in PermissionedBToken for reveal
    // ================================================================

    function test_RM6_RegistryWhitelistRequiredForReveal() public {
        // Deploy PermissionedBToken + fresh RealityETH_ERC20 + fresh registry
        vm.startPrank(owner);
        TestPermissionedBToken bToken = new TestPermissionedBToken(owner);

        RealityETH_ERC20_v3_2 lib2 = new RealityETH_ERC20_v3_2();
        RealityETH_ERC20_Factory factory2 = new RealityETH_ERC20_Factory(address(lib2));
        factory2.createInstance(address(bToken));
        address realityAddr2 = factory2.deployments(address(bToken));

        KaiSignRegistry reg2 = new KaiSignRegistry(
            20, 1, address(0), owner, NO_ARBITRATOR, MIN_BOND
        );
        reg2.setBondToken(address(bToken), realityAddr2);

        // Mint tokens to attester and whitelist Reality.eth so attester can send to it
        bToken.mint(attester1, 10_000 ether);
        bToken.whitelist(realityAddr2);
        // NOTE: registry is NOT whitelisted yet
        vm.stopPrank();

        // Commit (doesn't need token transfer)
        bytes32 blobHash = keccak256("blob-rm6");
        uint256 nonce = 666;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.prank(attester1);
        bytes32 commitmentId = reg2.commitSpec(commitment, 1, keccak256("code-rm6"));

        vm.warp(block.timestamp + 2);

        // Reveal should fail — registry not whitelisted, so transferFrom to registry reverts
        vm.startPrank(attester1);
        bToken.approve(address(reg2), MIN_BOND);
        vm.expectRevert("PermissionedBToken: transfer not allowed");
        reg2.revealSpec(commitmentId, blobHash, nonce, keccak256("meta-rm6"), MIN_BOND);
        vm.stopPrank();

        // Now whitelist the registry
        vm.prank(owner);
        bToken.whitelist(address(reg2));

        // Reveal should now succeed
        vm.startPrank(attester1);
        bToken.approve(address(reg2), MIN_BOND);
        bytes32 uid = reg2.revealSpec(commitmentId, blobHash, nonce, keccak256("meta-rm6"), MIN_BOND);
        vm.stopPrank();

        assertTrue(uid != bytes32(0), "Reveal should succeed after whitelisting registry");
    }

    // ================================================================
    //  RL-1: finalize/finalizeRevoke revert on invalid & unresolved results
    // ================================================================

    function test_RL1_FinalizeRevertsOnInvalid() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            attester1, keccak256("blob-rl1a"), keccak256("meta-rl1a"),
            keccak256("code-rl1a"), 1, 301
        );

        // Answer with INVALID (0xFF...FF)
        _answerAndFinalize(questionId, bytes32(type(uint256).max), attester1);

        vm.expectRevert(abi.encodeWithSignature("InvalidQuestionResult()"));
        registry.finalize(uid);
    }

    function test_RL1_FinalizeRevertsOnUnresolved() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            attester1, keccak256("blob-rl1b"), keccak256("meta-rl1b"),
            keccak256("code-rl1b"), 1, 302
        );

        // Answer with UNRESOLVED (0xFF...FE)
        _answerAndFinalize(questionId, bytes32(type(uint256).max - 1), attester1);

        vm.expectRevert(abi.encodeWithSignature("UnresolvedQuestionResult()"));
        registry.finalize(uid);
    }

    function test_RL1_FinalizeRevokeResetsOnInvalid() public {
        bytes32 uid = _fullApproveAttestation(
            attester1, keccak256("blob-rl1c"), keccak256("meta-rl1c"),
            keccak256("code-rl1c"), 1, 303
        );

        bytes32 rqId = _proposeRevokeWithAnswer(revoker, uid);
        _answerAndFinalize(rqId, bytes32(type(uint256).max), revoker);

        registry.finalizeRevoke(uid);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertEq(att.revokeProposedAt, 0, "revokeProposedAt should be reset");
        assertEq(att.revokeProposer, address(0), "revokeProposer should be reset");
        assertFalse(att.revoked, "Should not be revoked");
    }

    function test_RL1_FinalizeRevokeResetsOnUnresolved() public {
        bytes32 uid = _fullApproveAttestation(
            attester1, keccak256("blob-rl1d"), keccak256("meta-rl1d"),
            keccak256("code-rl1d"), 1, 304
        );

        bytes32 rqId = _proposeRevokeWithAnswer(revoker, uid);
        _answerAndFinalize(rqId, bytes32(type(uint256).max - 1), revoker);

        registry.finalizeRevoke(uid);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertEq(att.revokeProposedAt, 0, "revokeProposedAt should be reset");
        assertEq(att.revokeProposer, address(0), "revokeProposer should be reset");
        assertFalse(att.revoked, "Should not be revoked");
    }

    function test_RL1_FinalizeApprovalWorks() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            attester1, keccak256("blob-rl1e"), keccak256("meta-rl1e"),
            keccak256("code-rl1e"), 1, 305
        );

        _answerAndFinalize(questionId, bytes32(uint256(1)), attester1);
        registry.finalize(uid);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.finalizedAt != 0, "Should be finalized");
        assertFalse(att.revoked, "Should not be revoked (approved)");
        assertTrue(att.idx > 0, "Should have an index (approved)");
    }

    function test_RL1_FinalizeRejectionWorks() public {
        (bytes32 uid, bytes32 questionId) = _commitAndReveal(
            attester1, keccak256("blob-rl1f"), keccak256("meta-rl1f"),
            keccak256("code-rl1f"), 1, 306
        );

        _answerAndFinalize(questionId, bytes32(uint256(0)), attester1);
        registry.finalize(uid);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.finalizedAt != 0, "Should be finalized");
        assertTrue(att.revoked, "Should be revoked (rejected)");
        assertEq(att.idx, 0, "Should have no index (rejected)");
    }

    // ================================================================
    //  Hardening: Zero hashes precomputed in constructor
    // ================================================================

    function test_ZeroHashesPrecomputed() public view {
        // Manually compute the zero hash chain and verify against storage
        bytes32 z = bytes32(0);
        for (uint256 i = 0; i < 20; i++) {
            assertEq(
                registry.zeroHashes(i),
                z,
                string(abi.encodePacked("zeroHashes[", _uintToStr(i), "] mismatch"))
            );
            z = keccak256(abi.encodePacked(z, z));
        }
    }

    function _uintToStr(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 digits;
        uint256 tmp = v;
        while (tmp != 0) { digits++; tmp /= 10; }
        bytes memory buf = new bytes(digits);
        while (v != 0) { digits--; buf[digits] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }

    // ================================================================
    //  Hardening: abi.encode commit-reveal roundtrip
    // ================================================================

    function test_AbiEncodeCommitRevealRoundtrip() public {
        // Full commit→reveal→finalize roundtrip after abi.encode change
        bytes32 uid = _fullApproveAttestation(
            attester1, keccak256("blob-abi"), keccak256("meta-abi"),
            keccak256("code-abi"), 1, 501
        );

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.finalizedAt != 0, "Should be finalized");
        assertFalse(att.revoked, "Should be approved");
        assertTrue(att.idx > 0, "Should have merkle index");
    }

    // ================================================================
    //  Hardening: revokeQuestions cleared on rejection
    // ================================================================

    function test_RevokeRejectionClearsQuestion() public {
        // Approve an attestation
        bytes32 uid = _fullApproveAttestation(
            attester1, keccak256("blob-rqclr"), keccak256("meta-rqclr"),
            keccak256("code-rqclr"), 1, 601
        );

        // Propose revoke
        bytes32 rqId = _proposeRevokeWithAnswer(revoker, uid);

        // Verify revokeQuestions[uid] is set
        (bytes32 questionId,) = registry.revokeQuestions(uid);
        assertTrue(questionId != bytes32(0), "revokeQuestion should be set after proposal");

        // Reject the revoke
        _answerAndFinalize(rqId, bytes32(uint256(0)), revoker);
        registry.finalizeRevoke(uid);

        // Verify revokeQuestions[uid] is now cleared
        (bytes32 questionIdAfter, IRealityETH instanceAfter) = registry.revokeQuestions(uid);
        assertEq(questionIdAfter, bytes32(0), "revokeQuestion questionId should be zeroed after rejection");
        assertEq(address(instanceAfter), address(0), "revokeQuestion instance should be zeroed after rejection");

        // Verify attestation is NOT revoked (rejection means spec stays valid)
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertFalse(att.revoked, "Should not be revoked after rejection");
        assertEq(att.revokeProposedAt, 0, "revokeProposedAt should be reset");
    }
}
