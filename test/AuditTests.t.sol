// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KaiSign.sol";
import {RealityETH_v3_0} from "../staticlib/RealityETH-3.0.sol";

/**
 * @title Comprehensive Security Audit Tests for KaiSign System
 * @dev Tests covering: Access Control, Reentrancy, Economic Attacks, Edge Cases, DoS Vectors
 */
contract AuditTests is Test {
    KaiSign kaisign;
    RealityETH_v3_0 realityETH;
    
    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);
    address user4 = address(0x5);
    address treasury = address(0x6);
    address arbitrator = address(0x7);
    address attacker = address(0x8);
    address target = address(0x7777);
    
    uint256 constant MIN_BOND = 0.01 ether;
    uint256 constant LARGE_AMOUNT = 1000 ether;
    
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
        
        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);
        vm.deal(attacker, 100 ether);
    }

    // =============================================================================
    //                           ACCESS CONTROL TESTS
    // =============================================================================
    
    function testOnlyAdminFunctions() public {
        // Test unauthorized access to admin functions
        vm.prank(attacker);
        vm.expectRevert(KaiSign.Unauthorized.selector);
        kaisign.setMinBond(0.02 ether);
        
        vm.prank(attacker);
        vm.expectRevert(KaiSign.Unauthorized.selector);
        kaisign.addAdmin(attacker);
        
        vm.prank(attacker);
        vm.expectRevert(KaiSign.Unauthorized.selector);
        kaisign.removeAdmin(admin);
        
        vm.prank(attacker);
        vm.expectRevert(KaiSign.Unauthorized.selector);
        kaisign.emergencyPause();
    }
    
    function testAdminRoleManagement() public {
        // Test admin can add/remove other admins
        vm.startPrank(admin);
        kaisign.addAdmin(user1);
        assertTrue(kaisign.hasRole(kaisign.ADMIN_ROLE(), user1));
        
        kaisign.removeAdmin(user1);
        assertFalse(kaisign.hasRole(kaisign.ADMIN_ROLE(), user1));
        vm.stopPrank();
    }
    
    

    // =============================================================================
    //                           REENTRANCY TESTS
    // =============================================================================
    
    function testReentrancyProtectionIncentiveCreation() public {
        ReentrancyAttacker reentrancyAttacker = new ReentrancyAttacker(kaisign);
        vm.deal(address(reentrancyAttacker), 10 ether);
        
        // Create an incentive that triggers refund to attacker (which will trigger receive())
        vm.prank(address(reentrancyAttacker));
        vm.expectRevert(); // Should revert due to reentrancy protection
        // Send excess ETH to trigger refund and reentrancy attempt
        reentrancyAttacker.attemptReentrancyOnIncentive();
    }
    
    function testReentrancyProtectionCommitReveal() public {
        ReentrancyAttacker reentrancyAttacker = new ReentrancyAttacker(kaisign);
        vm.deal(address(reentrancyAttacker), 10 ether);
        
        // First create an incentive that the attacker can claim
        vm.prank(user1);
        kaisign.createIncentive{value: 1 ether}(
            target, 1, 1 ether, 7 days, "incentive for attacker"
        );
        
        // Commit spec from attacker
        string memory ipfs = "QmTest123";
        uint256 nonce = 12345;
        bytes32 metadataHash = keccak256(abi.encodePacked(ipfs, "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        vm.prank(address(reentrancyAttacker));
        kaisign.commitSpec(commitment, target, 1);
        
        vm.warp(block.timestamp + 30 minutes);
        
        // Reveal spec (this will auto-propose and when handleResult is called, will trigger incentive claim)
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, address(reentrancyAttacker), target, uint256(1), commitTime
        ));
        
        vm.prank(address(reentrancyAttacker));
        bytes32 blobHash = keccak256(abi.encodePacked(ipfs));
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, metadataHash, nonce);
        
        // Get questionId and mock acceptance
        (,,,,,address creator, address targetContract, bytes32 blobHashFromSpec, bytes32 questionId, bytes32 specIncentiveId, uint256 specChainId) = kaisign.specs(specId);
        // Mock Reality.eth finalization and acceptance
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
        
        // This should trigger reentrancy when incentive is claimed to attacker
        vm.expectRevert(); // Should revert due to reentrancy protection
        kaisign.handleResult(specId);
    }

    // =============================================================================
    //                           ECONOMIC ATTACK TESTS
    // =============================================================================
    
    function testOverflowProtection() public {
        // Test bond amount overflow protection
        vm.prank(user1);
        vm.expectRevert(KaiSign.InsufficientIncentive.selector);
        kaisign.createIncentive{value: 1 ether}(
            target, 1, type(uint256).max, 7 days, "overflow test"
        );
    }
    
    function testMultipleIncentivesPooled() public {
        // Create first incentive
        vm.prank(user1);
        bytes32 incentiveId1 = kaisign.createIncentive{value: 1 ether}(
            target, 1, 1 ether, 7 days, "first incentive"
        );
        
        // Create second active incentive for same contract/chain - should succeed now
        vm.prank(user2);
        bytes32 incentiveId2 = kaisign.createIncentive{value: 2 ether}(
            target, 1, 2 ether, 7 days, "second incentive"
        );
        
        // Create third incentive from different user
        vm.prank(user3);
        bytes32 incentiveId3 = kaisign.createIncentive{value: 1.5 ether}(
            target, 1, 1.5 ether, 7 days, "third incentive"
        );
        
        // Verify all incentives exist and are active
        (, uint80 amount1, , , , , bool claimed1, bool active1, , ) = kaisign.incentives(incentiveId1);
        (, uint80 amount2, , , , , bool claimed2, bool active2, , ) = kaisign.incentives(incentiveId2);
        (, uint80 amount3, , , , , bool claimed3, bool active3, , ) = kaisign.incentives(incentiveId3);
        
        assertEq(uint256(amount1), 1 ether);
        assertEq(uint256(amount2), 2 ether);
        assertEq(uint256(amount3), 1.5 ether);
        assertTrue(active1);
        assertTrue(active2);
        assertTrue(active3);
        assertFalse(claimed1);
        assertFalse(claimed2);
        assertFalse(claimed3);
        
        // Verify incentive pool contains total amount
        (uint256 poolAmount, uint256 contributorCount) = kaisign.getIncentivePool(target, 1);
        assertEq(poolAmount, 4.5 ether); // 1 + 2 + 1.5 ether
        assertEq(contributorCount, 3);
        
        // Now create and finalize a spec to claim the entire pool
        vm.startPrank(user4);
        
        // Create commitment hash from IPFS and nonce
        uint256 nonce = 12345;
        bytes32 blobHash = keccak256(abi.encodePacked("test_spec"));
        bytes32 metadataHash = keccak256(abi.encodePacked("test_spec", "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        // Record logs to capture commitment ID
        vm.recordLogs();
        kaisign.commitSpec(commitment, target, 1);
        
        // Get commitment ID from event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 commitmentId = logs[0].topics[2];
        
        // Fast forward and reveal
        vm.warp(block.timestamp + 1 hours);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(
            commitmentId,
            blobHash,
            metadataHash,
            nonce
        );
        
        vm.stopPrank();
        
        // Get the question ID and mock result
        (,,,,,,,,bytes32 questionId,,) = kaisign.specs(specId);
        // Mock Reality.eth finalization and acceptance
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
        
        // Record balances before claiming
        uint256 claimerBalanceBefore = user4.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        // Handle result and claim the entire pool
        vm.prank(user4);
        kaisign.handleResult(specId);
        
        // Calculate expected payouts
        uint256 totalPool = 4.5 ether;
        uint256 expectedPlatformFee = (totalPool * 5) / 100; // 5% platform fee
        uint256 expectedClaimerAmount = totalPool - expectedPlatformFee;
        
        // Verify payouts
        uint256 claimerPayout = user4.balance - claimerBalanceBefore;
        uint256 treasuryPayout = treasury.balance - treasuryBalanceBefore;
        
        assertEq(claimerPayout, expectedClaimerAmount);
        assertEq(treasuryPayout, expectedPlatformFee);
        
        // Verify pool is now empty
        (uint256 poolAmountAfter, uint256 contributorCountAfter) = kaisign.getIncentivePool(target, 1);
        assertEq(poolAmountAfter, 0);
        assertEq(contributorCountAfter, 3); // Count doesn't change when claiming
        
        console.log("Total pool claimed:", totalPool);
        console.log("Claimer received:", claimerPayout);
        console.log("Treasury received:", treasuryPayout);
    }
    
    function testPlatformFeeManipulation() public {
        // Create and claim incentive to verify platform fee is taken
        vm.prank(user1);
        bytes32 incentiveId = kaisign.createIncentive{value: 1 ether}(
            target, 1, 1 ether, 7 days, "fee test"
        );
        
        // Create and accept spec
        string memory ipfs = "QmTest123";
        uint256 nonce = 12345;
        bytes32 metadataHash = keccak256(abi.encodePacked(ipfs, "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        vm.prank(user2);
        kaisign.commitSpec(commitment, target, 1);
        
        vm.warp(block.timestamp + 30 minutes);
        
        uint256 chainId = 1;
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user2, target, chainId, commitTime
        ));
        
        vm.prank(user2);
        bytes32 blobHash = keccak256(abi.encodePacked(ipfs));
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, metadataHash, nonce);
        
        // Get the actual questionId from the spec  
        (,,,,,address creator, address targetContract, bytes32 blobHashFromSpec, bytes32 questionId, bytes32 specIncentiveId, uint256 specChainId) = kaisign.specs(specId);
        // Mock Reality.eth finalization and acceptance
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
        
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 user2BalanceBefore = user2.balance;
        
        kaisign.handleResult(specId);
        
        // Verify platform fee (5%) was taken
        uint256 expectedFee = (1 ether * 5) / 100;
        uint256 expectedUserAmount = 1 ether - expectedFee;
        
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee);
        assertEq(user2.balance - user2BalanceBefore, expectedUserAmount);
    }

    // =============================================================================
    //                           EDGE CASE TESTS
    // =============================================================================
    
    function testZeroAddressValidation() public {
        vm.expectRevert(KaiSign.InvalidContract.selector);
        vm.prank(user1);
        kaisign.commitSpec(keccak256("test"), address(0), 1);
        
        vm.expectRevert(KaiSign.InvalidContract.selector);
        vm.prank(user1);
        kaisign.createIncentive{value: 1 ether}(
            address(0), 1, 1 ether, 7 days, "test"
        );
    }
    
    function testInvalidChainIdValidation() public {
        vm.expectRevert(KaiSign.InvalidContract.selector);
        vm.prank(user1);
        kaisign.commitSpec(keccak256("test"), target, 0);
        
        vm.expectRevert(KaiSign.InvalidContract.selector);
        vm.prank(user1);
        kaisign.createIncentive{value: 1 ether}(
            target, 0, 1 ether, 7 days, "test"
        );
    }
    
    function testIPFSValidation() public {
        // Test empty IPFS
        string memory ipfs = "";
        uint256 nonce = 12345;
        bytes32 metadataHash = keccak256(abi.encodePacked(ipfs, "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target, 1);
        
        vm.warp(block.timestamp + 30 minutes);
        
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 blobHash = bytes32(0); // Empty blob hash to trigger error
        vm.expectRevert(KaiSign.InvalidReveal.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, metadataHash, nonce);
    }
    
    function testCommitmentTimeout() public {
        string memory ipfs = "QmTest123";
        uint256 nonce = 12345;
        bytes32 metadataHash = keccak256(abi.encodePacked(ipfs, "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target, 1);
        
        // Skip past timeout
        vm.warp(block.timestamp + 2 hours);
        
        uint64 commitTime = uint64(block.timestamp - 2 hours);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 blobHash = keccak256(abi.encodePacked(ipfs));
        vm.expectRevert(KaiSign.CommitmentExpired.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, metadataHash, nonce);
    }
    
    function testIncentiveClawbackTiming() public {
        vm.prank(user1);
        bytes32 incentiveId = kaisign.createIncentive{value: 1 ether}(
            target, 1, 1 ether, 7 days, "clawback test"
        );
        
        // Try to clawback too early
        vm.prank(user1);
        vm.expectRevert(KaiSign.ClawbackTooEarly.selector);
        kaisign.clawbackIncentive(incentiveId);
        
        // Skip to clawback period
        vm.warp(block.timestamp + 91 days);
        
        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        kaisign.clawbackIncentive(incentiveId);
        
        assertEq(user1.balance - balanceBefore, 1 ether);
    }

    // =============================================================================
    //                           DOS VECTOR TESTS
    // =============================================================================
    
    

    // =============================================================================
    //                           STATE MANIPULATION TESTS
    // =============================================================================
    
    function testDoubleReveal() public {
        string memory ipfs = "QmTest123";
        uint256 nonce = 12345;
        bytes32 metadataHash = keccak256(abi.encodePacked(ipfs, "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target, 1);
        
        vm.warp(block.timestamp + 30 minutes);
        
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 blobHash = keccak256(abi.encodePacked(ipfs));
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, metadataHash, nonce);
        
        // Try to reveal again
        vm.prank(user1);
        vm.expectRevert(KaiSign.CommitmentAlreadyRevealed.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, metadataHash, nonce);
    }
    
    function testDoubleProposal() public {
        // Create and reveal spec
        string memory ipfs = "QmTest123";
        uint256 nonce = 12345;
        bytes32 metadataHash = keccak256(abi.encodePacked(ipfs, "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target, 1);
        
        vm.warp(block.timestamp + 30 minutes);
        
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 blobHash = keccak256(abi.encodePacked(ipfs));
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, metadataHash, nonce);
        
        // Try to propose again (should be auto-proposed already)
        vm.prank(user2);
        vm.expectRevert(KaiSign.AlreadyProposed.selector);
        kaisign.proposeSpec{value: MIN_BOND}(specId);
    }
    
    function testPauseProtection() public {
        // Pause contract
        vm.prank(admin);
        kaisign.emergencyPause();
        
        // All user functions should revert when paused
        vm.prank(user1);
        vm.expectRevert();
        kaisign.commitSpec(keccak256("test"), target, 1);
        
        vm.prank(user1);
        vm.expectRevert();
        kaisign.createIncentive{value: 1 ether}(target, 1, 1 ether, 7 days, "test");
        
        // Unpause
        vm.prank(admin);
        kaisign.emergencyUnpause();
        
        // Should work now
        vm.prank(user1);
        kaisign.commitSpec(keccak256("test"), target, 1);
    }

    // =============================================================================
    //                           INTEGRATION TESTS
    // =============================================================================
    
    function testFullWorkflowWithIncentive() public {
        // Create incentive
        vm.prank(user1);
        bytes32 incentiveId = kaisign.createIncentive{value: 1 ether}(
            target, 1, 1 ether, 7 days, "integration test"
        );
        
        // Commit spec
        string memory ipfs = "QmTest123";
        uint256 nonce = 12345;
        bytes32 metadataHash = keccak256(abi.encodePacked(ipfs, "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        vm.prank(user2);
        kaisign.commitSpec(commitment, target, 1);
        
        vm.warp(block.timestamp + 30 minutes);
        
        // Reveal spec
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user2, target, uint256(1), commitTime
        ));
        
        vm.prank(user2);
        bytes32 blobHash = keccak256(abi.encodePacked(ipfs));
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, metadataHash, nonce);
        
        // Verify spec was auto-proposed
        (,, KaiSign.Status status,,,,,,,,) = kaisign.specs(specId);
        assertEq(uint256(status), uint256(KaiSign.Status.Proposed));
        
        // Get the actual questionId from the spec and mock result
        (,,,,,address creator, address targetContract, bytes32 blobHashFromSpec, bytes32 questionId, bytes32 specIncentiveId, uint256 specChainId) = kaisign.specs(specId);
        // Mock Reality.eth finalization and acceptance
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
        
        uint256 user2BalanceBefore = user2.balance;
        kaisign.handleResult(specId);
        
        // Verify incentive was claimed and fee taken
        uint256 expectedAmount = 1 ether - (1 ether * 5) / 100;
        assertEq(user2.balance - user2BalanceBefore, expectedAmount);
        
        // Verify spec is finalized
        (,, status,,,,,,,,) = kaisign.specs(specId);
        assertEq(uint256(status), uint256(KaiSign.Status.Finalized));
    }
}

// =============================================================================
//                           HELPER CONTRACTS
// =============================================================================

contract ReentrancyAttacker {
    KaiSign target;
    bool attacked = false;
    bool shouldAttack = true;
    
    constructor(KaiSign _target) {
        target = _target;
    }
    
    function attemptReentrancyOnIncentive() external {
        shouldAttack = true;
        attacked = false;
        // Send more ETH than needed to trigger refund, which will call receive()
        target.createIncentive{value: 2 ether}(
            address(0x1), 1, 1 ether, 7 days, "attack"
        );
    }
    
    function attemptReentrancyOnReveal(bytes32 commitment, bytes32 blobHash, bytes32 metadataHash, uint256 nonce) external {
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, address(this), address(0x7777), uint256(1), commitTime
        ));
        shouldAttack = true;
        attacked = false;
        target.revealSpec{value: 0.01 ether}(commitmentId, blobHash, metadataHash, nonce);
    }
    
    // This will be called when ETH is transferred to this contract
    receive() external payable {
        if (shouldAttack && !attacked && msg.value > 0) {
            attacked = true;
            // Attempt reentrancy during ETH transfer - this should fail due to nonReentrant
            target.createIncentive{value: 0.1 ether}(
                address(0x9999), 1, 0.1 ether, 7 days, "reentrant attack"
            );
        }
    }
    
    // Alternative attack vector through fallback
    fallback() external payable {
        if (shouldAttack && !attacked) {
            attacked = true;
            target.createIncentive{value: 0.1 ether}(
                address(0x8888), 1, 0.1 ether, 7 days, "fallback attack"
            );
        }
    }
}

