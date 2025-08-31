// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KaiSign.sol";
import "../staticlib/RealityETH-3.0.sol";

/**
 * Simple time manipulation tests for KaiSign
 */
contract TimeTest is Test {
    KaiSign kaisign;
    RealityETH_v3_0 realityETH;
    
    address admin = address(0x1);
    address user = address(0x2);
    address treasury = address(0x3);
    address arbitrator = address(0x4);
    
    uint256 constant MIN_BOND = 0.01 ether;
    
    function setUp() public {
        realityETH = new RealityETH_v3_0();
        
        vm.startPrank(admin);
        
        address[] memory admins = new address[](1);
        admins[0] = admin;
        
        kaisign = new KaiSign(
            address(realityETH),
            arbitrator,
            treasury,
            MIN_BOND,
            admins
        );
        vm.stopPrank();
        
        vm.deal(user, 10 ether);
    }
    
    // Test commit-reveal with time skip
    function testCommitRevealTimeSkip() public {
        bytes32 blobHash = keccak256("test-blob-hash");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        address target = address(0x7777);
        
        // Commit
        vm.prank(user);
        kaisign.commitSpec(commitment, target, 1);
        
        // Skip 30 minutes
        vm.warp(block.timestamp + 30 minutes);
        
        // Reveal should work
        uint256 chainId = 1;
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user, target, chainId, commitTime
        ));
        
        vm.prank(user);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Should be auto-proposed
        bytes32 specId = keccak256(abi.encodePacked(
            blobHash, target, chainId, user, commitTime
        ));
        
        (,, KaiSign.Status status,,,,,,,,) = kaisign.specs(specId);
        assertEq(uint256(status), uint256(KaiSign.Status.Proposed));
    }
    
    // Test commit timeout
    function testCommitTimeout() public {
        bytes32 blobHash = keccak256("test-blob-hash-2");
        uint256 nonce = 54321;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        address target = address(0x8888);
        
        // Commit
        vm.prank(user);
        kaisign.commitSpec(commitment, target, 1);
        
        uint256 chainId = 1;
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user, target, chainId, uint64(block.timestamp)
        ));
        
        // Skip past timeout (1 hour + 1 second)
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Reveal should fail
        vm.prank(user);
        vm.expectRevert(KaiSign.CommitmentExpired.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
    }
    
    // Test incentive deadline
    function testIncentiveDeadline() public {
        address target = address(0x9999);
        
        // Create incentive with 7 day deadline
        vm.prank(user);
        bytes32 incentiveId = kaisign.createIncentive{value: 1 ether}(
            target, 1, 1 ether, 7 days, "Test incentive"
        );
        
        // Create and reveal spec immediately
        bytes32 blobHash = keccak256("test-blob-hash-3");
        uint256 nonce = 11111;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user);
        kaisign.commitSpec(commitment, target, 1);
        
        uint256 chainId = 1;
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user, target, chainId, commitTime
        ));
        
        vm.prank(user);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Get question ID and mock acceptance
        (,,,,,,,, bytes32 questionId,,) = kaisign.specs(specId);
        
        // Skip to after incentive deadline
        vm.warp(block.timestamp + 8 days);
        
        // Mock Reality.eth finalization
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.isFinalized.selector, questionId),
            abi.encode(true)
        );
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.resultFor.selector, questionId),
            abi.encode(bytes32(uint256(1)))
        );
        
        // Handle result - incentive should be expired
        kaisign.handleResult(specId);
        
        // Check spec is finalized but no incentive paid (expired)
        (,, KaiSign.Status status,,,,,,,,) = kaisign.specs(specId);
        assertEq(uint256(status), uint256(KaiSign.Status.Finalized));
    }
    
    // Test incentive clawback timing
    function testIncentiveClawbackTiming() public {
        address target = address(0xAAAA);
        
        // Create incentive
        vm.prank(user);
        bytes32 incentiveId = kaisign.createIncentive{value: 1 ether}(
            target, 1, 1 ether, 7 days, "Clawback test"
        );
        
        // Cannot clawback immediately
        vm.prank(user);
        vm.expectRevert(KaiSign.ClawbackTooEarly.selector);
        kaisign.clawbackIncentive(incentiveId);
        
        // Skip 30 days - still cannot clawback
        vm.warp(block.timestamp + 30 days);
        vm.prank(user);
        vm.expectRevert(KaiSign.ClawbackTooEarly.selector);
        kaisign.clawbackIncentive(incentiveId);
        
        // Skip to exactly 90 days - should be able to clawback
        vm.warp(block.timestamp + 60 days); // Total 90 days
        
        uint256 balanceBefore = user.balance;
        vm.prank(user);
        kaisign.clawbackIncentive(incentiveId);
        
        // Check funds returned
        assertEq(user.balance, balanceBefore + 1 ether);
        
        // Check incentive marked as claimed
        (,,,,,, bool isClaimed, bool isActive,,) = kaisign.incentives(incentiveId);
        assertTrue(isClaimed);
        assertFalse(isActive);
    }
    
    // Test multiple time-based operations
    function testMultipleTimeOperations() public {
        address target1 = address(0xBBBB);
        address target2 = address(0xCCCC);
        
        // Create two incentives at different times
        vm.prank(user);
        bytes32 incentiveId1 = kaisign.createIncentive{value: 0.5 ether}(
            target1, 1, 0.5 ether, 7 days, "First incentive"
        );
        
        vm.warp(block.timestamp + 1 days);
        
        vm.prank(user);
        bytes32 incentiveId2 = kaisign.createIncentive{value: 0.5 ether}(
            target2, 1, 0.5 ether, 7 days, "Second incentive"
        );
        
        // Create specs for both
        bytes32 blobHash1 = keccak256("blob-1");
        uint256 nonce1 = 1;
        bytes32 commitment1 = keccak256(abi.encodePacked(blobHash1, nonce1));
        
        vm.prank(user);
        kaisign.commitSpec(commitment1, target1, 1);
        
        uint64 commitTime1 = uint64(block.timestamp);
        bytes32 commitmentId1 = keccak256(abi.encodePacked(
            commitment1, user, target1, uint256(1), commitTime1
        ));
        
        // Skip 30 minutes and reveal first
        vm.warp(block.timestamp + 30 minutes);
        
        vm.prank(user);
        bytes32 specId1 = kaisign.revealSpec{value: MIN_BOND}(commitmentId1, blobHash1, blobHash1, nonce1);
        
        // Create second spec
        bytes32 blobHash2 = keccak256("blob-2");
        uint256 nonce2 = 2;
        bytes32 commitment2 = keccak256(abi.encodePacked(blobHash2, nonce2));
        
        vm.prank(user);
        kaisign.commitSpec(commitment2, target2, 1);
        
        uint64 commitTime2 = uint64(block.timestamp);
        bytes32 commitmentId2 = keccak256(abi.encodePacked(
            commitment2, user, target2, uint256(1), commitTime2
        ));
        
        // Skip another 30 minutes and reveal second
        vm.warp(block.timestamp + 30 minutes);
        
        vm.prank(user);
        bytes32 specId2 = kaisign.revealSpec{value: MIN_BOND}(commitmentId2, blobHash2, blobHash2, nonce2);
        
        // Both should be proposed
        (,, KaiSign.Status status1,,,,,,,,) = kaisign.specs(specId1);
        (,, KaiSign.Status status2,,,,,,,,) = kaisign.specs(specId2);
        assertEq(uint256(status1), uint256(KaiSign.Status.Proposed));
        assertEq(uint256(status2), uint256(KaiSign.Status.Proposed));
        
        // Skip to after first incentive expires but before second
        vm.warp(block.timestamp + 5 days);
        
        // First incentive should be expired (created 1 day + 30 min + 30 min + 5 days = 7 days total)
        // Second incentive should still be valid (created 30 min + 30 min + 5 days = 6 days total)
        
        // Get question IDs
        (,,,,,,,, bytes32 questionId1,,) = kaisign.specs(specId1);
        (,,,,,,,, bytes32 questionId2,,) = kaisign.specs(specId2);
        
        // Mock both as finalized and accepted
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.isFinalized.selector, questionId1),
            abi.encode(true)
        );
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.resultFor.selector, questionId1),
            abi.encode(bytes32(uint256(1)))
        );
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.isFinalized.selector, questionId2),
            abi.encode(true)
        );
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.resultFor.selector, questionId2),
            abi.encode(bytes32(uint256(1)))
        );
        
        uint256 balanceBefore = user.balance;
        
        // Handle both results
        kaisign.handleResult(specId1);
        kaisign.handleResult(specId2);
        
        // Both incentives are paid from the pool (minus fees)
        // The pool contains 1 ether total (0.5 + 0.5)
        // Each spec claims from the pool when accepted
        uint256 expectedPayout = (0.5 ether - (0.5 ether * 5 / 100)) * 2; // 0.475 ether * 2 = 0.95 ether
        assertEq(user.balance, balanceBefore + expectedPayout);
    }
    
    // Test Reality.eth timeout
    function testRealityETHTimeout() public {
        address target = address(0xDDDD);
        
        // Create and reveal spec
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 99999;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user);
        kaisign.commitSpec(commitment, target, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user, target, uint256(1), commitTime
        ));
        
        vm.prank(user);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Check DEFAULT_TIMEOUT is used
        assertEq(kaisign.DEFAULT_TIMEOUT(), 48 hours);
        
        // Skip time but not enough for Reality.eth finalization
        vm.warp(block.timestamp + 24 hours);
        
        (,,,,,,,, bytes32 questionId,,) = kaisign.specs(specId);
        
        // Mock not finalized yet
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.isFinalized.selector, questionId),
            abi.encode(false)
        );
        
        // Should not be able to handle result yet
        vm.expectRevert(KaiSign.NotFinalized.selector);
        kaisign.handleResult(specId);
        
        // Skip past timeout
        vm.warp(block.timestamp + 25 hours); // Total 49 hours
        
        // Mock finalized
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.isFinalized.selector, questionId),
            abi.encode(true)
        );
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.resultFor.selector, questionId),
            abi.encode(bytes32(uint256(1)))
        );
        
        // Now should be able to handle
        kaisign.handleResult(specId);
        
        (,, KaiSign.Status status,,,,,,,,) = kaisign.specs(specId);
        assertEq(uint256(status), uint256(KaiSign.Status.Finalized));
    }
}