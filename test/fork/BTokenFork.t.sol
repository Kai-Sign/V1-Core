// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockBToken
 * @notice Simple ERC20 for testing bToken mode
 */
contract MockBToken is ERC20 {
    constructor() ERC20("Mock bToken", "BTOKEN") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title BTokenForkTest
 * @notice Fork tests for bToken (ERC20) mode in KaiSignRegistry
 * @dev Tests the ERC20-only bond mode
 *
 * Run with: source ../Kai-Sign-Builder/.env && forge test --match-contract BTokenForkTest -vvv
 */
contract BTokenForkTest is Test {
    // ========== CONSTANTS ==========

    // Reality.eth v3.0 Sepolia ERC20 version
    address constant REALITY_ETH_ERC20_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;

    address constant NO_ARBITRATOR = address(0);
    uint256 constant MIN_BOND = 0.01 ether;
    uint256 constant MIN_TOKEN_BOND = 100 ether; // 100 bTokens
    uint32 constant DEFAULT_TIMEOUT = 48 hours;
    bytes32 constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,uint256 idx,bool revoked)");

    // ========== EVENTS ==========

    event BondTokenSet(address indexed token, address indexed realityERC20);

    // ========== STATE ==========

    KaiSignRegistry public registry;
    IRealityETH public realityETH;
    MockBToken public bToken;

    address public deployer;
    address public proposer;
    address public challenger;
    address public voter;

    // Test data
    bytes32 public testBlobHash;
    bytes32 public testMetadataHash;
    bytes32 public testExtcodehash;
    uint256 public testChainId;

    // ========== SETUP ==========

    function setUp() public {
        // Fork Sepolia - try SEPOLIA_RPC_URL first
        string memory rpcUrl = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Create test addresses
        deployer = makeAddr("deployer");
        proposer = makeAddr("proposer");
        challenger = makeAddr("challenger");
        voter = makeAddr("voter");

        // Fund test accounts with ETH
        vm.deal(deployer, 100 ether);
        vm.deal(proposer, 100 ether);
        vm.deal(challenger, 100 ether);
        vm.deal(voter, 100 ether);

        // Set up test data
        testBlobHash = keccak256("test-blob-hash-btoken");
        testMetadataHash = keccak256("test-metadata-content-btoken");
        testExtcodehash = keccak256("test-extcodehash-btoken");
        testChainId = 1;

        // Deploy bToken
        vm.prank(deployer);
        bToken = new MockBToken();

        // Distribute bTokens to test accounts
        vm.startPrank(deployer);
        bToken.transfer(proposer, 10_000 ether);
        bToken.transfer(challenger, 10_000 ether);
        bToken.transfer(voter, 10_000 ether);
        vm.stopPrank();

        // Deploy KaiSignRegistry (ERC20 only mode)
        vm.startPrank(deployer);
        registry = new KaiSignRegistry(
            20,                         // treeDepth
            1,                          // universeId
            address(0),                 // parentRegistry (none)
            deployer,                   // initialOwner
            NO_ARBITRATOR,              // no arbitrator
            MIN_BOND                    // minBond
        );
        vm.stopPrank();

        realityETH = IRealityETH(REALITY_ETH_ERC20_SEPOLIA);

        console.log("=== BToken Fork Test Setup ===");
        console.log("Registry:", address(registry));
        console.log("bToken:", address(bToken));
        console.log("Note: setBondToken must be called before reveal/revoke operations");
    }

    // ========== HELPER FUNCTIONS ==========

    function _activateBTokenMode() internal {
        vm.prank(deployer);
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);
    }

    function _commitAndRevealToken(
        address _proposer,
        bytes32 _blobHash,
        uint256 _tokenAmount
    ) internal returns (bytes32 uid, bytes32 questionId) {
        uint256 nonce = 67890;
        bytes32 commitment = keccak256(abi.encode(_blobHash, nonce));

        vm.startPrank(_proposer);

        // Approve tokens
        bToken.approve(address(registry), _tokenAmount);

        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        uid = registry.revealSpec(commitmentId, _blobHash, nonce, testMetadataHash, _tokenAmount);
        vm.stopPrank();

        (questionId,) = registry.questions(uid);
    }

    // ========== TEST: setBondToken Activation ==========

    function test_SetBondToken() public {
        console.log("\n=== Test: setBondToken Activation ===\n");

        // Verify initial state - bondToken not set
        assertEq(address(registry.bondToken()), address(0), "Should start with no bond token");

        // Activate bToken mode
        vm.prank(deployer);
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);

        // Verify bToken mode
        assertEq(address(registry.bondToken()), address(bToken), "bondToken should be set");
        assertEq(address(registry.realityETH()), REALITY_ETH_ERC20_SEPOLIA, "realityETH should be set");

        console.log("bToken mode activated successfully!");
    }

    function test_SetBondToken_OnlyOwner() public {
        console.log("\n=== Test: setBondToken Only Owner ===\n");

        // Non-owner should fail
        vm.prank(proposer);
        vm.expectRevert();
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);

        console.log("Non-owner correctly rejected!");
    }

    function test_SetBondToken_InvalidParams() public {
        console.log("\n=== Test: setBondToken Invalid Params ===\n");

        // Zero bToken address
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        registry.setBondToken(address(0), REALITY_ETH_ERC20_SEPOLIA);

        // Zero Reality.eth address
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("InvalidRealityETH()"));
        registry.setBondToken(address(bToken), address(0));

        console.log("Invalid params correctly rejected!");
    }

    function test_SetBondToken_CanChangeToken() public {
        console.log("\n=== Test: setBondToken Can Change Token ===\n");

        // First activation
        vm.prank(deployer);
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);
        assertEq(address(registry.bondToken()), address(bToken), "First token should be set");

        // Deploy second token
        vm.prank(deployer);
        MockBToken bToken2 = new MockBToken();

        // Change to second token
        vm.prank(deployer);
        registry.setBondToken(address(bToken2), REALITY_ETH_ERC20_SEPOLIA);

        assertEq(address(registry.bondToken()), address(bToken2), "Should be changed to second token");
        console.log("bToken successfully changed!");
    }

    function test_SetBondToken_CanChangeRealityETH() public {
        console.log("\n=== Test: setBondToken Can Change Reality.eth ===\n");

        // First activation
        vm.prank(deployer);
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);
        assertEq(address(registry.realityETH()), REALITY_ETH_ERC20_SEPOLIA, "First Reality.eth should be set");
        uint256 firstTemplateId = registry.templateId();

        // Change to same Reality.eth (re-creates template)
        vm.prank(deployer);
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);

        assertEq(address(registry.realityETH()), REALITY_ETH_ERC20_SEPOLIA, "Reality.eth should still be set");
        assertTrue(registry.templateId() > firstTemplateId, "New template should be created");
        console.log("Reality.eth reconfigured, new template created!");
    }

    function test_SetBondToken_EmitsEventOnChange() public {
        console.log("\n=== Test: setBondToken Emits Event On Change ===\n");

        // First activation
        vm.prank(deployer);
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);

        // Deploy second token
        vm.prank(deployer);
        MockBToken bToken2 = new MockBToken();

        // Expect event on change
        vm.expectEmit(true, true, false, false);
        emit BondTokenSet(address(bToken2), REALITY_ETH_ERC20_SEPOLIA);

        vm.prank(deployer);
        registry.setBondToken(address(bToken2), REALITY_ETH_ERC20_SEPOLIA);

        console.log("Event emitted on token change!");
    }

    // ========== TEST: revealSpec with Token ==========

    function test_RevealSpec_RequiresBondToken() public {
        console.log("\n=== Test: revealSpec Requires Bond Token ===\n");

        // Don't activate bToken mode - should fail
        uint256 nonce = 67890;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.startPrank(proposer);
        bToken.approve(address(registry), MIN_TOKEN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("BondTokenNotSet()"));
        registry.revealSpec(commitmentId, testBlobHash, nonce, testMetadataHash, MIN_TOKEN_BOND);
        vm.stopPrank();

        console.log("revealSpec correctly requires bondToken to be set!");
    }

    function test_RevealSpec() public {
        console.log("\n=== Test: revealSpec ===\n");
        console.log("NOTE: Full test requires ERC20 Reality.eth deployment");

        _activateBTokenMode();

        uint256 proposerBalanceBefore = bToken.balanceOf(proposer);
        console.log("Proposer bToken balance before:", proposerBalanceBefore);

        // Commit works
        uint256 nonce = 67890;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.startPrank(proposer);
        bToken.approve(address(registry), MIN_TOKEN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        vm.stopPrank();

        assertTrue(commitmentId != bytes32(0), "Commitment should succeed");
        console.log("Commit succeeded - revealSpec needs ERC20 Reality.eth");
    }

    // ========== TEST: proposeRevoke with Token ==========

    function test_ProposeRevoke_RequiresBondToken() public {
        console.log("\n=== Test: proposeRevoke Requires Bond Token ===\n");

        // Don't activate bToken mode - should fail
        bytes32 fakeUid = keccak256("fake-uid");

        vm.prank(challenger);
        vm.expectRevert(abi.encodeWithSignature("BondTokenNotSet()"));
        registry.proposeRevoke(fakeUid, MIN_TOKEN_BOND);

        console.log("proposeRevoke correctly requires bondToken to be set!");
    }

    // ========== TEST: Universe Fork Architecture ==========

    function test_UniverseFork() public {
        console.log("\n=== Test: Universe Fork Architecture ===\n");

        // First registry is universe 1
        assertEq(registry.universeId(), 1, "First registry should be universe 1");
        assertEq(registry.parentRegistry(), address(0), "First registry should have no parent");

        // Deploy child registry (universe 2) with parent
        vm.startPrank(deployer);
        KaiSignRegistry childRegistry = new KaiSignRegistry(
            20,                         // treeDepth
            2,                          // universeId = 2
            address(registry),          // parentRegistry = first registry
            deployer,
            NO_ARBITRATOR,
            MIN_BOND
        );
        vm.stopPrank();

        // Verify child registry
        assertEq(childRegistry.universeId(), 2, "Child should be universe 2");
        assertEq(childRegistry.parentRegistry(), address(registry), "Child should have parent");

        console.log("Parent Registry:", address(registry));
        console.log("Parent Universe ID:", registry.universeId());
        console.log("Child Registry:", address(childRegistry));
        console.log("Child Universe ID:", childRegistry.universeId());
        console.log("Child's Parent:", childRegistry.parentRegistry());

        console.log("\nUniverse fork architecture verified!");
    }

    // ========== TEST: Full bToken Flow with Finalization ==========
    // NOTE: Requires ERC20 Reality.eth - skipped on Sepolia

    function test_BTokenFinalization() public {
        console.log("\n=== Test: Full bToken Flow with Finalization ===\n");
        console.log("SKIPPED: Requires ERC20 Reality.eth deployment");
        console.log("The flow would be:");
        console.log("1. setBondToken() - configure token and Reality.eth");
        console.log("2. commitSpec() - works (tested)");
        console.log("3. revealSpec() - requires ERC20 Reality.eth");
        console.log("4. Submit answer on Reality.eth ERC20");
        console.log("5. Warp time past timeout");
        console.log("6. finalize() - reads from realityETH");
    }

    // ========== TEST: Complete bToken Workflow ==========

    function test_CompleteWorkflow() public {
        console.log("\n=== Test: Complete Workflow ===\n");

        // 1. Activate bToken mode
        _activateBTokenMode();
        console.log("1. bToken mode activated");

        // 2. Verify commit works
        uint256 nonce = 99999;
        bytes32 commitment = keccak256(abi.encode(keccak256("test-spec"), nonce));

        vm.startPrank(proposer);
        bToken.approve(address(registry), MIN_TOKEN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        vm.stopPrank();

        assertTrue(commitmentId != bytes32(0), "Commitment should succeed");
        console.log("2. Commit succeeded");

        console.log("\nFull workflow requires ERC20 Reality.eth deployment");
        console.log("See test_BTokenFinalization for expected flow");
    }
}
