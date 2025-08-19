// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MetadataRegistry.sol";

contract MetadataRegistryTest is Test {
    MetadataRegistry public registry;
    
    address owner = address(0x1);
    address attester1 = address(0x2);
    address attester2 = address(0x3);
    address attester3 = address(0x4);
    address account = address(0x5);
    address unauthorized = address(0x6);
    
    bytes32 constant TEST_HASH = keccak256("test_metadata");
    bytes32 constant EMPTY_HASH = bytes32(0);
    
    event MetadataAttested(bytes32 indexed metadataHash, address indexed attester, uint256 timestamp);
    event AttesterAuthorized(address indexed attester);
    event AttesterRevoked(address indexed attester);
    event TrustedAttestersUpdated(
        address indexed account,
        address[] attesters,
        uint256 threshold,
        address[] mustIncludeAny,
        address[] mustIncludeAll
    );
    
    function setUp() public {
        registry = new MetadataRegistry();
    }
    
    // =============================================================================
    //                              ATTESTATION TESTS
    // =============================================================================
    
    function testAttestMetadata() public {
        vm.startPrank(attester1);
        
        vm.expectEmit(true, true, false, true);
        emit MetadataAttested(TEST_HASH, attester1, block.timestamp);
        
        registry.attestMetadata(TEST_HASH);
        
        assertTrue(registry.hasAttested(TEST_HASH, attester1));
        assertEq(registry.attestationCount(TEST_HASH), 1);
        
        address[] memory attesters = registry.getMetadataAttesters(TEST_HASH);
        assertEq(attesters.length, 1);
        assertEq(attesters[0], attester1);
        
        vm.stopPrank();
    }
    
    function testCannotAttestTwice() public {
        vm.startPrank(attester1);
        
        registry.attestMetadata(TEST_HASH);
        
        vm.expectRevert(MetadataRegistry.AlreadyAttested.selector);
        registry.attestMetadata(TEST_HASH);
        
        vm.stopPrank();
    }
    
    function testCannotAttestEmptyHash() public {
        vm.startPrank(attester1);
        
        vm.expectRevert(MetadataRegistry.EmptyMetadataHash.selector);
        registry.attestMetadata(EMPTY_HASH);
        
        vm.stopPrank();
    }
    
    function testAnyoneCanAttest() public {
        vm.startPrank(unauthorized);
        
        registry.attestMetadata(TEST_HASH);
        
        assertTrue(registry.hasAttested(TEST_HASH, unauthorized));
        assertEq(registry.attestationCount(TEST_HASH), 1);
        
        vm.stopPrank();
    }
    
    function testAttestMetadataBatch() public {
        vm.startPrank(attester1);
        
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = keccak256("hash1");
        hashes[1] = keccak256("hash2");
        hashes[2] = keccak256("hash3");
        
        registry.attestMetadataBatch(hashes);
        
        for (uint256 i = 0; i < hashes.length; i++) {
            assertTrue(registry.hasAttested(hashes[i], attester1));
            assertEq(registry.attestationCount(hashes[i]), 1);
        }
        
        vm.stopPrank();
    }
    
    function testBatchAttestSkipsAlreadyAttested() public {
        vm.startPrank(attester1);
        
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = keccak256("hash1");
        hashes[1] = keccak256("hash2");
        
        // First attestation
        registry.attestMetadata(hashes[0]);
        
        // Batch including already attested
        registry.attestMetadataBatch(hashes);
        
        // Should not double count
        assertEq(registry.attestationCount(hashes[0]), 1);
        assertEq(registry.attestationCount(hashes[1]), 1);
        
        vm.stopPrank();
    }
    
    // =============================================================================
    //                          PROJECT CONFIGURATION TESTS
    // =============================================================================
    
    function testTrustAttesters() public {
        vm.startPrank(account);
        
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        
        address[] memory mustIncludeAny = new address[](2);
        mustIncludeAny[0] = attester1;
        mustIncludeAny[1] = attester2;
        
        address[] memory mustIncludeAll = new address[](1);
        mustIncludeAll[0] = attester3;
        
        vm.expectEmit(true, false, false, true);
        emit TrustedAttestersUpdated(account, attesters, 2, mustIncludeAny, mustIncludeAll);
        
        registry.trustAttesters(2, attesters, mustIncludeAny, mustIncludeAll);
        
        (
            address[] memory configAttesters,
            uint256 threshold,
            address[] memory configMustAny,
            address[] memory configMustAll,
            bool isConfigured
        ) = registry.getAccountConfig(account);
        
        assertEq(configAttesters.length, 3);
        assertEq(threshold, 2);
        assertEq(configMustAny.length, 2);
        assertEq(configMustAll.length, 1);
        assertTrue(isConfigured);
        
        vm.stopPrank();
    }
    
    function testCannotSetInvalidThreshold() public {
        vm.startPrank(account);
        
        address[] memory attesters = new address[](2);
        attesters[0] = attester1;
        attesters[1] = attester2;
        
        address[] memory empty = new address[](0);
        
        // Threshold > attesters length
        vm.expectRevert(MetadataRegistry.InvalidThreshold.selector);
        registry.trustAttesters(3, attesters, empty, empty);
        
        // Threshold = 0
        vm.expectRevert(MetadataRegistry.InvalidThreshold.selector);
        registry.trustAttesters(0, attesters, empty, empty);
        
        vm.stopPrank();
    }
    
    function testCannotSetEmptyAttestersList() public {
        vm.startPrank(account);
        
        address[] memory empty = new address[](0);
        
        vm.expectRevert(MetadataRegistry.InvalidAttesterList.selector);
        registry.trustAttesters(1, empty, empty, empty);
        
        vm.stopPrank();
    }
    
    function testCannotSetDuplicateAttesters() public {
        vm.startPrank(account);
        
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester1; // Duplicate
        
        address[] memory empty = new address[](0);
        
        vm.expectRevert(MetadataRegistry.DuplicateAttester.selector);
        registry.trustAttesters(2, attesters, empty, empty);
        
        vm.stopPrank();
    }
    
    function testMustIncludeValidation() public {
        vm.startPrank(account);
        
        address[] memory attesters = new address[](2);
        attesters[0] = attester1;
        attesters[1] = attester2;
        
        address[] memory invalidMustInclude = new address[](1);
        invalidMustInclude[0] = attester3; // Not in attesters list
        
        address[] memory empty = new address[](0);
        
        vm.expectRevert(MetadataRegistry.InvalidAttesterList.selector);
        registry.trustAttesters(1, attesters, invalidMustInclude, empty);
        
        vm.expectRevert(MetadataRegistry.InvalidAttesterList.selector);
        registry.trustAttesters(1, attesters, empty, invalidMustInclude);
        
        vm.stopPrank();
    }
    
    // =============================================================================
    //                           VERIFICATION TESTS
    // =============================================================================
    
    function testApprovedWithThreshold() public {
        // Setup account config
        vm.startPrank(account);
        
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        
        address[] memory empty = new address[](0);
        
        registry.trustAttesters(2, attesters, empty, empty);
        vm.stopPrank();
        
        // Not enough attestations
        vm.prank(attester1);
        registry.attestMetadata(TEST_HASH);
        assertFalse(registry.approvedForAccount(TEST_HASH, account));
        
        // Meets threshold
        vm.prank(attester2);
        registry.attestMetadata(TEST_HASH);
        assertTrue(registry.approvedForAccount(TEST_HASH, account));
        
        // Still approved with more attestations
        vm.prank(attester3);
        registry.attestMetadata(TEST_HASH);
        assertTrue(registry.approvedForAccount(TEST_HASH, account));
    }
    
    function testApprovedWithMustIncludeAll() public {
        // Setup account config
        vm.startPrank(account);
        
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        
        address[] memory empty = new address[](0);
        address[] memory mustIncludeAll = new address[](1);
        mustIncludeAll[0] = attester3;
        
        registry.trustAttesters(2, attesters, empty, mustIncludeAll);
        vm.stopPrank();
        
        // Meet threshold but not mustIncludeAll
        vm.prank(attester1);
        registry.attestMetadata(TEST_HASH);
        vm.prank(attester2);
        registry.attestMetadata(TEST_HASH);
        assertFalse(registry.approvedForAccount(TEST_HASH, account));
        
        // Now includes required attester
        vm.prank(attester3);
        registry.attestMetadata(TEST_HASH);
        assertTrue(registry.approvedForAccount(TEST_HASH, account));
    }
    
    function testApprovedWithMustIncludeAny() public {
        // Setup account config
        vm.startPrank(account);
        
        address[] memory attesters = new address[](3);
        attesters[0] = attester1;
        attesters[1] = attester2;
        attesters[2] = attester3;
        
        address[] memory mustIncludeAny = new address[](2);
        mustIncludeAny[0] = attester1;
        mustIncludeAny[1] = attester2;
        
        address[] memory empty = new address[](0);
        
        registry.trustAttesters(2, attesters, mustIncludeAny, empty);
        vm.stopPrank();
        
        // Meet threshold but not mustIncludeAny
        vm.prank(attester3);
        registry.attestMetadata(TEST_HASH);
        assertFalse(registry.approvedForAccount(TEST_HASH, account));
        
        // Now includes one of the required attesters
        vm.prank(attester1);
        registry.attestMetadata(TEST_HASH);
        assertTrue(registry.approvedForAccount(TEST_HASH, account));
    }
    
    function testApprovedReturnsMsgSender() public {
        // Setup account config
        vm.startPrank(account);
        
        address[] memory attesters = new address[](1);
        attesters[0] = attester1;
        
        address[] memory empty = new address[](0);
        
        registry.trustAttesters(1, attesters, empty, empty);
        
        // Attest
        vm.stopPrank();
        vm.prank(attester1);
        registry.attestMetadata(TEST_HASH);
        
        // Check using approved() which uses msg.sender
        vm.prank(account);
        assertTrue(registry.approved(TEST_HASH));
        
        // Different sender should return false (not configured)
        vm.prank(unauthorized);
        assertFalse(registry.approved(TEST_HASH));
    }
    
    function testNotConfiguredProjectReturnsFalse() public {
        vm.prank(attester1);
        registry.attestMetadata(TEST_HASH);
        
        // Project hasn't configured attesters
        assertFalse(registry.approvedForAccount(TEST_HASH, account));
    }
    
    // =============================================================================
    //                              FUZZ TESTS
    // =============================================================================
    
    function testFuzzAttestMetadata(bytes32 hash, address attester) public {
        vm.assume(hash != bytes32(0));
        vm.assume(attester != address(0));
        
        // Attest (no authorization needed anymore)
        vm.prank(attester);
        registry.attestMetadata(hash);
        
        assertTrue(registry.hasAttested(hash, attester));
        assertEq(registry.attestationCount(hash), 1);
    }
    
    function testFuzzTrustAttesters(uint8 numAttesters, uint8 threshold) public {
        vm.assume(numAttesters > 0 && numAttesters <= 10);
        vm.assume(threshold > 0 && threshold <= numAttesters);
        
        address[] memory attesters = new address[](numAttesters);
        for (uint256 i = 0; i < numAttesters; i++) {
            attesters[i] = address(uint160(i + 100));
        }
        
        address[] memory empty = new address[](0);
        
        vm.prank(account);
        registry.trustAttesters(threshold, attesters, empty, empty);
        
        (,uint256 configThreshold,,,) = registry.getAccountConfig(account);
        assertEq(configThreshold, threshold);
    }
}

