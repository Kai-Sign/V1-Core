// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KaiSign.sol";
import "../staticlib/RealityETH-3.0.sol";

/**
 * @title Comprehensive Test Suite for KaiSign Contract Functions
 * @dev Tests EVERY function, modifier, edge case, and scenario in KaiSign contract
 */
contract ComprehensiveTests is Test {
    KaiSign kaisign;
    RealityETH_v3_0 realityETH;
    
    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);
    address treasury = address(0x5);
    address arbitrator = address(0x6);
    address attacker = address(0x7);
    address target1 = address(0x8888);
    address target2 = address(0x9999);
    
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
        
        // Fund accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(attacker, 100 ether);
    }

    // =============================================================================
    //                           CONSTRUCTOR TESTS
    // =============================================================================
    
    function testConstructorInitialization() public {
        assertEq(kaisign.realityETH(), address(realityETH));
        assertEq(kaisign.arbitrator(), arbitrator);
        assertEq(kaisign.treasury(), treasury);
        assertEq(kaisign.minBond(), MIN_BOND);
        assertEq(kaisign.VERSION(), "1.0.0");
        assertEq(kaisign.PLATFORM_FEE_PERCENT(), 5);
        assertEq(kaisign.COMMIT_REVEAL_TIMEOUT(), 1 hours);
        assertEq(kaisign.INCENTIVE_DURATION(), 30 days);
        assertEq(kaisign.INCENTIVE_CLAWBACK_PERIOD(), 90 days);
        assertEq(kaisign.DEFAULT_TIMEOUT(), 48 hours);
    }
    
    function testConstructorValidation() public {
        address[] memory admins = new address[](1);
        admins[0] = admin;
        
        // Test invalid RealityETH address
        vm.expectRevert(KaiSign.InvalidContract.selector);
        new KaiSign(address(0), arbitrator, treasury, MIN_BOND, admins);
        
        // Test invalid arbitrator
        vm.expectRevert(KaiSign.InvalidContract.selector);
        new KaiSign(address(realityETH), address(0), treasury, MIN_BOND, admins);
        
        // Test invalid treasury
        vm.expectRevert(KaiSign.InvalidContract.selector);
        new KaiSign(address(realityETH), arbitrator, address(0), MIN_BOND, admins);
        
        // Test empty admins array
        address[] memory emptyAdmins = new address[](0);
        vm.expectRevert(KaiSign.Unauthorized.selector);
        new KaiSign(address(realityETH), arbitrator, treasury, MIN_BOND, emptyAdmins);
    }

    // =============================================================================
    //                           ADMIN FUNCTION TESTS
    // =============================================================================
    
    function testSetMinBond() public {
        vm.prank(admin);
        kaisign.setMinBond(0.05 ether);
        assertEq(kaisign.minBond(), 0.05 ether);
        
        vm.prank(admin);
        kaisign.setMinBond(0);
        assertEq(kaisign.minBond(), 0);
    }
    
    function testAddAdmin() public {
        vm.prank(admin);
        kaisign.addAdmin(user3);
        assertTrue(kaisign.hasRole(kaisign.ADMIN_ROLE(), user3));
    }
    
    function testRemoveAdmin() public {
        vm.prank(admin);
        kaisign.addAdmin(user3);
        
        vm.prank(admin);
        kaisign.removeAdmin(user3);
        assertFalse(kaisign.hasRole(kaisign.ADMIN_ROLE(), user3));
    }
    
    function testEmergencyPause() public {
        assertFalse(kaisign.paused());
        
        vm.prank(admin);
        kaisign.emergencyPause();
        assertTrue(kaisign.paused());
    }
    
    function testEmergencyUnpause() public {
        vm.prank(admin);
        kaisign.emergencyPause();
        assertTrue(kaisign.paused());
        
        vm.prank(admin);
        kaisign.emergencyUnpause();
        assertFalse(kaisign.paused());
    }

    // =============================================================================
    //                           INCENTIVE SYSTEM TESTS
    // =============================================================================
    
    function testCreateIncentive() public {
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        bytes32 incentiveId = kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 7 days, "Test incentive"
        );
        
        (address creator, uint80 amount,, uint64 deadline, uint64 createdAt, address targetContract, bool isClaimed, bool isActive, uint256 chainId, string memory description) = kaisign.incentives(incentiveId);
        
        assertEq(creator, user1);
        assertEq(amount, 1 ether);
        assertEq(targetContract, target1);
        assertEq(chainId, 1);
        assertFalse(isClaimed);
        assertTrue(isActive);
        assertEq(description, "Test incentive");
        assertEq(deadline, createdAt + 7 days);
        assertEq(user1.balance, balanceBefore - 1 ether);
    }
    
    function testCreateIncentiveWithExcessETH() public {
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        kaisign.createIncentive{value: 2 ether}(
            target1, 1, 1 ether, 7 days, "Test incentive"
        );
        
        // Should refund excess 1 ether
        assertEq(user1.balance, balanceBefore - 1 ether);
    }
    
    function testCreateIncentiveValidation() public {
        // Invalid target contract
        vm.prank(user1);
        vm.expectRevert(KaiSign.InvalidContract.selector);
        kaisign.createIncentive{value: 1 ether}(
            address(0), 1, 1 ether, 7 days, "Test"
        );
        
        // Invalid chain ID
        vm.prank(user1);
        vm.expectRevert(KaiSign.InvalidContract.selector);
        kaisign.createIncentive{value: 1 ether}(
            target1, 0, 1 ether, 7 days, "Test"
        );
        
        // Amount too large
        vm.prank(user1);
        vm.expectRevert(KaiSign.InsufficientIncentive.selector);
        kaisign.createIncentive{value: 1 ether}(
            target1, 1, type(uint256).max, 7 days, "Test"
        );
        
        // Duration too long
        vm.prank(user1);
        vm.expectRevert(KaiSign.IncentiveExpired.selector);
        kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 31 days, "Test"
        );
        
        // Duration zero
        vm.prank(user1);
        vm.expectRevert(KaiSign.IncentiveExpired.selector);
        kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 0, "Test"
        );
        
        // Insufficient ETH
        vm.prank(user1);
        vm.expectRevert(KaiSign.InsufficientIncentive.selector);
        kaisign.createIncentive{value: 0.5 ether}(
            target1, 1, 1 ether, 7 days, "Test"
        );
    }
    
    function testIncentivePoolAccumulation() public {
        // Create multiple incentives for same target
        vm.prank(user1);
        kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 7 days, "Incentive 1"
        );
        
        vm.prank(user2);
        kaisign.createIncentive{value: 2 ether}(
            target1, 1, 2 ether, 7 days, "Incentive 2"
        );
        
        (uint256 poolAmount, uint256 contributorCount) = kaisign.getIncentivePool(target1, 1);
        assertEq(poolAmount, 3 ether);
        assertEq(contributorCount, 2);
    }
    
    function testClawbackIncentive() public {
        vm.prank(user1);
        bytes32 incentiveId = kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 7 days, "Test incentive"
        );
        
        // Cannot clawback before period
        vm.prank(user1);
        vm.expectRevert(KaiSign.ClawbackTooEarly.selector);
        kaisign.clawbackIncentive(incentiveId);
        
        // Fast forward past clawback period
        vm.warp(block.timestamp + 91 days);
        
        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        kaisign.clawbackIncentive(incentiveId);
        
        assertEq(user1.balance, balanceBefore + 1 ether);
        
        // Check pool decreased
        (uint256 poolAmount, ) = kaisign.getIncentivePool(target1, 1);
        assertEq(poolAmount, 0);
        
        // Cannot clawback twice
        vm.prank(user1);
        vm.expectRevert(KaiSign.NoIncentiveToClaim.selector);
        kaisign.clawbackIncentive(incentiveId);
    }
    
    function testClawbackIncentiveOnlyCreator() public {
        vm.prank(user1);
        bytes32 incentiveId = kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 7 days, "Test incentive"
        );
        
        vm.warp(block.timestamp + 91 days);
        
        vm.prank(user2);
        vm.expectRevert(KaiSign.Unauthorized.selector);
        kaisign.clawbackIncentive(incentiveId);
    }

    // =============================================================================
    //                           COMMIT-REVEAL TESTS
    // =============================================================================
    
    function testCommitSpec() public {
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        (address committer, uint64 commitTimestamp,, address targetContract, bool isRevealed, uint80 bondAmount,, uint64 revealDeadline, uint256 chainId, bytes32 incentiveId) = kaisign.commitments(commitmentId);
        
        assertEq(committer, user1);
        assertEq(commitTimestamp, commitTime);
        assertEq(targetContract, target1);
        assertFalse(isRevealed);
        assertEq(bondAmount, 0);
        assertEq(revealDeadline, commitTime + 1 hours);
        assertEq(chainId, 1);
        assertEq(incentiveId, bytes32(0));
    }
    
    function testCommitSpecValidation() public {
        bytes32 commitment = keccak256("test");
        
        // Invalid target contract
        vm.prank(user1);
        vm.expectRevert(KaiSign.InvalidContract.selector);
        kaisign.commitSpec(commitment, address(0), 1);
        
        // Invalid chain ID
        vm.prank(user1);
        vm.expectRevert(KaiSign.InvalidContract.selector);
        kaisign.commitSpec(commitment, target1, 0);
    }
    
    function testRevealSpec() public {
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        vm.warp(block.timestamp + 30 minutes);
        
        uint64 commitTime = uint64(block.timestamp - 30 minutes);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Check spec was created
        (uint64 createdTimestamp, uint64 proposedTimestamp, KaiSign.Status status, uint80 totalBonds,, address creator, address targetContract, bytes32 specBlobHash, bytes32 questionId, bytes32 specIncentiveId, uint256 chainId) = kaisign.specs(specId);
        
        assertEq(createdTimestamp, block.timestamp);
        assertEq(proposedTimestamp, block.timestamp); // Auto-proposed
        assertEq(uint256(status), uint256(KaiSign.Status.Proposed));
        assertEq(totalBonds, MIN_BOND);
        assertEq(creator, user1);
        assertEq(targetContract, target1);
        assertEq(specBlobHash, blobHash);
        assertTrue(questionId != bytes32(0)); // Question was created
        assertEq(chainId, 1);
        
        // Check commitment was marked as revealed
        (,,, , bool isRevealed,,,,,) = kaisign.commitments(commitmentId);
        assertTrue(isRevealed);
    }
    
    function testRevealSpecValidation() public {
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        // Reveal without commit
        bytes32 fakeCommitmentId = keccak256("fake");
        vm.prank(user1);
        vm.expectRevert(KaiSign.CommitmentNotFound.selector);
        kaisign.revealSpec{value: MIN_BOND}(fakeCommitmentId, blobHash, blobHash, nonce);
        
        // Commit first
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        // Wrong user tries to reveal
        vm.prank(user2);
        vm.expectRevert(KaiSign.InvalidReveal.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Reveal after timeout
        vm.warp(block.timestamp + 2 hours);
        vm.prank(user1);
        vm.expectRevert(KaiSign.CommitmentExpired.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // New commit for further tests
        vm.prank(user1);
        kaisign.commitSpec(commitment, target2, 1);
        
        commitTime = uint64(block.timestamp);
        commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target2, uint256(1), commitTime
        ));
        
        // Reveal with empty blob hash
        vm.prank(user1);
        vm.expectRevert(KaiSign.InvalidReveal.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, bytes32(0), bytes32(0), nonce);
        
        // Reveal with insufficient bond
        vm.prank(user1);
        vm.expectRevert(KaiSign.InsufficientBond.selector);
        kaisign.revealSpec{value: MIN_BOND - 1}(commitmentId, blobHash, blobHash, nonce);
        
        // Reveal with wrong nonce (invalid reveal)
        vm.prank(user1);
        vm.expectRevert(KaiSign.InvalidReveal.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce + 1);
        
        // Successful reveal
        vm.prank(user1);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Try to reveal again
        vm.prank(user1);
        vm.expectRevert(KaiSign.CommitmentAlreadyRevealed.selector);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
    }
    
    function testRevealWithLargeBond() public {
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        // Reveal with larger bond than minimum
        vm.prank(user1);
        bytes32 specId = kaisign.revealSpec{value: 1 ether}(commitmentId, blobHash, blobHash, nonce);
        
        (,,, uint80 totalBonds,,,,,,,) = kaisign.specs(specId);
        assertEq(totalBonds, 1 ether);
    }

    // =============================================================================
    //                           SPEC MANAGEMENT TESTS
    // =============================================================================
    
    function testProposeSpec() public {
        // Test that specs auto-propose when revealed with sufficient bond
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        // Wait for reveal period
        vm.warp(block.timestamp + 30 minutes);
        
        // Reveal with exact minBond - this will auto-propose
        vm.prank(user1);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Check status is automatically Proposed
        (,, KaiSign.Status status, uint80 totalBonds,,,,,,,) = kaisign.specs(specId);
        assertEq(uint256(status), uint256(KaiSign.Status.Proposed));
        assertEq(totalBonds, MIN_BOND);
        
        // Test that proposeSpec cannot be called on already proposed spec
        vm.prank(user2);
        vm.expectRevert(KaiSign.AlreadyProposed.selector);
        kaisign.proposeSpec{value: 0.02 ether}(specId);
    }
    
    function testProposeSpecValidation() public {
        // Try to propose non-existent spec
        bytes32 fakeSpecId = keccak256("fake");
        vm.prank(user1);
        vm.expectRevert(KaiSign.NotProposed.selector);
        kaisign.proposeSpec{value: MIN_BOND}(fakeSpecId);
        
        // Create and auto-propose a spec
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Try to propose already proposed spec
        vm.prank(user2);
        vm.expectRevert(KaiSign.AlreadyProposed.selector);
        kaisign.proposeSpec{value: MIN_BOND}(specId);
    }
    
    function testHandleResult() public {
        // Create and propose spec
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        // Create incentive first
        vm.prank(user1);
        kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 7 days, "Test incentive"
        );
        
        vm.prank(user2);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user2, target1, uint256(1), commitTime
        ));
        
        vm.prank(user2);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Get question ID
        (,,,,,,,, bytes32 questionId,,) = kaisign.specs(specId);
        
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
        uint256 treasuryBalanceBefore = treasury.balance;
        
        kaisign.handleResult(specId);
        
        // Check spec is finalized
        (,, KaiSign.Status status,,,,,,,,) = kaisign.specs(specId);
        assertEq(uint256(status), uint256(KaiSign.Status.Finalized));
        
        // Check incentive was paid out with fee
        uint256 expectedFee = (1 ether * 5) / 100;
        uint256 expectedPayout = 1 ether - expectedFee;
        assertEq(user2.balance - user2BalanceBefore, expectedPayout);
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee);
    }
    
    function testHandleResultRejection() public {
        // Create and propose spec
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Get question ID
        (,,,,,,,, bytes32 questionId,,) = kaisign.specs(specId);
        
        // Mock Reality.eth finalization and rejection
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.isFinalized.selector, questionId),
            abi.encode(true)
        );
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.resultFor.selector, questionId),
            abi.encode(bytes32(uint256(0))) // Rejected
        );
        
        kaisign.handleResult(specId);
        
        // Check spec is finalized
        (,, KaiSign.Status status,,,,,,,,) = kaisign.specs(specId);
        assertEq(uint256(status), uint256(KaiSign.Status.Finalized));
    }
    
    function testHandleResultValidation() public {
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        // Get question ID
        (,,,,,,,, bytes32 questionId,,) = kaisign.specs(specId);
        
        // Try to handle before finalization
        vm.mockCall(
            address(realityETH),
            abi.encodeWithSelector(RealityETH_v3_0.isFinalized.selector, questionId),
            abi.encode(false)
        );
        
        vm.expectRevert(KaiSign.NotFinalized.selector);
        kaisign.handleResult(specId);
    }

    // =============================================================================
    //                           QUERY FUNCTION TESTS
    // =============================================================================
    
    function testGetSpecsByContract() public {
        // Create multiple specs for same contract
        for (uint i = 0; i < 3; i++) {
            bytes32 blobHash = keccak256(abi.encodePacked("blob", i));
            uint256 nonce = i;
            bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
            
            vm.prank(user1);
            kaisign.commitSpec(commitment, target1, 1);
            
            uint64 commitTime = uint64(block.timestamp);
            bytes32 commitmentId = keccak256(abi.encodePacked(
                commitment, user1, target1, uint256(1), commitTime
            ));
            
            vm.prank(user1);
            kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
            
            vm.warp(block.timestamp + 1);
        }
        
        bytes32[] memory specs = kaisign.getSpecsByContract(target1, 1);
        assertEq(specs.length, 3);
    }
    
    function testGetSpecsByContractPaginated() public {
        // Create 5 specs
        for (uint i = 0; i < 5; i++) {
            bytes32 blobHash = keccak256(abi.encodePacked("blob", i));
            uint256 nonce = i;
            bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
            
            vm.prank(user1);
            kaisign.commitSpec(commitment, target1, 1);
            
            uint64 commitTime = uint64(block.timestamp);
            bytes32 commitmentId = keccak256(abi.encodePacked(
                commitment, user1, target1, uint256(1), commitTime
            ));
            
            vm.prank(user1);
            kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
            
            vm.warp(block.timestamp + 1);
        }
        
        // Test pagination
        (bytes32[] memory page1, uint256 total) = kaisign.getSpecsByContractPaginated(target1, 1, 0, 2);
        assertEq(page1.length, 2);
        assertEq(total, 5);
        
        (bytes32[] memory page2, uint256 total2) = kaisign.getSpecsByContractPaginated(target1, 1, 2, 2);
        assertEq(page2.length, 2);
        assertEq(total2, 5);
        
        (bytes32[] memory page3, uint256 total3) = kaisign.getSpecsByContractPaginated(target1, 1, 4, 2);
        assertEq(page3.length, 1);
        assertEq(total3, 5);
        
        // Test out of bounds
        (bytes32[] memory pageEmpty, uint256 total4) = kaisign.getSpecsByContractPaginated(target1, 1, 10, 2);
        assertEq(pageEmpty.length, 0);
        assertEq(total4, 5);
    }
    
    function testGetContractSpecCount() public {
        assertEq(kaisign.getContractSpecCount(target1, 1), 0);
        
        // Create a spec
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        assertEq(kaisign.getContractSpecCount(target1, 1), 1);
    }
    
    function testGetUserIncentives() public {
        // Create incentives
        vm.prank(user1);
        bytes32 incentiveId1 = kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 7 days, "Incentive 1"
        );
        
        vm.prank(user1);
        bytes32 incentiveId2 = kaisign.createIncentive{value: 1 ether}(
            target2, 1, 1 ether, 7 days, "Incentive 2"
        );
        
        bytes32[] memory userIncentives = kaisign.getUserIncentives(user1);
        assertEq(userIncentives.length, 2);
        assertEq(userIncentives[0], incentiveId1);
        assertEq(userIncentives[1], incentiveId2);
    }
    
    function testGetIncentivePool() public {
        (uint256 poolAmount, uint256 contributorCount) = kaisign.getIncentivePool(target1, 1);
        assertEq(poolAmount, 0);
        assertEq(contributorCount, 0);
        
        // Add incentives
        vm.prank(user1);
        kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 7 days, "Incentive 1"
        );
        
        vm.prank(user2);
        kaisign.createIncentive{value: 2 ether}(
            target1, 1, 2 ether, 7 days, "Incentive 2"
        );
        
        (poolAmount, contributorCount) = kaisign.getIncentivePool(target1, 1);
        assertEq(poolAmount, 3 ether);
        assertEq(contributorCount, 2);
    }
    
    function testGetSpecBlobHash() public {
        bytes32 blobHash = keccak256("test-blob");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        vm.prank(user1);
        kaisign.commitSpec(commitment, target1, 1);
        
        uint64 commitTime = uint64(block.timestamp);
        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment, user1, target1, uint256(1), commitTime
        ));
        
        vm.prank(user1);
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
        
        assertEq(kaisign.getSpecBlobHash(specId), blobHash);
    }

    // =============================================================================
    //                           PAUSABLE TESTS
    // =============================================================================
    
    function testPausableFunctions() public {
        vm.prank(admin);
        kaisign.emergencyPause();
        
        // Test all user functions are paused
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        kaisign.createIncentive{value: 1 ether}(
            target1, 1, 1 ether, 7 days, "Test"
        );
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        kaisign.commitSpec(keccak256("test"), target1, 1);
        
        bytes32 fakeCommitmentId = keccak256("fake");
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        kaisign.revealSpec{value: MIN_BOND}(fakeCommitmentId, keccak256("blob"), keccak256("blob"), 123);
        
        bytes32 fakeSpecId = keccak256("spec");
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        kaisign.proposeSpec{value: MIN_BOND}(fakeSpecId);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        kaisign.handleResult(fakeSpecId);
        
        bytes32 fakeIncentiveId = keccak256("incentive");
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        kaisign.clawbackIncentive(fakeIncentiveId);
        
        // Unpause
        vm.prank(admin);
        kaisign.emergencyUnpause();
        
        // Functions should work now
        vm.prank(user1);
        kaisign.commitSpec(keccak256("test"), target1, 1);
    }

    // =============================================================================
    //                           ACCESS CONTROL TESTS
    // =============================================================================
    
    function testRoleBasedAccessControl() public {
        // Check initial roles
        assertTrue(kaisign.hasRole(kaisign.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(kaisign.hasRole(kaisign.ADMIN_ROLE(), admin));
        
        // Add new admin
        vm.prank(admin);
        kaisign.addAdmin(user3);
        assertTrue(kaisign.hasRole(kaisign.ADMIN_ROLE(), user3));
        
        // New admin can perform admin functions
        vm.prank(user3);
        kaisign.setMinBond(0.02 ether);
        assertEq(kaisign.minBond(), 0.02 ether);
        
        // Remove admin
        vm.prank(admin);
        kaisign.removeAdmin(user3);
        assertFalse(kaisign.hasRole(kaisign.ADMIN_ROLE(), user3));
        
        // Removed admin cannot perform admin functions
        vm.prank(user3);
        vm.expectRevert(KaiSign.Unauthorized.selector);
        kaisign.setMinBond(0.03 ether);
    }

    // =============================================================================
    //                           EDGE CASE TESTS
    // =============================================================================
    
    function testMultipleSpecsSameContract() public {
        // Create multiple specs for same contract from different users
        for (uint i = 0; i < 3; i++) {
            address user = i == 0 ? user1 : i == 1 ? user2 : user3;
            bytes32 blobHash = keccak256(abi.encodePacked("blob", i));
            uint256 nonce = i;
            bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
            
            vm.prank(user);
            kaisign.commitSpec(commitment, target1, 1);
            
            uint64 commitTime = uint64(block.timestamp);
            bytes32 commitmentId = keccak256(abi.encodePacked(
                commitment, user, target1, uint256(1), commitTime
            ));
            
            vm.prank(user);
            kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
            
            vm.warp(block.timestamp + 1);
        }
        
        assertEq(kaisign.getContractSpecCount(target1, 1), 3);
    }
    
    function testDifferentChainIds() public {
        // Create specs for same contract on different chains
        for (uint256 chainId = 1; chainId <= 3; chainId++) {
            bytes32 blobHash = keccak256(abi.encodePacked("test-blob", chainId));
            uint256 nonce = 12345 + chainId;
            bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
            
            vm.prank(user1);
            kaisign.commitSpec(commitment, target1, chainId);
            
            uint64 commitTime = uint64(block.timestamp);
            bytes32 commitmentId = keccak256(abi.encodePacked(
                commitment, user1, target1, chainId, commitTime
            ));
            
            vm.prank(user1);
            kaisign.revealSpec{value: MIN_BOND}(commitmentId, blobHash, blobHash, nonce);
            
            vm.warp(block.timestamp + 1);
        }
        
        // Check each chain has 1 spec
        assertEq(kaisign.getContractSpecCount(target1, 1), 1);
        assertEq(kaisign.getContractSpecCount(target1, 2), 1);
        assertEq(kaisign.getContractSpecCount(target1, 3), 1);
    }
}