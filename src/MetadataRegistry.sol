// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MetadataRegistry is ReentrancyGuard {
    // =============================================================================
    //                                CUSTOM ERRORS
    // =============================================================================
    error InvalidThreshold();
    error InvalidAttesterList();
    error AlreadyAttested();
    error DuplicateAttester();
    error EmptyMetadataHash();
    error MustIncludeRequirementNotMet();
    
    // =============================================================================
    //                              STATE VARIABLES
    // =============================================================================
    
    // Global attestations tracking
    mapping(bytes32 => mapping(address => bool)) public hasAttested;
    mapping(bytes32 => address[]) public metadataAttesters;
    mapping(bytes32 => uint256) public attestationCount;
    
    // Per-account trusted attesters configuration
    struct TrustedAttestersConfig {
        address[] attesters;
        uint256 threshold;
        address[] mustIncludeAny;  // At least one of these must attest
        address[] mustIncludeAll;  // All of these must attest
        bool isConfigured;
    }
    
    mapping(address => TrustedAttestersConfig) public accountConfigs;
    
    // =============================================================================
    //                                  EVENTS
    // =============================================================================
    event MetadataAttested(
        bytes32 indexed metadataHash,
        address indexed attester,
        uint256 timestamp
    );
    
    event TrustedAttestersUpdated(
        address indexed account,
        address[] attesters,
        uint256 threshold,
        address[] mustIncludeAny,
        address[] mustIncludeAll
    );
    
    // =============================================================================
    //                               CONSTRUCTOR
    // =============================================================================
    constructor() {}
    
    // =============================================================================
    //                           ATTESTATION FUNCTIONS
    // =============================================================================
    
    function attestMetadata(bytes32 metadataHash) external nonReentrant {
        if (metadataHash == bytes32(0)) revert EmptyMetadataHash();
        if (hasAttested[metadataHash][msg.sender]) revert AlreadyAttested();
        
        // The attester is signing that they approve this specific metadataHash
        // The metadataHash should be included in their signed payload to prevent
        // attesters from accidentally approving unintended metadata
        hasAttested[metadataHash][msg.sender] = true;
        metadataAttesters[metadataHash].push(msg.sender);
        attestationCount[metadataHash]++;
        
        emit MetadataAttested(metadataHash, msg.sender, block.timestamp);
    }
    
    function attestMetadataBatch(bytes32[] calldata metadataHashes) external nonReentrant {
        
        for (uint256 i = 0; i < metadataHashes.length; i++) {
            bytes32 metadataHash = metadataHashes[i];
            
            if (metadataHash == bytes32(0)) revert EmptyMetadataHash();
            if (hasAttested[metadataHash][msg.sender]) continue; // Skip if already attested
            
            hasAttested[metadataHash][msg.sender] = true;
            metadataAttesters[metadataHash].push(msg.sender);
            attestationCount[metadataHash]++;
            
            emit MetadataAttested(metadataHash, msg.sender, block.timestamp);
        }
    }
    
    // =============================================================================
    //                        ACCOUNT CONFIGURATION FUNCTIONS
    // =============================================================================
    
    function trustAttesters(
        uint256 threshold,
        address[] calldata attesters,
        address[] calldata mustIncludeAny,
        address[] calldata mustIncludeAll
    ) external {
        if (attesters.length == 0) revert InvalidAttesterList();
        if (threshold == 0 || threshold > attesters.length) revert InvalidThreshold();
        
        // Check for duplicates in attesters list
        for (uint256 i = 0; i < attesters.length; i++) {
            for (uint256 j = i + 1; j < attesters.length; j++) {
                if (attesters[i] == attesters[j]) revert DuplicateAttester();
            }
        }
        
        // Validate mustInclude lists are subsets of attesters
        for (uint256 i = 0; i < mustIncludeAny.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < attesters.length; j++) {
                if (mustIncludeAny[i] == attesters[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) revert InvalidAttesterList();
        }
        
        for (uint256 i = 0; i < mustIncludeAll.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < attesters.length; j++) {
                if (mustIncludeAll[i] == attesters[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) revert InvalidAttesterList();
        }
        
        accountConfigs[msg.sender] = TrustedAttestersConfig({
            attesters: attesters,
            threshold: threshold,
            mustIncludeAny: mustIncludeAny,
            mustIncludeAll: mustIncludeAll,
            isConfigured: true
        });
        
        emit TrustedAttestersUpdated(
            msg.sender,
            attesters,
            threshold,
            mustIncludeAny,
            mustIncludeAll
        );
    }
    
    // =============================================================================
    //                           VERIFICATION FUNCTIONS
    // =============================================================================
    
    /**
     * @notice Check if a metadata hash is approved for the calling account
     * @dev This checks if the specified attesters for this account have attested to this metadataHash
     * @param metadataHash The hash of the metadata to check
     * @return bool True if the metadata is approved by the required attesters
     */
    function approved(bytes32 metadataHash) external view returns (bool) {
        return approvedForAccount(metadataHash, msg.sender);
    }
    
    /**
     * @notice Check if a metadata hash is approved for a specific account
     * @dev The metadata hash must have been attested by the account's specified attesters
     *      This ensures that:
     *      1. Only metadata attested by the account's trusted attesters is approved
     *      2. The attesters explicitly signed this specific metadataHash
     *      3. The threshold and requirements are met
     * @param metadataHash The hash of the metadata to verify
     * @param account The account address to check approval for
     * @return bool True if approved according to account's requirements
     */
    function approvedForAccount(
        bytes32 metadataHash,
        address account
    ) public view returns (bool) {
        TrustedAttestersConfig storage config = accountConfigs[account];
        
        // If account hasn't configured trusted attesters, return false
        if (!config.isConfigured) {
            return false;
        }
        
        // Count valid attestations from the account's trusted attesters only
        // This ensures we only accept metadataHashes that were explicitly
        // attested by the attesters this account trusts
        uint256 validAttestations = 0;
        for (uint256 i = 0; i < config.attesters.length; i++) {
            if (hasAttested[metadataHash][config.attesters[i]]) {
                validAttestations++;
            }
        }
        
        // Check if threshold is met
        if (validAttestations < config.threshold) {
            return false;
        }
        
        // Check mustIncludeAll requirement - all specified attesters must have attested
        for (uint256 i = 0; i < config.mustIncludeAll.length; i++) {
            if (!hasAttested[metadataHash][config.mustIncludeAll[i]]) {
                return false;
            }
        }
        
        // Check mustIncludeAny requirement - at least one must have attested
        if (config.mustIncludeAny.length > 0) {
            bool foundAny = false;
            for (uint256 i = 0; i < config.mustIncludeAny.length; i++) {
                if (hasAttested[metadataHash][config.mustIncludeAny[i]]) {
                    foundAny = true;
                    break;
                }
            }
            if (!foundAny) {
                return false;
            }
        }
        
        return true;
    }
    
    // =============================================================================
    //                              QUERY FUNCTIONS
    // =============================================================================
    
    function getMetadataAttesters(bytes32 metadataHash) 
        external 
        view 
        returns (address[] memory) 
    {
        return metadataAttesters[metadataHash];
    }
    
    function getAccountConfig(address account) 
        external 
        view 
        returns (
            address[] memory attesters,
            uint256 threshold,
            address[] memory mustIncludeAny,
            address[] memory mustIncludeAll,
            bool isConfigured
        ) 
    {
        TrustedAttestersConfig storage config = accountConfigs[account];
        return (
            config.attesters,
            config.threshold,
            config.mustIncludeAny,
            config.mustIncludeAll,
            config.isConfigured
        );
    }
}