// =============================================================================
//                    INVARIANT TESTS WITH HANDLER
// =============================================================================

import "forge-std/StdInvariant.sol";

contract MetadataRegistryInvariantTest is StdInvariant, Test {
    MetadataRegistry public registry;
    MetadataRegistryHandler public handler;
    
    address owner = address(0x1);
    address[] public attesters;
    address[] public accounts;
    
    function setUp() public {
        vm.startPrank(owner);
        registry = new MetadataRegistry();
        
        // Setup attesters
        for (uint i = 0; i < 5; i++) {
            address attester = makeAddr(string(abi.encodePacked("attester", i)));
            attesters.push(attester);
        }
        
        // Setup accounts
        for (uint i = 0; i < 3; i++) {
            address account = makeAddr(string(abi.encodePacked("account", i)));
            accounts.push(account);
        }
        
        vm.stopPrank();
        
        // Setup handler
        handler = new MetadataRegistryHandler(registry, attesters, accounts);
        targetContract(address(handler));
    }
    
    /**
     * @dev Invariant: Attestation count should match actual attesters array length
     */
    function invariant_AttestationCountConsistency() public view {
        bytes32[] memory testHashes = handler.getTestHashes();
        uint256 maxChecks = testHashes.length > 10 ? 10 : testHashes.length; // Limit checks
        for (uint i = 0; i < maxChecks; i++) {
            if (testHashes[i] != bytes32(0)) {
                address[] memory metadataAttesters = registry.getMetadataAttesters(testHashes[i]);
                assert(registry.attestationCount(testHashes[i]) == metadataAttesters.length);
            }
        }
    }
    
    
    /**
     * @dev Invariant: No duplicate attestations should exist
     */
    function invariant_NoDuplicateAttestations() public view {
        bytes32[] memory testHashes = handler.getTestHashes();
        uint256 maxHashes = testHashes.length > 3 ? 3 : testHashes.length; // Limit outer loop
        for (uint i = 0; i < maxHashes; i++) {
            if (testHashes[i] != bytes32(0)) {
                address[] memory metadataAttesters = registry.getMetadataAttesters(testHashes[i]);
                uint256 maxAttesters = metadataAttesters.length > 5 ? 5 : metadataAttesters.length; // Limit inner loops
                // Check for duplicates with bounded nested loops
                for (uint j = 0; j < maxAttesters; j++) {
                    for (uint k = j + 1; k < maxAttesters; k++) {
                        assert(metadataAttesters[j] != metadataAttesters[k]);
                    }
                }
            }
        }
    }
    
    /**
     * @dev Invariant: Threshold should never exceed attester count
     */
    function invariant_ThresholdValidity() public view {
        uint256 maxAccounts = accounts.length > 5 ? 5 : accounts.length; // Limit checks
        for (uint i = 0; i < maxAccounts; i++) {
            (address[] memory configAttesters, uint256 threshold,,, bool isConfigured) = registry.getAccountConfig(accounts[i]);
            address[] memory attesters = configAttesters;
            if (isConfigured) {
                assert(threshold <= attesters.length);
                assert(threshold > 0);
            }
        }
    }
    
    /**
     * @dev Invariant: Must include lists should be subsets of attesters
     */
    function invariant_MustIncludeSubsets() public view {
        uint256 maxAccounts = accounts.length > 3 ? 3 : accounts.length; // Limit outer loop
        for (uint i = 0; i < maxAccounts; i++) {
            (address[] memory configAttesters,, address[] memory mustIncludeAny, address[] memory mustIncludeAll, bool isConfigured) = registry.getAccountConfig(accounts[i]);
            address[] memory attesters = configAttesters;
            if (isConfigured) {
                // Check mustIncludeAny is subset (limit checks)
                uint256 maxAny = mustIncludeAny.length > 3 ? 3 : mustIncludeAny.length;
                for (uint j = 0; j < maxAny; j++) {
                    bool found = false;
                    uint256 maxAttesters = attesters.length > 5 ? 5 : attesters.length;
                    for (uint k = 0; k < maxAttesters; k++) {
                        if (mustIncludeAny[j] == attesters[k]) {
                            found = true;
                            break;
                        }
                    }
                    assert(found);
                }
                // Check mustIncludeAll is subset (limit checks)
                uint256 maxAll = mustIncludeAll.length > 3 ? 3 : mustIncludeAll.length;
                for (uint j = 0; j < maxAll; j++) {
                    bool found = false;
                    uint256 maxAttesters2 = attesters.length > 5 ? 5 : attesters.length;
                    for (uint k = 0; k < maxAttesters2; k++) {
                        if (mustIncludeAll[j] == attesters[k]) {
                            found = true;
                            break;
                        }
                    }
                    assert(found);
                }
            }
        }
    }
}

