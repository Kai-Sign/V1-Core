// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {KaiSign} from "../src/KaiSign.sol";
import {RealityETH_v3_0} from "../staticlib/RealityETH-3.0.sol";

contract BlobSpecTest is Test {
    KaiSign public kaisign;
    RealityETH_v3_0 public realityETH;
    
    address constant ARBITRATOR = address(0x1234);
    address constant TREASURY = address(0x5678);
    address constant USER = address(0x9ABC);
    address constant CONTRACT = address(0xDEF0);
    
    uint256 constant MIN_BOND = 0.01 ether;
    uint256 constant CHAIN_ID = 11155111; // Sepolia
    
    bytes32 constant SAMPLE_BLOB_HASH = keccak256("BLOB:metadata");
    
    event LogCommitSpec(
        address indexed committer,
        bytes32 indexed commitmentId,
        address indexed targetContract,
        uint256 chainId,
        uint256 bondAmount,
        uint64 revealDeadline
    );
    
    event LogRevealSpec(
        address indexed creator,
        bytes32 indexed specID,
        bytes32 indexed commitmentId,
        bytes32 blobHash,
        address targetContract,
        uint256 chainId
    );
    
    function setUp() public {
        // Deploy Reality.eth mock
        realityETH = new RealityETH_v3_0();
        
        // Deploy KaiSign
        address[] memory admins = new address[](1);
        admins[0] = address(this);
        
        kaisign = new KaiSign(
            address(realityETH),
            ARBITRATOR,
            TREASURY,
            MIN_BOND,
            admins
        );
        
        // Fund test user
        vm.deal(USER, 10 ether);
    }
    
    function testCommitBlobSpec() public {
        vm.startPrank(USER);
        
        // Create commitment
        bytes32 commitment = keccak256(abi.encodePacked(SAMPLE_BLOB_HASH, uint256(123)));
        
        // Commit the spec
        kaisign.commitSpec(commitment, CONTRACT, CHAIN_ID);
        
        vm.stopPrank();
    }
    
    function testRevealBlobSpec() public {
        vm.startPrank(USER);
        
        // Create commitment
        uint256 nonce = 123;
        bytes32 commitment = keccak256(abi.encodePacked(SAMPLE_BLOB_HASH, nonce));
        
        // Commit the spec and capture the event
        vm.recordLogs();
        kaisign.commitSpec(commitment, CONTRACT, CHAIN_ID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Extract commitmentId from event
        bytes32 commitmentId;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("LogCommitSpec(address,bytes32,address,uint256,uint256,uint64)")) {
                commitmentId = entries[i].topics[2]; // indexed commitmentId
                break;
            }
        }
        
        // Reveal the spec with blob hash
        bytes32 specID = kaisign.revealSpec{value: MIN_BOND}(
            commitmentId,
            SAMPLE_BLOB_HASH,
            SAMPLE_BLOB_HASH,
            nonce
        );
        
        // Verify the blob hash was stored
        assertEq(kaisign.getSpecBlobHash(specID), SAMPLE_BLOB_HASH);
        
        vm.stopPrank();
    }
    
    function testBlobHashStorage() public {
        vm.startPrank(USER);
        
        // Create and reveal spec
        uint256 nonce = 456;
        bytes32 blobHash = keccak256("test-blob-data");
        bytes32 commitment = keccak256(abi.encodePacked(blobHash, nonce));
        
        // Commit and capture event
        vm.recordLogs();
        kaisign.commitSpec(commitment, CONTRACT, CHAIN_ID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        bytes32 commitmentId;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("LogCommitSpec(address,bytes32,address,uint256,uint256,uint64)")) {
                commitmentId = entries[i].topics[2];
                break;
            }
        }
        
        bytes32 specID = kaisign.revealSpec{value: MIN_BOND}(
            commitmentId,
            blobHash,
            blobHash,
            nonce
        );
        
        // Verify blob hash retrieval
        bytes32 storedHash = kaisign.getSpecBlobHash(specID);
        assertEq(storedHash, blobHash, "Blob hash mismatch");
        
        vm.stopPrank();
    }
    
    function testInvalidBlobReveal() public {
        vm.startPrank(USER);
        
        // Create commitment
        uint256 nonce = 789;
        bytes32 commitment = keccak256(abi.encodePacked(SAMPLE_BLOB_HASH, nonce));
        
        // Commit and capture event
        vm.recordLogs();
        kaisign.commitSpec(commitment, CONTRACT, CHAIN_ID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        bytes32 commitmentId;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("LogCommitSpec(address,bytes32,address,uint256,uint256,uint64)")) {
                commitmentId = entries[i].topics[2];
                break;
            }
        }
        
        // Try to reveal with empty blob hash
        vm.expectRevert(KaiSign.InvalidReveal.selector);
        kaisign.revealSpec{value: MIN_BOND}(
            commitmentId,
            bytes32(0),
            bytes32(0),
            nonce
        );
        
        vm.stopPrank();
    }
    
    function testBlobSpecProposal() public {
        vm.startPrank(USER);
        
        // Create and reveal spec
        uint256 nonce = 999;
        bytes32 commitment = keccak256(abi.encodePacked(SAMPLE_BLOB_HASH, nonce));
        
        // Commit and capture event
        vm.recordLogs();
        kaisign.commitSpec(commitment, CONTRACT, CHAIN_ID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        bytes32 commitmentId;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("LogCommitSpec(address,bytes32,address,uint256,uint256,uint64)")) {
                commitmentId = entries[i].topics[2];
                break;
            }
        }
        
        // Reveal with sufficient bond to auto-propose
        bytes32 specID = kaisign.revealSpec{value: MIN_BOND * 2}(
            commitmentId,
            SAMPLE_BLOB_HASH,
            SAMPLE_BLOB_HASH,
            nonce
        );
        
        // Get spec details
        (,, KaiSign.Status status,,,,, bytes32 blobHash,,,) = kaisign.specs(specID);
        
        assertEq(uint256(status), uint256(KaiSign.Status.Proposed), "Should be proposed");
        assertEq(blobHash, SAMPLE_BLOB_HASH, "Blob hash should match");
        
        vm.stopPrank();
    }
    
    function testMultipleBlobSpecs() public {
        vm.startPrank(USER);
        
        bytes32[] memory blobHashes = new bytes32[](3);
        blobHashes[0] = keccak256("blob1");
        blobHashes[1] = keccak256("blob2");
        blobHashes[2] = keccak256("blob3");
        
        bytes32[] memory specIDs = new bytes32[](3);
        
        for (uint i = 0; i < 3; i++) {
            uint256 nonce = i + 1000;
            bytes32 commitment = keccak256(abi.encodePacked(blobHashes[i], nonce));
            
            // Commit and capture event
            vm.recordLogs();
            kaisign.commitSpec(commitment, CONTRACT, CHAIN_ID);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            
            bytes32 commitmentId;
            for (uint j = 0; j < entries.length; j++) {
                if (entries[j].topics[0] == keccak256("LogCommitSpec(address,bytes32,address,uint256,uint256,uint64)")) {
                    commitmentId = entries[j].topics[2];
                    break;
                }
            }
            
            specIDs[i] = kaisign.revealSpec{value: MIN_BOND}(
                commitmentId,
                blobHashes[i],
                blobHashes[i],
                nonce
            );
        }
        
        // Verify all blob hashes are stored correctly
        for (uint i = 0; i < 3; i++) {
            assertEq(kaisign.getSpecBlobHash(specIDs[i]), blobHashes[i]);
        }
        
        vm.stopPrank();
    }
    
    function testBlobSpecWithIncentive() public {
        vm.startPrank(USER);
        
        // Create incentive for the contract
        kaisign.createIncentive{value: 1 ether}(
            CONTRACT,
            CHAIN_ID,
            1 ether,
            30 days,
            "Blob spec incentive"
        );
        
        // Create and reveal spec
        uint256 nonce = 2000;
        bytes32 commitment = keccak256(abi.encodePacked(SAMPLE_BLOB_HASH, nonce));
        
        // Commit and capture event
        vm.recordLogs();
        kaisign.commitSpec(commitment, CONTRACT, CHAIN_ID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        bytes32 commitmentId;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("LogCommitSpec(address,bytes32,address,uint256,uint256,uint64)")) {
                commitmentId = entries[i].topics[2];
                break;
            }
        }
        
        kaisign.revealSpec{value: MIN_BOND}(
            commitmentId,
            SAMPLE_BLOB_HASH,
            SAMPLE_BLOB_HASH,
            nonce
        );
        
        // Verify spec created with incentive pool available
        (uint256 poolAmount,) = kaisign.getIncentivePool(CONTRACT, CHAIN_ID);
        assertEq(poolAmount, 1 ether, "Incentive pool should exist");
        
        vm.stopPrank();
    }
}