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
 * @title WorkflowTests
 * @notice End-to-end workflow tests for KaiSignRegistry (ERC20 mode)
 * @dev Note: Full workflow tests require ERC20 Reality.eth deployment
 *      These tests validate the commit flow and basic operations
 */
contract WorkflowTests is Test {
    // ========== CONSTANTS ==========
    address constant REALITY_ETH_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;
    address constant NO_ARBITRATOR = address(0);
    uint256 constant MIN_BOND = 100 ether; // Token amount
    uint32 constant DEFAULT_TIMEOUT = 48 hours;
    bytes32 constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,uint256 idx,bool revoked)");

    // ========== STATE ==========
    KaiSignRegistry public registry;
    MockToken public token;

    address public owner;
    address public specProvider;
    address public voter1;
    address public voter2;
    address public revoker;

    // ========== SETUP ==========

    function setUp() public {
        string memory rpcUrl = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpcUrl);

        owner = makeAddr("owner");
        specProvider = makeAddr("specProvider");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        revoker = makeAddr("revoker");

        vm.deal(owner, 100 ether);
        vm.deal(specProvider, 100 ether);
        vm.deal(voter1, 100 ether);
        vm.deal(voter2, 100 ether);
        vm.deal(revoker, 100 ether);

        // Deploy token
        vm.prank(owner);
        token = new MockToken();

        // Distribute tokens
        vm.startPrank(owner);
        token.transfer(specProvider, 10_000 ether);
        token.transfer(voter1, 10_000 ether);
        token.transfer(voter2, 10_000 ether);
        token.transfer(revoker, 10_000 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        registry = new KaiSignRegistry(
            20, 1, address(0), owner,
            NO_ARBITRATOR, MIN_BOND
        );

        // Note: Using ETH Reality.eth as mock - full tests need ERC20 Reality.eth
        registry.setBondToken(address(token), REALITY_ETH_SEPOLIA);
        vm.stopPrank();
    }

    // ========== WORKFLOW 1: COMMIT FLOW ==========

    function test_Workflow_CommitFlow() public {
        console.log("\n=== Workflow: Commit Flow ===\n");

        // Test data
        bytes32 blobHash = keccak256("erc7730-metadata-json");
        bytes32 extcodehash = keccak256("uniswap-v3-router-bytecode");
        uint256 chainId = 1;
        uint256 nonce = block.timestamp;

        // Step 1: Provider commits spec
        console.log("Step 1: Commit spec");
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.prank(specProvider);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);

        assertTrue(commitmentId != bytes32(0), "Commitment should be created");
        console.log("   Commitment ID:", vm.toString(commitmentId));

        // Verify commitment data
        (address committer, , bool isRevealed, , uint256 storedChainId, bytes32 storedExtcodehash) =
            registry.commitments(commitmentId);

        assertEq(committer, specProvider, "Committer should match");
        assertEq(storedChainId, chainId, "Chain ID should match");
        assertEq(storedExtcodehash, extcodehash, "Extcodehash should match");
        assertFalse(isRevealed, "Should not be revealed yet");

        console.log("\n=== Commit Flow Complete ===\n");
        console.log("NOTE: Full reveal flow requires ERC20 Reality.eth deployment");
    }

    // ========== WORKFLOW 2: TOKEN APPROVAL FLOW ==========

    function test_Workflow_TokenApprovalFlow() public {
        console.log("\n=== Workflow: Token Approval Flow ===\n");

        bytes32 blobHash = keccak256("metadata");
        bytes32 metadataHash = keccak256("metadata-content");
        bytes32 extcodehash = keccak256("some-contract");
        uint256 chainId = 1;
        uint256 nonce = block.timestamp;

        // Step 1: Commit
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));
        vm.prank(specProvider);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);

        console.log("Step 1: Committed, ID:", vm.toString(commitmentId));

        // Step 2: Approve tokens
        vm.prank(specProvider);
        token.approve(address(registry), MIN_BOND);

        uint256 allowance = token.allowance(specProvider, address(registry));
        assertEq(allowance, MIN_BOND, "Allowance should be set");
        console.log("Step 2: Token approved, amount:", MIN_BOND);

        // Step 3: Reveal would fail on Reality.eth call (ETH vs ERC20)
        console.log("Step 3: Reveal requires ERC20 Reality.eth deployment");

        console.log("\n=== Token Approval Flow Complete ===\n");
    }

    // ========== WORKFLOW 3: MULTIPLE COMMITS ==========

    function test_Workflow_MultipleCommits() public {
        console.log("\n=== Workflow: Multiple Commits Same Contract ===\n");

        bytes32 extcodehash = keccak256("shared-contract-bytecode");
        uint256 chainId = 1;

        // Commit first spec
        bytes32 blobHash1 = keccak256("spec-v1");
        uint256 nonce1 = block.timestamp;
        bytes32 commitment1 = keccak256(abi.encode(blobHash1, nonce1));

        vm.prank(specProvider);
        bytes32 commitmentId1 = registry.commitSpec(commitment1, chainId, extcodehash);
        console.log("Spec 1 committed:", vm.toString(commitmentId1));

        // Commit second spec
        bytes32 blobHash2 = keccak256("spec-v2");
        uint256 nonce2 = block.timestamp + 1;
        bytes32 commitment2 = keccak256(abi.encode(blobHash2, nonce2));

        vm.prank(specProvider);
        bytes32 commitmentId2 = registry.commitSpec(commitment2, chainId, extcodehash);
        console.log("Spec 2 committed:", vm.toString(commitmentId2));

        // Verify both commitments exist
        (address c1, , , , ,) = registry.commitments(commitmentId1);
        (address c2, , , , , ) = registry.commitments(commitmentId2);

        assertEq(c1, specProvider, "Commit 1 should exist");
        assertEq(c2, specProvider, "Commit 2 should exist");
        assertTrue(commitmentId1 != commitmentId2, "Commitment IDs should be different");

        console.log("\n=== Multiple Commits Complete ===\n");
    }

    // ========== WORKFLOW 4: UNIVERSE FORK ==========

    function test_Workflow_UniverseFork() public {
        console.log("\n=== Workflow: Universe Fork ===\n");

        // First registry is universe 1
        assertEq(registry.universeId(), 1, "First registry should be universe 1");
        assertEq(registry.parentRegistry(), address(0), "First registry should have no parent");
        console.log("Parent Registry:", address(registry));
        console.log("Parent Universe ID:", registry.universeId());

        // Deploy child registry
        vm.startPrank(owner);
        KaiSignRegistry childRegistry = new KaiSignRegistry(
            20,                         // treeDepth
            2,                          // universeId = 2
            address(registry),          // parentRegistry = first registry
            owner,
            NO_ARBITRATOR,
            MIN_BOND
        );
        vm.stopPrank();

        assertEq(childRegistry.universeId(), 2, "Child should be universe 2");
        assertEq(childRegistry.parentRegistry(), address(registry), "Child should have parent");

        console.log("Child Registry:", address(childRegistry));
        console.log("Child Universe ID:", childRegistry.universeId());
        console.log("Child's Parent:", childRegistry.parentRegistry());

        console.log("\n=== Universe Fork Complete ===\n");
    }
}