/**
 * @title Handler contract for MetadataRegistry invariant testing
 */
contract MetadataRegistryHandler is Test {
    MetadataRegistry public registry;
    address[] public attesters;
    address[] public accounts;
    bytes32[] public testHashes;
    
    mapping(bytes32 => bool) public hashExists;
    
    constructor(MetadataRegistry _registry, address[] memory _attesters, address[] memory _accounts) {
        registry = _registry;
        attesters = _attesters;
        accounts = _accounts;
    }
    
    function attestMetadata(uint256 attesterSeed, uint256 hashSeed) public {
        address attester = attesters[attesterSeed % attesters.length];
        bytes32 metadataHash = keccak256(abi.encodePacked("metadata", hashSeed % 100));
        
        if (!hashExists[metadataHash]) {
            testHashes.push(metadataHash);
            hashExists[metadataHash] = true;
        }
        
        vm.prank(attester);
        try registry.attestMetadata(metadataHash) {
            // Success
        } catch {
            // Already attested or other error
        }
    }
    
    function attestMetadataBatch(uint256 attesterSeed, uint256[] memory hashSeeds) public {
        if (hashSeeds.length == 0 || hashSeeds.length > 10) return;
        
        address attester = attesters[attesterSeed % attesters.length];
        bytes32[] memory hashes = new bytes32[](hashSeeds.length);
        
        for (uint i = 0; i < hashSeeds.length; i++) {
            bytes32 metadataHash = keccak256(abi.encodePacked("metadata", hashSeeds[i] % 100));
            hashes[i] = metadataHash;
            
            if (!hashExists[metadataHash]) {
                testHashes.push(metadataHash);
                hashExists[metadataHash] = true;
            }
        }
        
        vm.prank(attester);
        try registry.attestMetadataBatch(hashes) {
            // Success
        } catch {
            // Error in batch
        }
    }
    
    function trustAttesters(
        uint256 accountSeed,
        uint256 threshold,
        uint256 attesterCount,
        uint256 mustIncludeAnySeed,
        uint256 mustIncludeAllSeed
    ) public {
        if (attesterCount == 0 || attesterCount > attesters.length) return;
        
        address account = accounts[accountSeed % accounts.length];
        threshold = bound(threshold, 1, attesterCount);
        
        address[] memory selectedAttesters = new address[](attesterCount);
        for (uint i = 0; i < attesterCount; i++) {
            selectedAttesters[i] = attesters[i];
        }
        
        // Setup mustInclude arrays
        address[] memory mustIncludeAny;
        address[] memory mustIncludeAll;
        
        if (mustIncludeAnySeed % 3 == 0 && attesterCount > 0) {
            mustIncludeAny = new address[](1);
            mustIncludeAny[0] = selectedAttesters[0];
        } else {
            mustIncludeAny = new address[](0);
        }
        
        if (mustIncludeAllSeed % 3 == 0 && attesterCount > 1) {
            mustIncludeAll = new address[](1);
            mustIncludeAll[0] = selectedAttesters[1];
        } else {
            mustIncludeAll = new address[](0);
        }
        
        vm.prank(account);
        try registry.trustAttesters(threshold, selectedAttesters, mustIncludeAny, mustIncludeAll) {
            // Success
        } catch {
            // Invalid configuration
        }
    }
    
    function getTestHashes() public view returns (bytes32[] memory) {
        return testHashes;
    }
}
