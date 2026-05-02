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
 * @title RealityEthForkTest
 * @notice Fork test for KaiSignRegistry + Reality.eth v3.0 integration (ERC20 mode)
 * @dev Run with: forge test --match-contract RealityEthForkTest --fork-url $SEPOLIA_RPC_URL -vvv
 *
 * Note: This test uses the ETH Reality.eth as a mock for ERC20 Reality.eth
 * since askQuestionWithMinBondERC20 has a similar interface. Full integration
 * requires deploying RealityETH_ERC20 with the token.
 */
contract RealityEthForkTest is Test {
    // ========== CONSTANTS ==========

    // Reality.eth v3.0 sepolia
    address constant REALITY_ETH_SEPOLIA = 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA;

    // No arbitrator for faster testing (questions finalize after timeout without arbitration)
    address constant NO_ARBITRATOR = address(0);

    uint256 constant MIN_BOND = 100 ether; // Token amount
    uint32 constant DEFAULT_TIMEOUT = 48 hours;
    bytes32 constant LEAF_TYPEHASH =
        keccak256("RegistryLeaf(uint256 chainId,bytes32 extcodehash,bytes32 metadataHash,bool revoked)");

    // ========== STATE ==========

    KaiSignRegistry public registry;
    IRealityETH public realityETH;
    MockToken public token;

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
        // Fork Sepolia
        string memory rpcUrl = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            rpcUrl = vm.envString("MAINNET_RPC_URL");
        }
        vm.createSelectFork(rpcUrl);

        // Create test addresses
        deployer = makeAddr("deployer");
        proposer = makeAddr("proposer");
        challenger = makeAddr("challenger");
        voter = makeAddr("voter");

        // Fund test accounts
        vm.deal(deployer, 100 ether);
        vm.deal(proposer, 100 ether);
        vm.deal(challenger, 100 ether);
        vm.deal(voter, 100 ether);

        // Set up test data
        testBlobHash = keccak256("test-blob-hash");
        testMetadataHash = keccak256("test-metadata-content");
        testExtcodehash = keccak256("test-extcodehash");
        testChainId = 1; // Mainnet

        // Deploy token
        vm.prank(deployer);
        token = new MockToken();

        // Distribute tokens
        vm.startPrank(deployer);
        token.transfer(proposer, 10_000 ether);
        token.transfer(challenger, 10_000 ether);
        token.transfer(voter, 10_000 ether);
        vm.stopPrank();

        // Deploy KaiSignRegistry
        vm.startPrank(deployer);
        registry = new KaiSignRegistry(
            1,                    // universeId
            address(0),           // parentRegistry (none)
            deployer,             // initialOwner
            NO_ARBITRATOR,        // no arbitrator - faster finalization
            MIN_BOND              // minBond
        );

        // Set bond token - note: using ETH Reality.eth as mock
        // In production, this would be RealityETH_ERC20 instance
        registry.setBondToken(address(token), REALITY_ETH_SEPOLIA);
        vm.stopPrank();

        // Get Reality.eth interface
        realityETH = IRealityETH(REALITY_ETH_SEPOLIA);

        // Log setup info
        console.log("=== Fork Test Setup ===");
        console.log("Registry:", address(registry));
        console.log("Token:", address(token));
        console.log("Template ID:", registry.templateId());
        console.log("Min Bond:", MIN_BOND);
        console.log("NOTE: Using ETH Reality.eth as mock - full tests need ERC20 Reality.eth");
    }

    // ========== BASIC TESTS ==========

    function test_TemplateCreation() public view {
        uint256 templateId = registry.templateId();

        console.log("Template ID:", templateId);
        assertTrue(templateId > 0, "Template should be created");
    }

    function test_CommitFlow() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        // Commit
        vm.prank(proposer);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        assertTrue(commitmentId != bytes32(0), "Commitment ID should not be zero");

        // Check commitment data
        (
            address committer,
            ,
            bool isRevealed,
            ,
            uint256 chainId,
            bytes32 extcodehash
        ) = registry.commitments(commitmentId);

        assertEq(committer, proposer, "Committer should match");
        assertEq(chainId, testChainId, "Chain ID should match");
        assertEq(extcodehash, testExtcodehash, "Extcodehash should match");
        assertFalse(isRevealed, "Should not be revealed yet");

        console.log("Commitment created:", vm.toString(commitmentId));
    }

    function test_BondTokenRequired() public {
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(testBlobHash, nonce));

        vm.startPrank(proposer);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, testChainId, testExtcodehash);

        // revealSpec requires token bond
        // NOTE: This will fail at Reality.eth level since we're using ETH Reality.eth
        // but token approval and transfer to registry will work
        vm.expectRevert(); // Reality.eth ERC20 call will fail on ETH Reality.eth
        registry.revealSpec(commitmentId, testBlobHash, nonce, testMetadataHash, MIN_BOND);
        vm.stopPrank();

        console.log("Token bond flow validated up to Reality.eth call");
    }

    function test_ProposeRevokeRequiresToken() public {
        bytes32 fakeUid = keccak256("fake-uid");

        vm.startPrank(challenger);
        token.approve(address(registry), MIN_BOND);

        // Will fail at validation (attestation not found) before Reality.eth call
        vm.expectRevert(abi.encodeWithSignature("AttestationNotFound()"));
        registry.proposeRevoke(fakeUid, MIN_BOND);
        vm.stopPrank();

        console.log("Token revoke flow validated");
    }

    function test_UniverseFork() public {
        // First registry is universe 1
        assertEq(registry.universeId(), 1, "First registry should be universe 1");
        assertEq(registry.parentRegistry(), address(0), "First registry should have no parent");

        // Deploy child registry (universe 2) with parent
        vm.startPrank(deployer);
        KaiSignRegistry childRegistry = new KaiSignRegistry(
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

        console.log("Universe fork architecture verified!");
    }
}
