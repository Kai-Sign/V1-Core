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
 * @title SecurityTests
 * @notice Security-focused tests for KaiSignRegistry (ERC20 mode)
 */
contract SecurityTests is Test {
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
    address public attester;
    address public attacker;

    // Test data
    bytes32 public testBlobHash;
    bytes32 public testMetadataHash;
    bytes32 public testExtcodehash;
    uint256 public testChainId;

    // ========== SETUP ==========

    function setUp() public {
        string memory rpcUrl = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpcUrl);

        owner = makeAddr("owner");
        attester = makeAddr("attester");
        attacker = makeAddr("attacker");

        vm.deal(owner, 100 ether);
        vm.deal(attester, 100 ether);
        vm.deal(attacker, 100 ether);

        testBlobHash = keccak256("test-blob");
        testMetadataHash = keccak256("test-metadata-content");
        testExtcodehash = keccak256("test-bytecode");
        testChainId = 1;

        // Deploy token
        vm.prank(owner);
        token = new MockToken();

        // Distribute tokens
        vm.startPrank(owner);
        token.transfer(attester, 10_000 ether);
        token.transfer(attacker, 10_000 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        registry = new KaiSignRegistry(
            20, 1, address(0), owner,
            NO_ARBITRATOR, MIN_BOND
        );

        // Note: Using ETH Reality.eth as mock
        registry.setBondToken(address(token), REALITY_ETH_SEPOLIA);
        vm.stopPrank();
    }

    // ========== ACCESS CONTROL TESTS ==========

    function test_AccessControl_OnlyOwner_SetMinBond() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.setMinBond(1 ether);
    }

    function test_AccessControl_OnlyOwner_Pause() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.pause();
    }

    function test_AccessControl_OnlyOwner_Unpause() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(attacker);
        vm.expectRevert();
        registry.unpause();
    }

    function test_AccessControl_OnlyOwner_SetBondToken() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.setBondToken(address(1), address(2));
    }

    // ========== INPUT VALIDATION TESTS ==========

    function test_Validation_InvalidChainId() public {
        bytes32 commitment = keccak256("test");

        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSignature("InvalidChainId()"));
        registry.commitSpec(commitment, 0, testExtcodehash);
    }

    function test_Validation_InvalidExtcodehash() public {
        bytes32 commitment = keccak256("test");

        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSignature("InvalidExtcodehash()"));
        registry.commitSpec(commitment, testChainId, bytes32(0));
    }

    function test_Validation_EmptyBlobHash() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(bytes32(0), nonce));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("EmptyBlobHash()"));
        registry.revealSpec(commitmentId, bytes32(0), nonce, testMetadataHash, MIN_BOND);
        vm.stopPrank();
    }

    function test_Validation_BelowMinBond() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("BelowMinBond()"));
        registry.revealSpec(commitmentId, testBlobHash, nonce, testMetadataHash, MIN_BOND - 1);
        vm.stopPrank();
    }

    function test_Validation_BondTokenNotSet() public {
        // Deploy new registry without setBondToken
        vm.prank(owner);
        KaiSignRegistry newRegistry = new KaiSignRegistry(
            20, 2, address(0), owner,
            NO_ARBITRATOR, MIN_BOND
        );

        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.startPrank(attester);
        bytes32 commitmentId = newRegistry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("BondTokenNotSet()"));
        newRegistry.revealSpec(commitmentId, testBlobHash, nonce, testMetadataHash, MIN_BOND);
        vm.stopPrank();
    }

    // ========== COMMITMENT VALIDATION ==========

    function test_Security_InvalidReveal_WrongNonce() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // Advance time past MIN_REVEAL_DELAY
        vm.warp(block.timestamp + 2);

        // Wrong nonce
        vm.expectRevert(abi.encodeWithSignature("InvalidReveal()"));
        registry.revealSpec(commitmentId, testBlobHash, 99999, testMetadataHash, MIN_BOND);
        vm.stopPrank();
    }

    function test_Security_InvalidReveal_WrongBlobHash() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // Advance time past MIN_REVEAL_DELAY
        vm.warp(block.timestamp + 2);

        // Wrong blob hash
        vm.expectRevert(abi.encodeWithSignature("InvalidReveal()"));
        registry.revealSpec(commitmentId, keccak256("wrong"), nonce, testMetadataHash, MIN_BOND);
        vm.stopPrank();
    }

    function test_Security_InvalidReveal_WrongCommitter() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        // Attester commits
        vm.prank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // Attacker tries to reveal
        vm.startPrank(attacker);
        token.approve(address(registry), MIN_BOND);
        vm.expectRevert(abi.encodeWithSignature("InvalidReveal()"));
        registry.revealSpec(commitmentId, testBlobHash, nonce, testMetadataHash, MIN_BOND);
        vm.stopPrank();
    }

    function test_Security_CommitmentNotFound() public {
        bytes32 fakeCommitmentId = keccak256("fake");

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        vm.expectRevert(abi.encodeWithSignature("CommitmentNotFound()"));
        registry.revealSpec(fakeCommitmentId, testBlobHash, 12345, testMetadataHash, MIN_BOND);
        vm.stopPrank();
    }

    // ========== REVOCATION SECURITY ==========

    function test_Security_ProposeRevoke_NotFinalized() public {
        // Create commitment but don't reveal/finalize
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.prank(attester);
        registry.commitSpec(commitment, testChainId, testExtcodehash);

        // Use a fake UID
        bytes32 fakeUid = keccak256("fake-uid");

        vm.startPrank(attacker);
        token.approve(address(registry), MIN_BOND);
        vm.expectRevert(abi.encodeWithSignature("AttestationNotFound()"));
        registry.proposeRevoke(fakeUid, MIN_BOND);
        vm.stopPrank();
    }

    function test_Security_ProposeRevoke_BondTokenNotSet() public {
        // Deploy new registry without setBondToken
        vm.prank(owner);
        KaiSignRegistry newRegistry = new KaiSignRegistry(
            20, 2, address(0), owner,
            NO_ARBITRATOR, MIN_BOND
        );

        bytes32 fakeUid = keccak256("fake-uid");

        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSignature("BondTokenNotSet()"));
        newRegistry.proposeRevoke(fakeUid, MIN_BOND);
        vm.stopPrank();
    }

    // ========== PAUSE PROTECTION ==========

    function test_Security_Paused_CommitSpec() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(attester);
        vm.expectRevert();
        registry.commitSpec(keccak256("test"), testChainId, testExtcodehash);
    }

    function test_Security_Paused_RevealSpec() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.prank(attester);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.prank(owner);
        registry.pause();

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        vm.expectRevert();
        registry.revealSpec(commitmentId, testBlobHash, nonce, testMetadataHash, MIN_BOND);
        vm.stopPrank();
    }

    function test_Security_Paused_ProposeRevoke() public {
        vm.prank(owner);
        registry.pause();

        bytes32 fakeUid = keccak256("fake-uid");

        vm.startPrank(attacker);
        token.approve(address(registry), MIN_BOND);
        vm.expectRevert();
        registry.proposeRevoke(fakeUid, MIN_BOND);
        vm.stopPrank();
    }
}
