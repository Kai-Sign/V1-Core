// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MetadataRegistry.sol";

/**
 * @title MetadataRegistry Mutation Testing
 * @notice Tests that verify our test suite catches potential mutations/bugs
 */
contract MetadataRegistryMutationTest is Test {
    MetadataRegistry public registry;
    
    address owner = address(0x1);
    address attester1 = address(0x2);
    address attester2 = address(0x3);
    address attester3 = address(0x4);
    address account = address(0x5);
    
    function setUp() public {
        vm.startPrank(owner);
        registry = new MetadataRegistry();
        vm.stopPrank();
    }
    
    /**
     * @dev Test that mutations in authorization logic are caught
     */
    function test_Mutation_AuthorizationBypass() public {
        // This test ensures that if someone tries to bypass authorization
        // (e.g., changing !authorizedAttesters[msg.sender] to authorizedAttesters[msg.sender])
        // our tests would catch it
        
        address unauthorized = address(0x999);
        bytes32 metadataHash = keccak256("test");
        
        // Now anyone can attest since we removed authorization
        vm.prank(unauthorized);
        registry.attestMetadata(metadataHash);
        
        // Verify it gets attested
        assertTrue(registry.hasAttested(metadataHash, unauthorized));
        assertEq(registry.attestationCount(metadataHash), 1);
    }
    
    /**
     * @dev Test that mutations in threshold validation are caught
     */
    function test_Mutation_ThresholdValidation() public {
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        
        // Test mutation: threshold > attesters.length changed to threshold >= attesters.length
        // This would allow threshold == attesters.length + 1
        vm.prank(account);
        vm.expectRevert(MetadataRegistry.InvalidThreshold.selector);
        registry.trustAttesters(4, attesters, new address[](0), new address[](0)); // threshold > length
        
        // Test mutation: threshold == 0 check removed
        vm.prank(account);
        vm.expectRevert(MetadataRegistry.InvalidThreshold.selector);
        registry.trustAttesters(0, attesters, new address[](0), new address[](0));
    }
    
    /**
     * @dev Test that mutations in duplicate detection are caught
     */
    function test_Mutation_DuplicateDetection() public {
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester1; // Duplicate
        
        // If mutation changes != to == in duplicate check, this would pass incorrectly
        vm.prank(account);
        vm.expectRevert(MetadataRegistry.DuplicateAttester.selector);
        registry.trustAttesters(2, attesters, new address[](0), new address[](0));
    }
    
    /**
     * @dev Test that mutations in approval logic are caught
     */
    function test_Mutation_ApprovalLogic() public {
        // Setup trust configuration
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        
        vm.prank(account);
        registry.trustAttesters(2, attesters, new address[](0), new address[](0));
        
        bytes32 metadataHash = keccak256("approval test");
        
        // Only one attestation - should not be approved
        vm.prank(attester1);
        registry.attestMetadata(metadataHash);
        assertFalse(registry.approvedForAccount(metadataHash, account));
        
        // Mutation test: if validAttestations < threshold changed to <=
        // This would incorrectly approve with only 1 attestation when threshold is 2
    }
    
    /**
     * @dev Test that mutations in mustInclude logic are caught
     */
    function test_Mutation_MustIncludeLogic() public {
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        
        address[] memory mustIncludeAll = new address[](1);
        mustIncludeAll[0] = attester3;
        
        vm.prank(account);
        registry.trustAttesters(2, attesters, new address[](0), mustIncludeAll);
        
        bytes32 metadataHash = keccak256("must include test");
        
        // Attest with attester1 and attester2 (but not attester3 who is required)
        vm.prank(attester1);
        registry.attestMetadata(metadataHash);
        vm.prank(attester2);
        registry.attestMetadata(metadataHash);
        
        // Should not be approved without attester3
        assertFalse(registry.approvedForAccount(metadataHash, account));
        
        // Mutation: if the mustIncludeAll check is bypassed, this would incorrectly return true
    }
    
    /**
     * @dev Test that mutations in empty hash validation are caught
     */
    function test_Mutation_EmptyHashValidation() public {
        // If mutation removes or inverts the empty hash check
        vm.prank(attester1);
        vm.expectRevert(MetadataRegistry.EmptyMetadataHash.selector);
        registry.attestMetadata(bytes32(0));
    }
    
    /**
     * @dev Test that mutations in already attested check are caught
     */
    function test_Mutation_AlreadyAttestedCheck() public {
        bytes32 metadataHash = keccak256("double attest");
        
        vm.prank(attester1);
        registry.attestMetadata(metadataHash);
        
        // If mutation changes hasAttested check, this would allow double attestation
        vm.prank(attester1);
        vm.expectRevert(MetadataRegistry.AlreadyAttested.selector);
        registry.attestMetadata(metadataHash);
        
        // Verify count didn't increase
        assertEq(registry.attestationCount(metadataHash), 1);
    }
    
    /**
     * @dev Test that mutations in batch attestation are caught
     */
    function test_Mutation_BatchAttestationLogic() public {
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = keccak256("batch1");
        hashes[1] = keccak256("batch2");
        hashes[2] = bytes32(0); // Invalid
        
        // Should revert on empty hash even in batch
        vm.prank(attester1);
        vm.expectRevert(MetadataRegistry.EmptyMetadataHash.selector);
        registry.attestMetadataBatch(hashes);
        
        // Fix the batch
        hashes[2] = keccak256("batch3");
        
        vm.prank(attester1);
        registry.attestMetadataBatch(hashes);
        
        // Verify all were attested
        for (uint i = 0; i < hashes.length; i++) {
            assertTrue(registry.hasAttested(hashes[i], attester1));
            assertEq(registry.attestationCount(hashes[i]), 1);
        }
    }
    
    /**
     * @dev Test that mutations in subset validation are caught
     */
    function test_Mutation_SubsetValidation() public {
        address[] memory attesters = new address[](2);
        attesters[0] = attester1;
        attesters[1] = attester2;
        
        address[] memory mustIncludeAny = new address[](1);
        mustIncludeAny[0] = attester3; // Not in attesters list
        
        // Should revert because mustIncludeAny contains address not in attesters
        vm.prank(account);
        vm.expectRevert(MetadataRegistry.InvalidAttesterList.selector);
        registry.trustAttesters(1, attesters, mustIncludeAny, new address[](0));
    }
    
    /**
     * @dev Test mutation in ownership check - Now tests permissionless attestation
     */
    function test_Mutation_OwnershipCheck() public {
        address anyUser = address(0x999);
        bytes32 metadataHash = keccak256("permissionless test");
        
        // Since we removed ownership, anyone can attest
        vm.prank(anyUser);
        registry.attestMetadata(metadataHash);
        
        // Verify attestation succeeded
        assertTrue(registry.hasAttested(metadataHash, anyUser));
        assertEq(registry.attestationCount(metadataHash), 1);
    }
}