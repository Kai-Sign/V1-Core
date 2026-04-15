// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MetadataStatusMockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MetadataStatusMockRealityETH is IRealityETH {
    uint256 public nextTemplateId = 1;
    uint256 public nextQuestionNonce = 1;

    mapping(bytes32 => bool) public finalized;
    mapping(bytes32 => bytes32) public result;

    function createTemplate(string memory) external returns (uint256) {
        return nextTemplateId++;
    }

    function askQuestionWithMinBond(uint256, string memory, address, uint32, uint32, uint256, uint256)
        external
        payable
        returns (bytes32)
    {
        revert("unused");
    }

    function askQuestionWithMinBondERC20(uint256, string memory, address, uint32, uint32, uint256, uint256, uint256)
        external
        returns (bytes32)
    {
        return bytes32(nextQuestionNonce++);
    }

    function submitAnswerERC20(bytes32, bytes32, uint256, uint256) external pure {}

    function submitAnswer(bytes32, bytes32, uint256) external payable {
        revert("unused");
    }

    function isFinalized(bytes32 question_id) external view returns (bool) {
        return finalized[question_id];
    }

    function resultFor(bytes32 question_id) external view returns (bytes32) {
        return result[question_id];
    }

    function getBestAnswer(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getBond(bytes32) external pure returns (uint256) {
        return 0;
    }

    function claimWinnings(bytes32, bytes32[] memory, address[] memory, uint256[] memory, bytes32[] memory)
        external
        pure
    {
        revert("unused");
    }

    function getFinalizeTS(bytes32) external pure returns (uint32) {
        return 0;
    }

    function setQuestionResult(bytes32 questionId, bytes32 answer) external {
        finalized[questionId] = true;
        result[questionId] = answer;
    }
}

