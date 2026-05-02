// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @notice Simple ERC20 for testing
 */
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title KaiSignRegistryTest
 * @notice Unit tests for KaiSignRegistry contract (ERC20 mode)
 */
contract KaiSignRegistryTest is Test {
    // ========== CONSTANTS ==========
    address constant REALITY_ETH_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;
    address constant NO_ARBITRATOR = address(0);
    uint256 constant MIN_BOND = 100 ether; // Token amount
    uint32 constant DEFAULT_TIMEOUT = 48 hours;
    bytes32 constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,bool revoked)");

    // ========== STATE ==========
    KaiSignRegistry public registry;
    MockToken public token;

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

        // Deploy token
        vm.prank(owner);
        token = new MockToken();

        // Distribute tokens
        vm.startPrank(owner);
        token.transfer(attester1, 10_000 ether);
        token.transfer(attester2, 10_000 ether);
        token.transfer(nonAttester, 10_000 ether);
        vm.stopPrank();

        // Deploy registry
        vm.startPrank(owner);
        registry = new KaiSignRegistry(
            1,                    // universeId
            address(0),           // parentRegistry
            owner,                // initialOwner
            NO_ARBITRATOR,        // arbitrator
            MIN_BOND              // minBond
        );

        // Set bond token - note: using ETH Reality.eth as mock
        registry.setBondToken(address(token), REALITY_ETH_SEPOLIA);
        vm.stopPrank();
    }

    // ========== CONSTRUCTOR TESTS ==========

    function test_Constructor_SetsCorrectValues() public view {
        assertEq(registry.SMT_DEPTH(), 256);
        assertEq(registry.universeId(), 1);
        assertEq(registry.parentRegistry(), address(0));
        assertEq(registry.owner(), owner);
        assertEq(registry.minBond(), MIN_BOND);
        assertTrue(registry.templateId() > 0);
        assertTrue(registry.revokeTemplateId() > 0);
        assertEq(address(registry.bondToken()), address(token));
    }

    // ========== SET MIN BOND TESTS ==========

    function test_SetMinBond() public {
        uint256 newBond = 50 ether;

        vm.prank(owner);
        registry.setMinBond(newBond);

        assertEq(registry.minBond(), newBond);
    }

    function test_SetMinBond_OnlyOwner() public {
        vm.prank(nonAttester);
        vm.expectRevert();
        registry.setMinBond(50 ether);
    }

    function test_SetMinBond_AllowsZero() public {
        // Contract allows zero minBond - this is by design
        vm.prank(owner);
        registry.setMinBond(0);
        assertEq(registry.minBond(), 0);
    }

    // ========== SET BOND TOKEN TESTS ==========

    function test_SetBondToken() public {
        // Deploy new registry without setBondToken
        vm.prank(owner);
        KaiSignRegistry newRegistry = new KaiSignRegistry(
            2, address(0), owner,
            NO_ARBITRATOR, MIN_BOND
        );

        assertEq(address(newRegistry.bondToken()), address(0));
        assertEq(address(newRegistry.realityETH()), address(0));

        // Set bond token
        vm.prank(owner);
        newRegistry.setBondToken(address(token), REALITY_ETH_SEPOLIA);

        assertEq(address(newRegistry.bondToken()), address(token));
        assertEq(address(newRegistry.realityETH()), REALITY_ETH_SEPOLIA);
        assertTrue(newRegistry.templateId() > 0);
        assertTrue(newRegistry.revokeTemplateId() > 0);
    }

    function test_SetBondToken_InvalidToken() public {
        vm.prank(owner);
        KaiSignRegistry newRegistry = new KaiSignRegistry(
            2, address(0), owner,
            NO_ARBITRATOR, MIN_BOND
        );

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        newRegistry.setBondToken(address(0), REALITY_ETH_SEPOLIA);
    }

    function test_SetBondToken_InvalidRealityETH() public {
        vm.prank(owner);
        KaiSignRegistry newRegistry = new KaiSignRegistry(
            2, address(0), owner,
            NO_ARBITRATOR, MIN_BOND
        );

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidRealityETH()"));
        newRegistry.setBondToken(address(token), address(0));
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

        (address committer, , bool isRevealed, , uint256 storedChainId, bytes32 storedExtcodehash) =
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

    function test_RevealSpec_RequiresBondToken() public {
        // Deploy new registry without setBondToken
        vm.prank(owner);
        KaiSignRegistry newRegistry = new KaiSignRegistry(
            2, address(0), owner,
            NO_ARBITRATOR, MIN_BOND
        );

        bytes32 blobHash = keccak256("blob-data");
        bytes32 metadataHash = keccak256("metadata-content");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.startPrank(attester1);
        bytes32 commitmentId = newRegistry.commitSpec(commitment, 1, keccak256("bytecode"));

        vm.expectRevert(abi.encodeWithSignature("BondTokenNotSet()"));
        newRegistry.revealSpec(commitmentId, blobHash, nonce, metadataHash, MIN_BOND);
        vm.stopPrank();
    }

    function test_RevealSpec_BelowMinBond() public {
        bytes32 blobHash = keccak256("blob-data");
        bytes32 metadataHash = keccak256("metadata-content");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.startPrank(attester1);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, 1, keccak256("bytecode"));

        vm.expectRevert(abi.encodeWithSignature("BelowMinBond()"));
        registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, MIN_BOND - 1);
        vm.stopPrank();
    }

    function test_RevealSpec_InvalidCommitment() public {
        bytes32 blobHash = keccak256("blob-data");
        bytes32 metadataHash = keccak256("metadata-content");
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.startPrank(attester1);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, 1, keccak256("bytecode"));

        // Advance time past MIN_REVEAL_DELAY
        vm.warp(block.timestamp + 2);

        // Wrong nonce
        vm.expectRevert(abi.encodeWithSignature("InvalidReveal()"));
        registry.revealSpec(commitmentId, blobHash, 99999, metadataHash, MIN_BOND);
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

    // ========== SMT VERIFIER TESTS ==========

    function test_VerifySmtProof_RejectsWrongLength() public view {
        bytes32 key = registry.smtKey(1, keccak256("c"));
        bytes32[] memory proof = new bytes32[](0);
        // Wrong length must return false (not revert).
        assertFalse(registry.verifySmtProof(key, bytes32(0), proof, bytes32(0)));
    }

    // ========== STATE GETTERS TESTS ==========

    function test_SmtRoot_StartsAtZero() public view {
        assertEq(registry.smtRoot(), bytes32(0));
    }

    // ========== LEAF HASH TESTS ==========

    function test_LeafTypehashValue() public view {
        bytes32 expected = keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash)");
        assertEq(registry.LEAF_TYPEHASH(), expected, "LEAF_TYPEHASH should match SMT schema string");
    }

    function test_ApprovedLeafDeterministic() public view {
        uint256 chainId = 42161;
        bytes32 extcodehash = keccak256("some-contract");
        bytes32 metadataHash = keccak256("some-metadata");

        bytes32 a = registry.approvedLeaf(chainId, extcodehash, metadataHash);
        bytes32 b = registry.approvedLeaf(chainId, extcodehash, metadataHash);
        assertEq(a, b, "Same inputs must produce same leaf hash");

        bytes32 c = registry.approvedLeaf(chainId, extcodehash, keccak256("different-metadata"));
        assertTrue(a != c, "Different metadataHash must produce different leaf hash");
    }
}
