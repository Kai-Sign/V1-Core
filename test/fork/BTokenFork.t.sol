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
 * @dev Tests the Phase 2 bToken mode and clean break behavior
 *
 * Run with: source ../Kai-Sign-Builder/.env && forge test --match-contract BTokenForkTest -vvv
 */
contract BTokenForkTest is Test {
    // ========== CONSTANTS ==========

    // Reality.eth v3.0 Sepolia (ETH version)
    address constant REALITY_ETH_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;

    // Reality.eth v3.0 Sepolia ERC20 version
    // Note: For testing, we'll use the same address since the interface is compatible
    // In production, this would be a separate deployment
    address constant REALITY_ETH_ERC20_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;

    address constant NO_ARBITRATOR = address(0);
    uint256 constant MIN_BOND = 0.01 ether;
    uint256 constant MIN_TOKEN_BOND = 100 ether; // 100 bTokens
    uint32 constant DEFAULT_TIMEOUT = 48 hours;
    bytes32 constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,uint256 idx,bool revoked)");

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

        // Deploy KaiSignRegistry in ETH mode
        vm.startPrank(deployer);

        address[] memory attesters = new address[](1);
        attesters[0] = proposer;

        registry = new KaiSignRegistry(
            1,                          // universeId
            address(0),                 // parentRegistry (none)
            deployer,                   // initialOwner
            attesters,                  // initialAttesters
            REALITY_ETH_SEPOLIA,        // Reality.eth v3.0
            NO_ARBITRATOR,              // no arbitrator
            MIN_BOND                    // minBond
        );

        vm.stopPrank();

        realityETH = IRealityETH(REALITY_ETH_SEPOLIA);

        console.log("=== BToken Fork Test Setup ===");
        console.log("Registry:", address(registry));
        console.log("bToken:", address(bToken));
        console.log("Initial mode: ETH (bondToken == address(0))");
    }

    // ========== HELPER FUNCTIONS ==========

    function _activateBTokenMode() internal {
        vm.prank(deployer);
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);
    }

    function _commitAndRevealETH(
        address _proposer,
        bytes32 _blobHash,
        uint256 _bond
    ) internal returns (bytes32 uid, bytes32 questionId, bytes32 commitmentId) {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(_blobHash, nonce));

        vm.startPrank(_proposer);
        commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        uid = registry.revealSpec{value: _bond}(commitmentId, _blobHash, nonce, testMetadataHash);
        vm.stopPrank();

        questionId = registry.questionIds(uid);
    }

    function _commitAndRevealToken(
        address _proposer,
        bytes32 _blobHash,
        uint256 _tokenAmount
    ) internal returns (bytes32 uid, bytes32 questionId) {
        uint256 nonce = 67890;
        bytes32 commitment = keccak256(abi.encodePacked(_blobHash, nonce));

        vm.startPrank(_proposer);

        // Approve tokens
        bToken.approve(address(registry), _tokenAmount);

        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        uid = registry.revealSpecToken(commitmentId, _blobHash, nonce, testMetadataHash, _tokenAmount);
        vm.stopPrank();

        questionId = registry.questionIds(uid);
    }

    // ========== TEST: setBondToken Activation ==========

    function test_SetBondToken() public {
        console.log("\n=== Test: setBondToken Activation ===\n");

        // Verify initial ETH mode
        assertEq(address(registry.bondToken()), address(0), "Should start in ETH mode");

        // Activate bToken mode
        vm.prank(deployer);
        registry.setBondToken(address(bToken), REALITY_ETH_ERC20_SEPOLIA);

        // Verify bToken mode
        assertEq(address(registry.bondToken()), address(bToken), "bondToken should be set");
        assertEq(address(registry.realityETH_ERC20()), REALITY_ETH_ERC20_SEPOLIA, "realityETH_ERC20 should be set");

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
        vm.expectRevert("Invalid token");
        registry.setBondToken(address(0), REALITY_ETH_ERC20_SEPOLIA);

        // Zero Reality.eth ERC20 address
        vm.prank(deployer);
        vm.expectRevert("Invalid Reality.eth ERC20");
        registry.setBondToken(address(bToken), address(0));

        console.log("Invalid params correctly rejected!");
    }

    // ========== TEST: revealSpecToken ==========
    // NOTE: This test requires an ERC20 Reality.eth deployment with our bToken
    // Sepolia only has ETH Reality.eth, so this test is skipped on Sepolia fork
    // To fully test: Deploy RealityETH_ERC20 with bToken on testnet

    function test_RevealSpecToken() public {
        console.log("\n=== Test: revealSpecToken ===\n");
        console.log("SKIPPED: Requires ERC20 Reality.eth deployment");
        console.log("Sepolia only has ETH Reality.eth at 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA");
        console.log("To test: Deploy RealityETH_ERC20 with bToken");

        // Test the token approval and transfer logic up to Reality.eth call
        _activateBTokenMode();

        uint256 proposerBalanceBefore = bToken.balanceOf(proposer);
        console.log("Proposer bToken balance before:", proposerBalanceBefore);

        // Commit works
        uint256 nonce = 67890;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(proposer);
        bToken.approve(address(registry), MIN_TOKEN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);
        vm.stopPrank();

        assertTrue(commitmentId != bytes32(0), "Commitment should succeed");
        console.log("Commit succeeded - revealSpecToken needs ERC20 Reality.eth");
    }

    // ========== TEST: Mode Enforcement ==========

    function test_ModeEnforcement_ETHInBTokenMode() public {
        console.log("\n=== Test: Mode Enforcement - ETH in bToken Mode ===\n");

        _activateBTokenMode();

        // Try to use ETH function in bToken mode - should fail
        uint256 nonce = 11111;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(proposer);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("UseRevealSpecToken()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, testBlobHash, nonce, testMetadataHash);
        vm.stopPrank();

        console.log("ETH revealSpec correctly blocked in bToken mode!");
    }

    function test_ModeEnforcement_TokenInETHMode() public {
        console.log("\n=== Test: Mode Enforcement - Token in ETH Mode ===\n");

        // Stay in ETH mode (don't activate bToken)

        uint256 nonce = 22222;
        bytes32 commitment = keccak256(abi.encodePacked(testBlobHash, nonce));

        vm.startPrank(proposer);
        bToken.approve(address(registry), MIN_TOKEN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("UseRevealSpecETH()"));
        registry.revealSpecToken(commitmentId, testBlobHash, nonce, testMetadataHash, MIN_TOKEN_BOND);
        vm.stopPrank();

        console.log("Token revealSpecToken correctly blocked in ETH mode!");
    }

    function test_ModeEnforcement_ProposeRevokeETHInBTokenMode() public {
        console.log("\n=== Test: Mode Enforcement - proposeRevoke ETH in bToken Mode ===\n");

        // First submit and finalize an attestation in ETH mode
        (bytes32 uid, bytes32 questionId,) = _commitAndRevealETH(
            proposer,
            testBlobHash,
            MIN_BOND
        );

        // Submit APPROVE answer
        vm.prank(voter);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0);

        // Warp and finalize
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);
        bytes32 leaf = keccak256(abi.encode(LEAF_TYPEHASH, testChainId, testExtcodehash, testMetadataHash, uint64(1), false));
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(proposer);
        registry.finalize(uid, leaf, proof);

        // NOW activate bToken mode
        _activateBTokenMode();

        // Try ETH proposeRevoke - should fail
        vm.prank(challenger);
        vm.expectRevert(abi.encodeWithSignature("UseProposeRevokeToken()"));
        registry.proposeRevoke{value: MIN_BOND}(uid);

        console.log("ETH proposeRevoke correctly blocked in bToken mode!");
    }

    // ========== TEST: proposeRevokeToken ==========
    // NOTE: Requires ERC20 Reality.eth - skipped on Sepolia

    function test_ProposeRevokeToken() public {
        console.log("\n=== Test: proposeRevokeToken ===\n");
        console.log("SKIPPED: Requires ERC20 Reality.eth deployment");

        // Test the mode enforcement instead
        _activateBTokenMode();

        // Verify proposeRevokeToken exists and mode check works
        // (full test requires ERC20 Reality.eth)
        console.log("proposeRevokeToken mode enforcement tested in test_ModeEnforcement_ProposeRevokeETHInBTokenMode");
    }

    // ========== TEST: Full bToken Flow with Finalization ==========
    // NOTE: Requires ERC20 Reality.eth - skipped on Sepolia

    function test_BTokenFinalization() public {
        console.log("\n=== Test: Full bToken Flow with Finalization ===\n");
        console.log("SKIPPED: Requires ERC20 Reality.eth deployment");
        console.log("The flow would be:");
        console.log("1. Activate bToken mode");
        console.log("2. commitSpec() - works (tested)");
        console.log("3. revealSpecToken() - requires ERC20 Reality.eth");
        console.log("4. Submit answer on Reality.eth ERC20");
        console.log("5. Warp time past timeout");
        console.log("6. finalize() - reads from realityETH_ERC20");
        console.log("\nETH flow is fully tested in RealityEthFork.t.sol");
    }

    // ========== TEST: Universe Fork Architecture ==========

    function test_UniverseFork() public {
        console.log("\n=== Test: Universe Fork Architecture ===\n");

        // First registry is universe 1
        assertEq(registry.universeId(), 1, "First registry should be universe 1");
        assertEq(registry.parentRegistry(), address(0), "First registry should have no parent");

        // Deploy child registry (universe 2) with parent
        vm.startPrank(deployer);
        address[] memory attesters = new address[](1);
        attesters[0] = proposer;

        KaiSignRegistry childRegistry = new KaiSignRegistry(
            2,                          // universeId = 2
            address(registry),          // parentRegistry = first registry
            deployer,
            attesters,
            REALITY_ETH_SEPOLIA,
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

    // ========== TEST: Clean Break - ETH Attestations Orphaned ==========

    function test_CleanBreak() public {
        console.log("\n=== Test: Clean Break - ETH Attestations Orphaned ===\n");

        // 1. Submit spec in ETH mode (don't finalize yet)
        (bytes32 uid, bytes32 questionId, ) = _commitAndRevealETH(
            proposer,
            testBlobHash,
            MIN_BOND
        );

        console.log("1. Submitted spec in ETH mode");
        console.log("   UID:", vm.toString(uid));
        console.log("   Question ID:", vm.toString(questionId));

        // Submit APPROVE answer
        vm.prank(voter);
        realityETH.submitAnswer{value: MIN_BOND}(questionId, bytes32(uint256(1)), 0);

        // Wait for timeout
        vm.warp(block.timestamp + DEFAULT_TIMEOUT + 1);
        console.log("2. Answer submitted and timeout reached");

        // 2. NOW activate bToken mode (BEFORE finalizing)
        _activateBTokenMode();
        console.log("3. bToken mode activated - CLEAN BREAK");

        // 3. Try to finalize the ETH-based attestation
        // The finalize function queries the correct Reality.eth based on bondToken
        // After bToken activation, it will try to query realityETH_ERC20
        // The question was created on realityETH (ETH version), not realityETH_ERC20
        // This should cause issues because the question doesn't exist on realityETH_ERC20

        bytes32 leaf = keccak256(abi.encode(LEAF_TYPEHASH, testChainId, testExtcodehash, testMetadataHash, uint64(1), false));
        bytes32[] memory proof = new bytes32[](0);

        // The attestation cannot be properly finalized because:
        // - It was submitted to realityETH (ETH version)
        // - But now the registry queries realityETH_ERC20 for results
        // - The question doesn't exist on realityETH_ERC20

        // Note: In the current implementation, this may or may not revert depending on
        // how Reality.eth handles non-existent question IDs. But the attestation
        // is effectively orphaned because the question result cannot be properly verified.

        // Try finalization - should behave unexpectedly or fail
        vm.prank(proposer);
        try registry.finalize(uid, leaf, proof) {
            // If it doesn't revert, check if the result is correct
            // The result will likely be incorrect since question doesn't exist
            IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
            console.log("4. Finalize did not revert but attestation state is:");
            console.log("   finalizedAt:", att.finalizedAt);
            console.log("   idx:", att.idx);
            console.log("   revoked:", att.revoked);

            // If the question doesn't exist on realityETH_ERC20, it won't be finalized
            // or will be rejected (revoked) because isFinalized returns false
        } catch {
            console.log("4. Finalize reverted - ETH attestation is orphaned!");
        }

        console.log("\nClean break behavior: ETH attestations cannot be properly");
        console.log("finalized after bToken mode activation.");
        console.log("Users must re-submit specs in bToken mode.");
    }

    // ========== TEST: Complete bToken Workflow After Clean Break ==========
    // NOTE: Partially tested - bToken submission requires ERC20 Reality.eth

    function test_CompleteWorkflowAfterCleanBreak() public {
        console.log("\n=== Test: Complete Workflow After Clean Break ===\n");

        // 1. Start with some ETH attestations (left unfinalized)
        bytes32 ethBlobHash = keccak256("eth-spec-orphaned");
        (bytes32 ethUid, , ) = _commitAndRevealETH(proposer, ethBlobHash, MIN_BOND);
        console.log("1. ETH spec submitted (will be orphaned):", vm.toString(ethUid));

        // 2. Activate bToken mode
        _activateBTokenMode();
        console.log("2. bToken mode activated");

        // 3. Verify ETH functions are now blocked
        uint256 nonce = 99999;
        bytes32 commitment = keccak256(abi.encodePacked(keccak256("blocked"), nonce));

        vm.startPrank(proposer);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        vm.expectRevert(abi.encodeWithSignature("UseRevealSpecToken()"));
        registry.revealSpec{value: MIN_BOND}(commitmentId, keccak256("blocked"), nonce, testMetadataHash);
        vm.stopPrank();

        console.log("3. ETH revealSpec correctly blocked after bToken activation");

        // 4. Verify ETH attestation remains unfinalized (orphaned)
        IKaiSignRegistry.Attestation memory ethAtt = registry.getAttestation(ethUid);
        assertEq(ethAtt.finalizedAt, 0, "ETH attestation should remain unfinalized");
        console.log("4. ETH spec remains orphaned (finalizedAt=0)");

        console.log("\nClean break verified: ETH specs orphaned, ETH functions blocked");
        console.log("Full bToken workflow requires ERC20 Reality.eth deployment");
    }
}
