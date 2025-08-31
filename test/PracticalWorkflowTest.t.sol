// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/KaiSign.sol";
import "../staticlib/RealityETH-3.0.sol";

/**
 * @title Practical End-to-End Workflow Test
 * @dev Demonstrates a complete real-world KaiSign workflow with ERC-7730 metadata
 */
contract PracticalWorkflowTest is Test {
    KaiSign kaisign;
    RealityETH_v3_0 realityETH;
    
    // Different addresses for different roles
    address admin = address(0x1);           // Contract administrator
    address incentiveCreator = address(0x2); // Company/DAO creating incentive
    address metadataProvider = address(0x3); // Metadata spec author
    address arbitrator = address(0x6);       // Reality.eth arbitrator
    address treasury = address(0x7);         // Platform treasury
    address voter1 = address(0x8);           // Reality.eth voter 1
    address voter2 = address(0x9);           // Reality.eth voter 2
    
    // Target contract we want metadata for
    address testTarget = address(0x1234567890123456789012345678901234567890);
    uint256 targetChainId = 1; // Ethereum mainnet
    
    uint256 constant MIN_BOND = 0.01 ether;
    uint256 constant INCENTIVE_AMOUNT = 5 ether;
    
    // Real ERC-7730 metadata for KaiSign contract
    string constant ERC7730_KAISIGN_METADATA = '{"metadata":{"name":"KaiSign Protocol","description":"Clear signing metadata for decentralized contract verification","version":"1.0.0","chainId":1},"display":{"formats":{"createIncentive":[{"label":"Create Incentive","fields":[{"path":"targetContract","label":"Target Contract","format":"address"},{"path":"amount","label":"Incentive Amount","format":"amount"}],"primary":["targetContract","amount"]}],"proposeSpec":[{"label":"Propose Specification","fields":[{"path":"specId","label":"Specification ID","format":"bytes32"}],"primary":["specId"]}],"handleResult":[{"label":"Handle Result","fields":[{"path":"specId","label":"Specification ID","format":"bytes32"},{"path":"accepted","label":"Specification Accepted","format":"bool"}],"primary":["specId","accepted"]}]}}}';
    
    // Blob hash for the metadata (would be real blob hash in practice)
    string constant METADATA_BLOB = "QmKaiSignERC7730MetadataV1HashExampleFor32CharactersMin";
    
    // Calculate the actual metadata hash
    bytes32 constant METADATA_HASH = bytes32(keccak256(bytes(ERC7730_KAISIGN_METADATA)));
    
    event WorkflowStep(string step, address actor, string details);
    
    function setUp() public {
        // Deploy contracts
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
        
        // Fund all participants
        vm.deal(incentiveCreator, 100 ether);
        vm.deal(metadataProvider, 10 ether);
        vm.deal(voter1, 1 ether);
        vm.deal(voter2, 1 ether);
        vm.deal(arbitrator, 1 ether);
        
        console.log("=== KAISIGN PRACTICAL WORKFLOW TEST ===");
        console.log("Target Contract:", testTarget);
        console.log("Incentive Amount:", INCENTIVE_AMOUNT);
        console.log("Metadata Blob:", METADATA_BLOB);
        console.logBytes32(METADATA_HASH);
    }
    
    function testCompleteWorkflow() public {
        console.log("\n=== STEP 1: INCENTIVE CREATOR CREATES INCENTIVE ===");
        
        // Step 1: Incentive Creator creates an incentive for target contract metadata
        vm.startPrank(incentiveCreator);
        
        bytes32 incentiveId = kaisign.createIncentive{value: INCENTIVE_AMOUNT}(
            testTarget,
            targetChainId,
            INCENTIVE_AMOUNT,
            30 days,
            "ERC-7730 clear signing metadata for DeFi protocol integration"
        );
        
        vm.stopPrank();
        
        emit WorkflowStep(
            "Incentive Created", 
            incentiveCreator, 
            "5 ETH incentive for target contract metadata"
        );
        
        // Verify incentive was created
        (
            address creator,
            uint80 amount,
            ,
            ,
            ,
            address target,
            bool isClaimed,
            bool isActive,
            uint256 chainId,
            string memory description
        ) = kaisign.incentives(incentiveId);
        
        assertEq(creator, incentiveCreator);
        assertEq(uint256(amount), INCENTIVE_AMOUNT);
        assertEq(target, testTarget);
        assertEq(chainId, targetChainId);
        assertFalse(isClaimed);
        assertTrue(isActive);
        
        console.log("[OK] Incentive created with ID:");
        console.logBytes32(incentiveId);
        console.log("[OK] Description:", description);
        
        console.log("\n=== STEP 2: METADATA PROVIDER COMMITS SPEC ===");
        
        // Step 2: Metadata Provider commits their metadata specification
        vm.startPrank(metadataProvider);
        
        // Create commitment hash from blob and nonce
        uint256 nonce = 12345;
        bytes32 blobHash = keccak256(abi.encodePacked(METADATA_BLOB));
        bytes32 metadataHash = keccak256(abi.encodePacked(METADATA_BLOB, "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        // Record logs to capture commitment ID
        vm.recordLogs();
        
        kaisign.commitSpec(commitment, testTarget, targetChainId);
        
        // Get commitment ID from event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 commitmentId = logs[0].topics[2];
        
        vm.stopPrank();
        
        emit WorkflowStep(
            "Spec Committed", 
            metadataProvider, 
            "Metadata specification committed with commitment-reveal scheme"
        );
        
        console.log("[OK] Commitment created with ID:");
        console.logBytes32(commitmentId);
        console.log("[OK] Commitment hash:");
        console.logBytes32(commitment);
        
        console.log("\n=== STEP 3: METADATA PROVIDER REVEALS SPEC ===");
        
        // Step 3: Wait for reveal period and reveal the specification
        vm.warp(block.timestamp + 1 hours); // Wait for reveal period
        
        vm.startPrank(metadataProvider);
        
        // Reveal with blob hash and metadata hash
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(
            commitmentId,
            blobHash,
            metadataHash,
            nonce
        );
        
        vm.stopPrank();
        
        emit WorkflowStep(
            "Spec Revealed", 
            metadataProvider, 
            "ERC-7730 metadata revealed and automatically proposed to Reality.eth"
        );
        
        // Verify spec was created and proposed
        (
            ,
            ,
            KaiSign.Status status,
            uint80 totalBonds,
            ,
            address specCreator,
            address specTarget,
            bytes32 blobHashFromSpec,
            bytes32 questionId,
            ,
            uint256 specChainId
        ) = kaisign.specs(specId);
        
        assertEq(specCreator, metadataProvider);
        assertEq(specTarget, testTarget);
        assertEq(blobHashFromSpec, blobHash);
        assertEq(specChainId, targetChainId);
        assertEq(uint256(status), uint256(KaiSign.Status.Proposed));
        assertEq(uint256(totalBonds), MIN_BOND);
        assertTrue(questionId != bytes32(0)); // Question should be created
        
        console.log("[OK] Spec revealed with ID:");
        console.logBytes32(specId);
        console.log("[OK] Reality.eth question ID:");
        console.logBytes32(questionId);
        console.log("[OK] Blob hash:");
        console.logBytes32(blobHashFromSpec);
        
        console.log("\n=== STEP 4: BLOB DATA STORED ON-CHAIN ===");
        
        // Step 4: Blob hash and metadata hash are now stored on-chain
        // This replaces the need for attestation registry
        
        emit WorkflowStep(
            "Blob Data Stored", 
            metadataProvider, 
            "ERC-7730 metadata stored via blob storage"
        );
        
        console.log("[OK] Blob hash stored on-chain");
        console.log("[OK] Metadata hash stored on-chain");
        
        console.log("\n=== STEP 5: COMMUNITY VOTING ON REALITY.ETH ===");
        
        // Step 5: Simulate community voting on Reality.eth
        // In practice, this would involve real economic voting with bonds
        
        vm.startPrank(voter1);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0); // Vote YES (1)
        vm.stopPrank();
        
        vm.startPrank(voter2);
        realityETH.submitAnswer{value: MIN_BOND * 2}(questionId, bytes32(uint256(1)), MIN_BOND); // Vote YES (1) - needs to double previous bond
        vm.stopPrank();
        
        // Wait for Reality.eth timeout period to pass (2 days default)
        vm.warp(block.timestamp + 172800 + 1);
        
        emit WorkflowStep(
            "Reality.eth Voting", 
            arbitrator, 
            "Community voted YES - metadata specification accepted"
        );
        
        // Verify question is finalized with positive result
        assertTrue(realityETH.isFinalized(questionId));
        bytes32 result = realityETH.resultFor(questionId);
        assertEq(uint256(result), 1); // Should be YES
        
        console.log("[OK] Reality.eth question finalized");
        console.log("[OK] Community vote result: ACCEPTED");
        
        console.log("\n=== STEP 6: HANDLE RESULT AND CLAIM INCENTIVE ===");
        
        // Step 6: Handle the result and claim the incentive
        vm.startPrank(metadataProvider);
        
        // Record balances before
        uint256 providerBalanceBefore = metadataProvider.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        kaisign.handleResult(specId);
        
        // Record balances after
        uint256 providerBalanceAfter = metadataProvider.balance;
        uint256 treasuryBalanceAfter = treasury.balance;
        
        vm.stopPrank();
        
        emit WorkflowStep(
            "Result Handled", 
            metadataProvider, 
            "Incentive claimed and distributed"
        );
        
        // Verify final state
        (, , KaiSign.Status finalStatus, , , , , , , , ) = kaisign.specs(specId);
        assertEq(uint256(finalStatus), uint256(KaiSign.Status.Finalized));
        
        // Verify incentive pool was claimed (should now be empty)
        (uint256 poolAmountAfter, ) = kaisign.getIncentivePool(testTarget, targetChainId);
        assertEq(poolAmountAfter, 0); // Pool should be empty after claiming
        
        // Calculate expected payouts (95% to provider, 5% platform fee)
        uint256 expectedProviderPayout = (INCENTIVE_AMOUNT * 95) / 100;
        uint256 expectedPlatformFee = (INCENTIVE_AMOUNT * 5) / 100;
        
        // Verify payouts (provider gets payout + bond back)
        uint256 providerPayout = providerBalanceAfter - providerBalanceBefore;
        uint256 treasuryPayout = treasuryBalanceAfter - treasuryBalanceBefore;
        
        // The provider gets the incentive payout (bond handling depends on implementation)
        assertEq(providerPayout, expectedProviderPayout);
        assertEq(treasuryPayout, expectedPlatformFee);
        
        console.log("[OK] Spec finalized with ACCEPTED status");
        console.log("[OK] Incentive claimed successfully");
        console.log("[OK] Provider received:", providerPayout);
        console.log("[OK] Treasury received:", treasuryPayout);
        
        console.log("\n=== WORKFLOW COMPLETED SUCCESSFULLY ===");
        console.log("SUMMARY:");
        console.log("- Target contract now has verified ERC-7730 metadata");
        console.log("- Metadata is stored on-chain via blob storage");
        console.log("- Community validated the specification quality");
        console.log("- Economic incentives properly distributed");
        console.log("- Clear signing enabled for DeFi integration");
        
        // Final verification - demonstrate the metadata can be used
        console.log("\n=== METADATA VERIFICATION ===");
        console.log("ERC-7730 Metadata Content:");
        console.log(ERC7730_KAISIGN_METADATA);
        console.log("\nBlob Reference:", METADATA_BLOB);
        console.log("Blob hash stored on-chain: TRUE");
        console.log("Specification Finalized: TRUE");
    }
    
    function testIncentiveFailureScenario() public {
        console.log("\n=== ALTERNATIVE SCENARIO: SPECIFICATION REJECTED ===");
        
        // Create incentive
        vm.startPrank(incentiveCreator);
        bytes32 incentiveId = kaisign.createIncentive{value: INCENTIVE_AMOUNT}(
            testTarget,
            targetChainId,
            INCENTIVE_AMOUNT,
            30 days,
            "Poor quality metadata specification example"
        );
        vm.stopPrank();
        
        // Commit and reveal poor quality spec
        vm.startPrank(metadataProvider);
        uint256 nonce = 54321;
        bytes32 blobHash = keccak256(abi.encodePacked("QmPoorQualitySpec123"));
        bytes32 metadataHash = keccak256(abi.encodePacked("QmPoorQualitySpec123", "metadata"));
        bytes32 commitment = keccak256(abi.encodePacked(metadataHash, nonce));
        
        vm.recordLogs();
        kaisign.commitSpec(commitment, testTarget, targetChainId);
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 commitmentId = logs[0].topics[2];
        
        vm.warp(block.timestamp + 1 hours);
        
        bytes32 specId = kaisign.revealSpec{value: MIN_BOND}(
            commitmentId,
            blobHash,
            metadataHash,
            nonce
        );
        
        vm.stopPrank();
        
        // Community rejects the specification
        (, , , , , , , , bytes32 questionId, , ) = kaisign.specs(specId);
        
        // The question needs to be created in RealityETH first
        // This happens when the spec is proposed - let's ensure it exists
        assertTrue(questionId != bytes32(0), "Question ID should exist");
        
        vm.startPrank(voter1);
        // First parameter is questionId, not blobHash
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(0)), 0); // Vote NO (0)
        vm.stopPrank();
        
        // Wait for Reality.eth timeout period to pass (2 days default)
        vm.warp(block.timestamp + 172800 + 1);
        
        // Handle rejected result
        vm.startPrank(metadataProvider);
        uint256 providerBalanceBefore = metadataProvider.balance;
        
        kaisign.handleResult(specId);
        
        uint256 providerBalanceAfter = metadataProvider.balance;
        vm.stopPrank();
        
        // Verify spec was rejected and incentive remains unclaimed
        (, , KaiSign.Status finalStatus, , , , , , , , ) = kaisign.specs(specId);
        assertEq(uint256(finalStatus), uint256(KaiSign.Status.Finalized));
        
        // Verify incentive pool remains unclaimed (should still have the original amount)
        (uint256 poolAmountAfter, ) = kaisign.getIncentivePool(testTarget, targetChainId);
        assertEq(poolAmountAfter, INCENTIVE_AMOUNT); // Pool should still contain the incentive
        
        // Provider should get no payout when rejected (no incentive claimed)
        uint256 providerPayout = providerBalanceAfter - providerBalanceBefore;
        assertEq(providerPayout, 0); // No payout when rejected
        
        console.log("[OK] Poor specification rejected by community");
        console.log("[OK] Incentive remains available for better submissions");
        console.log("[OK] No payout when specification rejected");
        
        emit WorkflowStep(
            "Spec Rejected", 
            metadataProvider, 
            "Community rejected poor quality specification"
        );
    }
}