contract MetadataStatusTest is Test {
    uint256 constant MIN_BOND = 100 ether;

    KaiSignRegistry internal registry;
    MetadataStatusMockToken internal token;
    MetadataStatusMockRealityETH internal reality;

    address internal owner;
    address internal attester;
    address internal revoker;

    function setUp() public {
        owner = makeAddr("owner");
        attester = makeAddr("attester");
        revoker = makeAddr("revoker");

        vm.startPrank(owner);
        token = new MetadataStatusMockToken();
        reality = new MetadataStatusMockRealityETH();
        registry = new KaiSignRegistry(20, 1, address(0), owner, address(0), MIN_BOND);
        registry.setBondToken(address(token), address(reality));
        token.transfer(attester, 10_000 ether);
        token.transfer(revoker, 10_000 ether);
        vm.stopPrank();
    }

    function test_MetadataStatus_TracksUnknownApprovedRevoked() public {
        bytes32 blobHash = keccak256("blob");
        bytes32 metadataHash = keccak256("metadata");
        bytes32 extcodehash = keccak256("bytecode");
        uint256 chainId = 1;
        uint256 nonce = 12345;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        (IKaiSignRegistry.MetadataStatus initialStatus, bytes32 initialUid) =
            registry.getMetadataStatus(chainId, extcodehash, metadataHash);
        assertEq(uint8(initialStatus), uint8(IKaiSignRegistry.MetadataStatus.Unknown));
        assertEq(initialUid, bytes32(0));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
        vm.warp(block.timestamp + 2);
        bytes32 uid = registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, MIN_BOND);
        vm.stopPrank();

        (bytes32 questionId,) = registry.questions(uid);
        reality.setQuestionResult(questionId, bytes32(uint256(1)));
        registry.finalize(uid);

        (IKaiSignRegistry.MetadataStatus approvedStatus, bytes32 approvedUid) =
            registry.getMetadataStatus(chainId, extcodehash, metadataHash);
        assertEq(uint8(approvedStatus), uint8(IKaiSignRegistry.MetadataStatus.Approved));
        assertEq(approvedUid, uid);

        vm.startPrank(revoker);
        token.approve(address(registry), MIN_BOND);
        registry.proposeRevoke(uid, MIN_BOND);
        vm.stopPrank();

        (bytes32 revokeQuestionId,) = registry.revokeQuestions(uid);
        reality.setQuestionResult(revokeQuestionId, bytes32(uint256(1)));
        registry.finalizeRevoke(uid);

        (IKaiSignRegistry.MetadataStatus revokedStatus, bytes32 revokedUid) =
            registry.getMetadataStatus(chainId, extcodehash, metadataHash);
        assertEq(uint8(revokedStatus), uint8(IKaiSignRegistry.MetadataStatus.Revoked));
        assertEq(revokedUid, uid);
    }

    function test_MetadataStatus_StaysUnknown_WhenSubmissionRejected() public {
        bytes32 blobHash = keccak256("blob-rejected");
        bytes32 metadataHash = keccak256("metadata-rejected");
        bytes32 extcodehash = keccak256("bytecode-rejected");
        uint256 chainId = 1;
        uint256 nonce = 77;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
        vm.warp(block.timestamp + 2);
        bytes32 uid = registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, MIN_BOND);
        vm.stopPrank();

        (bytes32 questionId,) = registry.questions(uid);
        reality.setQuestionResult(questionId, bytes32(uint256(0)));
        registry.finalize(uid);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertTrue(att.revoked, "rejected submission should mark attestation revoked");

        (IKaiSignRegistry.MetadataStatus status, bytes32 foundUid) =
            registry.getMetadataStatus(chainId, extcodehash, metadataHash);
        assertEq(uint8(status), uint8(IKaiSignRegistry.MetadataStatus.Unknown));
        assertEq(foundUid, bytes32(0));
    }

    function test_MetadataStatus_StaysApproved_WhenRevokeRejected() public {
        bytes32 blobHash = keccak256("blob-revoke-rejected");
        bytes32 metadataHash = keccak256("metadata-revoke-rejected");
        bytes32 extcodehash = keccak256("bytecode-revoke-rejected");
        uint256 chainId = 1;
        uint256 nonce = 88;
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
        vm.warp(block.timestamp + 2);
        bytes32 uid = registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, MIN_BOND);
        vm.stopPrank();

        (bytes32 questionId,) = registry.questions(uid);
        reality.setQuestionResult(questionId, bytes32(uint256(1)));
        registry.finalize(uid);

        vm.startPrank(revoker);
        token.approve(address(registry), MIN_BOND);
        registry.proposeRevoke(uid, MIN_BOND);
        vm.stopPrank();

        (bytes32 revokeQuestionId,) = registry.revokeQuestions(uid);
        reality.setQuestionResult(revokeQuestionId, bytes32(uint256(0)));
        registry.finalizeRevoke(uid);

        IKaiSignRegistry.Attestation memory att = registry.getAttestation(uid);
        assertFalse(att.revoked, "rejected revoke should leave attestation approved");

        (IKaiSignRegistry.MetadataStatus status, bytes32 foundUid) =
            registry.getMetadataStatus(chainId, extcodehash, metadataHash);
        assertEq(uint8(status), uint8(IKaiSignRegistry.MetadataStatus.Approved));
        assertEq(foundUid, uid);
    }

    function test_MetadataStatus_LatestUidWinsForSameIdentity() public {
        bytes32 blobHash1 = keccak256("blob-same-1");
        bytes32 blobHash2 = keccak256("blob-same-2");
        bytes32 metadataHash = keccak256("metadata-same");
        bytes32 extcodehash = keccak256("bytecode-same");
        uint256 chainId = 1;
        bytes32 commitment1 = keccak256(abi.encode(blobHash1, uint256(111)));
        bytes32 commitment2 = keccak256(abi.encode(blobHash2, uint256(222)));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND * 2);
        bytes32 commitmentId1 = registry.commitSpec(commitment1, chainId, extcodehash);
        vm.warp(block.timestamp + 2);
        bytes32 uid1 = registry.revealSpec(commitmentId1, blobHash1, 111, metadataHash, MIN_BOND);
        vm.stopPrank();
        (bytes32 questionId1,) = registry.questions(uid1);
        reality.setQuestionResult(questionId1, bytes32(uint256(1)));
        registry.finalize(uid1);

        vm.startPrank(attester);
        bytes32 commitmentId2 = registry.commitSpec(commitment2, chainId, extcodehash);
        vm.warp(block.timestamp + 2);
        bytes32 uid2 = registry.revealSpec(commitmentId2, blobHash2, 222, metadataHash, MIN_BOND);
        vm.stopPrank();
        (bytes32 questionId2,) = registry.questions(uid2);
        reality.setQuestionResult(questionId2, bytes32(uint256(1)));
        registry.finalize(uid2);

        (IKaiSignRegistry.MetadataStatus status, bytes32 foundUid) =
            registry.getMetadataStatus(chainId, extcodehash, metadataHash);
        assertEq(uint8(status), uint8(IKaiSignRegistry.MetadataStatus.Approved));
        assertEq(foundUid, uid2, "latest finalized uid should be returned");
    }

    function test_MetadataStatus_UsesIdentityScope() public {
        bytes32 metadataHash = keccak256("shared-metadata");
        bytes32 extcodehash1 = keccak256("bytecode-a");
        bytes32 extcodehash2 = keccak256("bytecode-b");
        uint256 chainId = 1;

        bytes32 commitment = keccak256(abi.encode(keccak256("blob-a"), uint256(999)));

        vm.startPrank(attester);
        token.approve(address(registry), MIN_BOND);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash1);
        vm.warp(block.timestamp + 2);
        bytes32 uid = registry.revealSpec(commitmentId, keccak256("blob-a"), 999, metadataHash, MIN_BOND);
        vm.stopPrank();

        (bytes32 questionId,) = registry.questions(uid);
        reality.setQuestionResult(questionId, bytes32(uint256(1)));
        registry.finalize(uid);

        (IKaiSignRegistry.MetadataStatus status1, ) = registry.getMetadataStatus(chainId, extcodehash1, metadataHash);
        (IKaiSignRegistry.MetadataStatus status2, bytes32 uid2) =
            registry.getMetadataStatus(chainId, extcodehash2, metadataHash);

        assertEq(uint8(status1), uint8(IKaiSignRegistry.MetadataStatus.Approved));
        assertEq(uint8(status2), uint8(IKaiSignRegistry.MetadataStatus.Unknown));
        assertEq(uid2, bytes32(0));
    }
}
