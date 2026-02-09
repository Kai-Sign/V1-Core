// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";

/**
 * @title SecurityTests
 * @notice Security-focused tests for KaiSignRegistry
 * @dev Adapted from V1 AuditTests.t.sol for V2 with Reality.eth integration
 */
contract SecurityTests is Test {
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
    address public attester;
    address public attacker;

    // Test data
    bytes32 public testBlobHash;
    bytes32 public testMetadataHash;
    bytes32 public testExtcodehash;
    uint256 public testChainId;

    // ========== SETUP ==========

    function setUp() public {
        string memory rpcUrl = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpcUrl);

        owner = makeAddr("owner");
        attester = makeAddr("attester");
        attacker = makeAddr("attacker");

        vm.deal(owner, 100 ether);
        vm.deal(attester, 100 ether);
        vm.deal(attacker, 100 ether);

        testBlobHash = keccak256("test-blob");
        testMetadataHash = keccak256("test-metadata-content");
        testExtcodehash = keccak256("test-bytecode");
        testChainId = 1;

        vm.startPrank(owner);
        address[] memory attesters = new address[](1);
        attesters[0] = attester;

        registry = new KaiSignRegistry(
            1, address(0), owner, attesters,
            REALITY_ETH_SEPOLIA, NO_ARBITRATOR, MIN_BOND
        );
        vm.stopPrank();

        realityETH = IRealityETH(REALITY_ETH_SEPOLIA);
    }

    // ========== ACCESS CONTROL TESTS ==========

    function test_AccessControl_OnlyOwner_SetMinBond() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.setMinBond(1 ether);
    }

    function test_AccessControl_OnlyOwner_AddAttester() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.addAttester(attacker);
    }

    function test_AccessControl_OnlyOwner_RemoveAttester() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.removeAttester(attester);
    }

    function test_AccessControl_OnlyOwner_Pause() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.pause();
    }

    function test_AccessControl_OnlyOwner_Unpause() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(attacker);
        vm.expectRevert();
        registry.unpause();
    }

    function test_AccessControl_OnlyOwner_SetBondToken() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.setBondToken(address(1), address(2));
    }

    function test_AccessControl_OnlyOwner_SetIncentivePool() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.setIncentivePool(address(1));
    }

    // ========== INPUT VALIDATION TESTS ==========

    function test_Validation_InvalidChainId() public {
        bytes32 commitment = keccak256("test");

        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSignature("InvalidChainId()"));
        registry.commitSpec(commitment, 0, testExtcodehash);
    }

    function test_Validation_InvalidExtcodehash() public {
        bytes32 commitment = keccak256("test");

        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSignature("InvalidExtcodehash()"));
        registry.commitSpec(commitment, testChainId, bytes32(0));
    }

    function test_Validation_EmptyBlobHash() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(bytes32(0), nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("EmptyBlobHash()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, bytes32(0), nonce, testMetadataHash);
        vm.stopPrank();
    }

    function test_Validation_BelowMinBond() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("BelowMinBond()"));
        registry.revealSpec{value: MIN_BOND - 1}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();
    }

    // ========== DOUBLE REVEAL PREVENTION ==========

    function test_Security_DoubleReveal() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // First reveal succeeds
        registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);

        // Second reveal fails
        vm.expectRevert(abi.encodeWithSignature("CommitmentAlreadyRevealed()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();
    }

    // ========== COMMITMENT VALIDATION ==========

    function test_Security_InvalidReveal_WrongNonce() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // Wrong nonce
        vm.expectRevert(abi.encodeWithSignature("InvalidReveal()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, 99999, testMetadataHash);
        vm.stopPrank();
    }

    function test_Security_InvalidReveal_WrongBlobHash() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // Wrong blob hash
        vm.expectRevert(abi.encodeWithSignature("InvalidReveal()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, keccak256("wrong"), nonce, testMetadataHash);
        vm.stopPrank();
    }

    function test_Security_InvalidReveal_WrongCommitter() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        // Attester commits
        vm.prank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // Attacker tries to reveal
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("InvalidReveal()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
    }

    function test_Security_CommitmentNotFound() public {
        bytes32 fakeCommitmentId = keccak256("fake");

        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSignature("CommitmentNotFound()"));
        registry.revealSpec{value: MIN_BOND}(fakeCommitmentId, testBlobHash, 12345, testMetadataHash);
    }

    // ========== MODE ENFORCEMENT ==========

    function test_Security_ModeEnforcement_TokenInETHMode() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // Try token function in ETH mode
        vm.expectRevert(abi.encodeWithSignature("UseRevealSpecETH()"));
        registry.revealSpecToken(commitmentId, testBlobHash, nonce, testMetadataHash, MIN_BOND);
        vm.stopPrank();
    }

    // ========== FINALIZATION SECURITY ==========

    function test_Security_FinalizeNotFinalized() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();

        // Try to finalize before Reality.eth question is answered
        // Contract uses ChallengePeriodActive when Reality.eth question is not finalized
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSignature("ChallengePeriodActive()"));
        registry.finalize(uid, bytes32(0), proof);
    }

    function test_Security_FinalizeAlreadyFinalized() public {
        // Submit and finalize a spec
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();

        bytes32 questionId = registry.questionIds(uid);

        // Submit APPROVE answer
        vm.prank(attester);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0);

        // Warp past timeout
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        // First finalize
        bytes32 leaf = keccak256(abi.encode(LEAF_TYPEHASH, testChainId, testExtcodehash, testMetadataHash, uint64(1), false));
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(attester);
        registry.finalize(uid, leaf, proof);

        // Try to finalize again
        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSignature("AlreadyFinalized()"));
        registry.finalize(uid, leaf, proof);
    }

    // ========== REVOCATION SECURITY ==========

    function test_Security_ProposeRevoke_NotFinalized() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();

        // Try to revoke before finalized
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("NotFinalized()"));
        registry.proposeRevoke{value: MIN_BOND}(uid);
    }

    function test_Security_ProposeRevoke_AlreadyRevoked() public {
        // Create and finalize an approved attestation
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();

        bytes32 questionId = registry.questionIds(uid);

        // Submit REJECT answer (this marks as revoked on finalization)
        vm.prank(attester);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(0)), 0);

        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(attester);
        registry.finalize(uid, bytes32(0), proof);

        // Try to propose revoke on already revoked attestation
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("AlreadyRevoked()"));
        registry.proposeRevoke{value: MIN_BOND}(uid);
    }

    // ========== PAUSE PROTECTION ==========

    function test_Security_Paused_CommitSpec() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(attester);
        vm.expectRevert();
        registry.commitSpec(keccak256("test"), testChainId, testExtcodehash);
    }

    function test_Security_Paused_RevealSpec() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.prank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.prank(owner);
        registry.pause();

        vm.prank(attester);
        vm.expectRevert();
        registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
    }

    function test_Security_Paused_Finalize() public {
        // Setup complete flow
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();

        bytes32 questionId = registry.questionIds(uid);
        vm.prank(attester);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0);

        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        // Pause
        vm.prank(owner);
        registry.pause();

        // Try to finalize
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(attester);
        vm.expectRevert();
        registry.finalize(uid, bytes32(0), proof);
    }

    function test_Security_Paused_ProposeRevoke() public {
        // Create and finalize approved attestation
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();

        bytes32 questionId = registry.questionIds(uid);
        vm.prank(attester);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0);

        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);

        bytes32 leaf = keccak256(abi.encode(LEAF_TYPEHASH, testChainId, testExtcodehash, testMetadataHash, uint64(1), false));
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(attester);
        registry.finalize(uid, leaf, proof);

        // Pause
        vm.prank(owner);
        registry.pause();

        // Try to propose revoke
        vm.prank(attacker);
        vm.expectRevert();
        registry.proposeRevoke{value: MIN_BOND}(uid);
    }
}
