// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";

/**
 * @title KaiSignRegistryTest
 * @notice Unit tests for KaiSignRegistry contract
 * @dev Adapted from V1 ComprehensiveTests.t.sol for V2 with Reality.eth integration
 */
contract KaiSignRegistryTest is Test {
    // ========== CONSTANTS ==========
    address constant REALITY_ETH_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;
    address constant NO_ARBITRATOR = address(0);
    uint256 constant MIN_BOND = 0.01 ether;

    // ========== STATE ==========
    KaiSignRegistry public registry;
    IRealityETH public realityETH;

    address public owner;
    address public attester1;
    address public attester2;
    address public nonAttester;

    // ========== SETUP ==========

    function setUp() public {
        // Fork Sepolia
        string memory rpcUrl = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Create addresses
        owner = makeAddr("owner");
        attester1 = makeAddr("attester1");
        attester2 = makeAddr("attester2");
        nonAttester = makeAddr("nonAttester");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(attester1, 100 ether);
        vm.deal(attester2, 100 ether);
        vm.deal(nonAttester, 100 ether);

        // Deploy registry
        vm.startPrank(owner);
        address[] memory attesters = new address[](1);
        attesters[0] = attester1;

        registry = new KaiSignRegistry(
            1,                    // universeId
            address(0),           // parentRegistry
            owner,                // initialOwner
            attesters,            // initialAttesters
            REALITY_ETH_SEPOLIA,  // realityETH
            NO_ARBITRATOR,        // arbitrator
            MIN_BOND              // minBond
        );
        vm.stopPrank();

        realityETH = IRealityETH(REALITY_ETH_SEPOLIA);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function test_Constructor_SetsCorrectValues() public view {
        assertEq(registry.universeId(), 1);
        assertEq(registry.parentRegistry(), address(0));
        assertEq(registry.owner(), owner);
        assertEq(registry.minBond(), MIN_BOND);
        assertTrue(registry.templateId() > 0);
    }

    function test_Constructor_InvalidRealityETH() public {
        vm.prank(owner);
        address[] memory attesters = new address[](1);
        attesters[0] = attester1;

        vm.expectRevert("Invalid Reality.eth");
        new KaiSignRegistry(
            1, address(0), owner, attesters,
            address(0),  // Invalid Reality.eth
            NO_ARBITRATOR, MIN_BOND
        );
    }

    // Note: Contract does not validate zero minBond - this is by design
    // Owner can set minBond to any value including zero

    // ========== ATTESTER MANAGEMENT TESTS ==========

    function test_AddAttester() public {
        assertFalse(registry.isAttester(attester2));

        vm.prank(owner);
        registry.addAttester(attester2);

        assertTrue(registry.isAttester(attester2));
    }

    function test_AddAttester_OnlyOwner() public {
        vm.prank(nonAttester);
        vm.expectRevert();
        registry.addAttester(attester2);
    }

    function test_AddAttester_AlreadyAttester() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("AlreadyAttester()"));
        registry.addAttester(attester1);
    }

    function test_RemoveAttester() public {
        assertTrue(registry.isAttester(attester1));

        vm.prank(owner);
        registry.removeAttester(attester1);

        assertFalse(registry.isAttester(attester1));
    }

    function test_RemoveAttester_OnlyOwner() public {
        vm.prank(nonAttester);
        vm.expectRevert();
        registry.removeAttester(attester1);
    }

    function test_RemoveAttester_NotAttester() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NotAttester()"));
        registry.removeAttester(attester2);
    }

    function test_GetAttesters() public {
        address[] memory attesters = registry.getAttesters();
        assertEq(attesters.length, 1);
        assertEq(attesters[0], attester1);

        vm.prank(owner);
        registry.addAttester(attester2);

        attesters = registry.getAttesters();
        assertEq(attesters.length, 2);
    }

    // ========== SET MIN BOND TESTS ==========

    function test_SetMinBond() public {
        uint256 newBond = 0.05 ether;

        vm.prank(owner);
        registry.setMinBond(newBond);

        assertEq(registry.minBond(), newBond);
    }

    function test_SetMinBond_OnlyOwner() public {
        vm.prank(nonAttester);
        vm.expectRevert();
        registry.setMinBond(0.05 ether);
    }

    function test_SetMinBond_AllowsZero() public {
        // Contract allows zero minBond - this is by design
        vm.prank(owner);
        registry.setMinBond(0);
        assertEq(registry.minBond(), 0);
    }

    // ========== PAUSE TESTS ==========

    function test_Pause() public {
        vm.prank(owner);
        registry.pause();

        assertTrue(registry.paused());
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(nonAttester);
        vm.expectRevert();
        registry.pause();
    }

    function test_Unpause() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(owner);
        registry.unpause();

        assertFalse(registry.paused());
    }

    function test_CommitSpec_WhenPaused() public {
        vm.prank(owner);
        registry.pause();

        bytes32 commitment = keccak256("test");

        vm.prank(attester1);
        vm.expectRevert();
        registry.commitSpec(commitment, 1, keccak256("bytecode"));
    }

    // ========== COMMIT SPEC TESTS ==========

    function test_CommitSpec() public {
        bytes32 commitment = keccak256(abi.encodePacked(keccak256("blob"), uint256(123)));
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("bytecode");

        vm.prank(attester1);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);

        assertTrue(commitmentId != bytes32(0));

        (address committer, , uint256 storedChainId, bytes32 storedExtcodehash, bool isRevealed) =
            registry.commitments(commitmentId);

        assertEq(committer, attester1);
        assertEq(storedChainId, chainId);
        assertEq(storedExtcodehash, extcodehash);
        assertFalse(isRevealed);
    }

    function test_CommitSpec_InvalidChainId() public {
        bytes32 commitment = keccak256("test");

        vm.prank(attester1);
        vm.expectRevert(abi.encodeWithSignature("InvalidChainId()"));
        registry.commitSpec(commitment, 0, keccak256("bytecode"));
    }

    function test_CommitSpec_InvalidExtcodehash() public {
        bytes32 commitment = keccak256("test");

        vm.prank(attester1);
        vm.expectRevert(abi.encodeWithSignature("InvalidExtcodehash()"));
        registry.commitSpec(commitment, 1, bytes32(0));
    }

    // ========== REVEAL SPEC TESTS ==========

    function test_RevealSpec() public {
        bytes32 blobHash = keccak256("blob-data");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("bytecode");

        vm.startPrank(attester1);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
        bytes32 uid = registry.revealSpec{value: MIN_BOND}(commitmentId, blobHash, nonce);
        vm.stopPrank();

        assertTrue(uid != bytes32(0));

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertEq(att.chainId, chainId);
        assertEq(att.extcodehash, extcodehash);
        assertEq(att.blobHash, blobHash);
        assertEq(att.attester, attester1);
    }

    function test_RevealSpec_BelowMinBond() public {
        bytes32 blobHash = keccak256("blob-data");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));

        vm.startPrank(attester1);
        bytes32 commitmentId = registry.commitSpec(commitment, 1, keccak256("bytecode"));

        vm.expectRevert(abi.encodeWithSignature("BelowMinBond()"));
        registry.revealSpec{value: MIN_BOND - 1}(commitmentId, blobHash, nonce);
        vm.stopPrank();
    }

    function test_RevealSpec_InvalidCommitment() public {
        bytes32 blobHash = keccak256("blob-data");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));

        vm.startPrank(attester1);
        bytes32 commitmentId = registry.commitSpec(commitment, 1, keccak256("bytecode"));

        // Wrong nonce
        vm.expectRevert(abi.encodeWithSignature("InvalidReveal()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, blobHash, 99999);
        vm.stopPrank();
    }

    function test_RevealSpec_DoubleReveal() public {
        bytes32 blobHash = keccak256("blob-data");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));

        vm.startPrank(attester1);
        bytes32 commitmentId = registry.commitSpec(commitment, 1, keccak256("bytecode"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, blobHash, nonce);

        // Try to reveal again
        vm.expectRevert(abi.encodeWithSignature("CommitmentAlreadyRevealed()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, blobHash, nonce);
        vm.stopPrank();
    }

    // ========== QUERY FUNCTION TESTS ==========

    function test_GetAttestation_NotFound() public view {
        IKaiSignRegistry.Attestation memory att = registry.getAttestation(bytes32(uint256(999)));
        assertEq(att.uid, bytes32(0));
    }

    function test_GetSpecsForBytecode_Empty() public view {
        bytes32[] memory specs = registry.getSpecsForBytecode(1, keccak256("nonexistent"));
        assertEq(specs.length, 0);
    }

    function test_GetLatestSpecForBytecode_Empty() public view {
        (bytes32 uid, bool valid) = registry.getLatestSpecForBytecode(1, keccak256("nonexistent"));
        assertEq(uid, bytes32(0));
        assertFalse(valid);
    }

    // ========== MERKLE HELPERS TESTS ==========

    function test_VerifyMerkleProof_SingleLeaf() public view {
        bytes32 leaf = keccak256("leaf");
        bytes32[] memory proof = new bytes32[](0);

        // Single leaf: leaf is its own root
        bool valid = registry.verifyMerkleProof(leaf, proof, 0, leaf);
        assertTrue(valid);
    }

    // ========== STATE GETTERS TESTS ==========

    function test_CurrentIdx() public view {
        assertEq(registry.currentIdx(), 0);
    }

    function test_MerkleRoot() public view {
        assertEq(registry.merkleRoot(), bytes32(0));
    }
}
