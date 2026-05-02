// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KaiSignRegistry} from "../../src/KaiSignRegistry.sol";
import {IKaiSignRegistry} from "../../src/interfaces/IKaiSignRegistry.sol";
import {IRealityETH} from "../../src/interfaces/IRealityETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SmtHelper} from "../helpers/SmtHelper.sol";

contract MockRealityETH is IRealityETH {
    uint256 public nextTemplateId = 1;
    uint256 public nextNonce = 1;
    mapping(bytes32 => bool) public finalized;
    mapping(bytes32 => bytes32) public result;

    /// @dev Result the next created question will return when finalized.
    bytes32 public pendingResult = bytes32(uint256(1));

    function setPendingResult(bytes32 r) external { pendingResult = r; }

    function createTemplate(string memory) external returns (uint256) {
        return nextTemplateId++;
    }

    function askQuestionWithMinBond(
        uint256, string memory, address, uint32, uint32, uint256, uint256
    ) external payable returns (bytes32) {
        bytes32 qid = keccak256(abi.encodePacked("eth", msg.sender, nextNonce++));
        finalized[qid] = true;
        result[qid] = pendingResult;
        return qid;
    }

    function askQuestionWithMinBondERC20(
        uint256, string memory, address, uint32, uint32, uint256, uint256, uint256
    ) external returns (bytes32) {
        bytes32 qid = keccak256(abi.encodePacked("erc20", msg.sender, nextNonce++));
        finalized[qid] = true;
        result[qid] = pendingResult;
        return qid;
    }

    function submitAnswerERC20(bytes32, bytes32, uint256, uint256) external {}
    function submitAnswer(bytes32, bytes32, uint256) external payable {}
    function isFinalized(bytes32 qid) external view returns (bool) { return finalized[qid]; }
    function resultFor(bytes32 qid) external view returns (bytes32) { return result[qid]; }
    function getBestAnswer(bytes32 qid) external view returns (bytes32) { return result[qid]; }
    function getBond(bytes32) external pure returns (uint256) { return 0; }
    function claimWinnings(bytes32, bytes32[] memory, address[] memory, uint256[] memory, bytes32[] memory) external {}
    function getFinalizeTS(bytes32 qid) external view returns (uint32) { return finalized[qid] ? uint32(block.timestamp) : 0; }
}

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") { _mint(msg.sender, 1_000_000 ether); }
}

contract KaiSignRegistrySMTTest is Test {
    uint256 internal constant BOND = 1 ether;

    KaiSignRegistry internal registry;
    MockRealityETH internal reality;
    MockToken internal token;
    SmtHelper internal smt;

    address internal alice = address(0xA11CE);
    address internal bob   = address(0xB0B);

    function setUp() public {
        reality = new MockRealityETH();
        token = new MockToken();
        smt = new SmtHelper();

        registry = new KaiSignRegistry(
            1,             // universeId
            address(0),    // parentRegistry
            address(this), // initial owner
            address(0),    // arbitrator
            BOND
        );
        registry.setBondToken(address(token), address(reality));

        token.transfer(alice, 1000 ether);
        token.transfer(bob, 1000 ether);
        vm.prank(alice); token.approve(address(registry), type(uint256).max);
        vm.prank(bob);   token.approve(address(registry), type(uint256).max);
    }

    // ============ helpers ============

    /// @dev End-to-end: alice submits + reveals + collects the uid.
    function _submit(
        address who,
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash,
        bytes32 blobHash,
        uint256 nonce
    ) internal returns (bytes32 uid) {
        bytes32 commitment = keccak256(abi.encode(blobHash, nonce));
        vm.prank(who);
        bytes32 commitmentId = registry.commitSpec(commitment, chainId, extcodehash);
        vm.warp(block.timestamp + 1);
        vm.prank(who);
        uid = registry.revealSpec(commitmentId, blobHash, nonce, metadataHash, BOND);
    }

    /// @dev Compute the proof and finalize through the registry. Mirrors what an
    ///      off-chain bot would do.
    function _finalizeApproved(
        bytes32 uid,
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 metadataHash
    ) internal {
        bytes32 key = registry.smtKey(chainId, extcodehash);
        bytes32[] memory siblings = smt.proof(key);

        // Mirror the registry's update locally so we stay in sync.
        bytes32 newLeaf = registry.approvedLeaf(chainId, extcodehash, metadataHash);
        smt.update(key, newLeaf);

        registry.finalize(uid, siblings);
    }

    function _finalizeRevoke(
        bytes32 uid,
        uint256 chainId,
        bytes32 extcodehash,
        bytes32 /*metadataHash*/
    ) internal {
        bytes32 key = registry.smtKey(chainId, extcodehash);
        bytes32[] memory siblings = smt.proof(key);
        smt.update(key, bytes32(0));
        registry.finalizeRevoke(uid, siblings);
    }

    // ============ tests ============

    function test_emptyRoot_isZero() public {
        assertEq(registry.smtRoot(), bytes32(0));
        assertEq(smt.root(), bytes32(0));
    }

    function test_finalize_insertsLeaf_rootMatchesHelper() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("contractA");
        bytes32 metadataHash = keccak256("metaA");
        bytes32 blobHash = keccak256("blobA");

        bytes32 uid = _submit(alice, chainId, extcodehash, metadataHash, blobHash, 1);
        _finalizeApproved(uid, chainId, extcodehash, metadataHash);

        assertEq(registry.smtRoot(), smt.root(), "root mismatch with helper");
        assertTrue(registry.smtRoot() != bytes32(0));

        // Round-trip verifyAttestation
        bytes32 key = registry.smtKey(chainId, extcodehash);
        bytes32[] memory siblings = smt.proof(key);
        registry.verifyAttestation(chainId, extcodehash, metadataHash, siblings);
    }

    function test_finalize_twoDifferentKeys_rootEvolves() public {
        bytes32 root0 = registry.smtRoot();

        bytes32 uid1 = _submit(alice, 1, keccak256("A"), keccak256("metaA"), keccak256("blobA"), 1);
        _finalizeApproved(uid1, 1, keccak256("A"), keccak256("metaA"));
        bytes32 root1 = registry.smtRoot();

        bytes32 uid2 = _submit(bob, 1, keccak256("B"), keccak256("metaB"), keccak256("blobB"), 2);
        _finalizeApproved(uid2, 1, keccak256("B"), keccak256("metaB"));
        bytes32 root2 = registry.smtRoot();

        assertTrue(root0 != root1);
        assertTrue(root1 != root2);
        assertEq(registry.smtRoot(), smt.root());
    }

    function test_finalize_secondInsertSameKey_revertsSlotOccupied() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("dup");

        bytes32 uid1 = _submit(alice, chainId, extcodehash, keccak256("meta1"), keccak256("blob1"), 1);
        _finalizeApproved(uid1, chainId, extcodehash, keccak256("meta1"));

        // Second submission for the same (chainId, extcodehash). Slot is occupied.
        bytes32 uid2 = _submit(bob, chainId, extcodehash, keccak256("meta2"), keccak256("blob2"), 2);
        bytes32 key = registry.smtKey(chainId, extcodehash);
        bytes32[] memory siblings = smt.proof(key);

        vm.expectRevert(KaiSignRegistry.SlotAlreadyOccupied.selector);
        registry.finalize(uid2, siblings);
    }

    function test_revoke_clearsSlot_freshFinalizeAllowed() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("rev");

        // 1. Approve original.
        bytes32 uid1 = _submit(alice, chainId, extcodehash, keccak256("meta1"), keccak256("blob1"), 1);
        _finalizeApproved(uid1, chainId, extcodehash, keccak256("meta1"));
        bytes32 rootAfterFinalize = registry.smtRoot();

        // 2. Revoke it.
        vm.prank(bob);
        registry.proposeRevoke(uid1, BOND);
        _finalizeRevoke(uid1, chainId, extcodehash, keccak256("meta1"));

        assertEq(registry.smtRoot(), bytes32(0), "slot should be empty after revoke");
        assertTrue(registry.getAttestation(uid1).revoked);
        assertTrue(rootAfterFinalize != bytes32(0));

        // 3. After revoke, a brand-new submission for the same key may finalize.
        bytes32 uid2 = _submit(alice, chainId, extcodehash, keccak256("meta2"), keccak256("blob2"), 2);
        _finalizeApproved(uid2, chainId, extcodehash, keccak256("meta2"));
        assertEq(registry.smtRoot(), smt.root());
    }

    function test_revoke_makesOldProofNonVerifiable() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("hwwallet");
        bytes32 metadataHash = keccak256("meta");

        bytes32 uid = _submit(alice, chainId, extcodehash, metadataHash, keccak256("blob"), 1);
        _finalizeApproved(uid, chainId, extcodehash, metadataHash);

        // Capture proof a hardware wallet might have cached.
        bytes32 key = registry.smtKey(chainId, extcodehash);
        bytes32[] memory cachedProof = smt.proof(key);
        registry.verifyAttestation(chainId, extcodehash, metadataHash, cachedProof);

        // Revoke.
        vm.prank(bob);
        registry.proposeRevoke(uid, BOND);
        _finalizeRevoke(uid, chainId, extcodehash, metadataHash);

        // The exact same cached proof must now FAIL verification — that's the
        // whole point of the SMT migration.
        vm.expectRevert(KaiSignRegistry.InvalidSmtProof.selector);
        registry.verifyAttestation(chainId, extcodehash, metadataHash, cachedProof);
    }

    function test_finalize_proofTampering_reverts() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("tamper");
        bytes32 metadataHash = keccak256("meta");
        bytes32 uid = _submit(alice, chainId, extcodehash, metadataHash, keccak256("blob"), 1);

        bytes32 key = registry.smtKey(chainId, extcodehash);
        bytes32[] memory siblings = smt.proof(key);
        // Corrupt one sibling.
        siblings[100] = keccak256("garbage");

        vm.expectRevert(KaiSignRegistry.SlotAlreadyOccupied.selector);
        registry.finalize(uid, siblings);
    }

    function test_finalize_wrongLengthSiblings_reverts() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("short");
        bytes32 uid = _submit(alice, chainId, extcodehash, keccak256("meta"), keccak256("blob"), 1);

        bytes32[] memory siblings = new bytes32[](10);
        vm.expectRevert(KaiSignRegistry.SlotAlreadyOccupied.selector);
        registry.finalize(uid, siblings);
    }

    function test_verifySmtProof_nonMembership() public view {
        // Tree is empty. Non-membership of any key under the empty root must verify
        // because every sibling is bytes32(0) and hashing two zeros yields zero.
        bytes32 key = registry.smtKey(42, keccak256("never"));
        bytes32[] memory siblings = new bytes32[](256);
        assertTrue(registry.verifySmtProof(key, bytes32(0), siblings, bytes32(0)));
        // ...and membership of a non-zero leaf under empty root must NOT verify.
        assertFalse(
            registry.verifySmtProof(key, keccak256("anything"), siblings, bytes32(0))
        );
    }

    function test_finalize_rejectedReality_marksRevokedNoTreeUpdate() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("rejected");

        // Reality.eth answers NO for the next question.
        reality.setPendingResult(bytes32(uint256(0)));

        bytes32 uid = _submit(alice, chainId, extcodehash, keccak256("meta"), keccak256("blob"), 1);

        // Empty proof works as long as slot is empty AND we're on the rejection path —
        // but the rejection path returns before checking the proof. Pass any 256-len array.
        bytes32[] memory siblings = new bytes32[](256);
        registry.finalize(uid, siblings);

        assertTrue(registry.getAttestation(uid).revoked);
        assertEq(registry.smtRoot(), bytes32(0), "tree must not change on rejection");
    }

    function test_finalize_invalidReality_marksRevokedNoTreeUpdate() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("invalid");

        reality.setPendingResult(bytes32(type(uint256).max)); // INVALID

        bytes32 uid = _submit(alice, chainId, extcodehash, keccak256("meta"), keccak256("blob"), 1);
        bytes32[] memory siblings = new bytes32[](256);
        registry.finalize(uid, siblings);

        assertTrue(registry.getAttestation(uid).revoked);
        assertEq(registry.smtRoot(), bytes32(0));
    }

    function test_doubleFinalize_reverts() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("double");
        bytes32 metadataHash = keccak256("meta");
        bytes32 uid = _submit(alice, chainId, extcodehash, metadataHash, keccak256("blob"), 1);
        _finalizeApproved(uid, chainId, extcodehash, metadataHash);

        bytes32 key = registry.smtKey(chainId, extcodehash);
        bytes32[] memory siblings = smt.proof(key);
        vm.expectRevert(KaiSignRegistry.AlreadyFinalized.selector);
        registry.finalize(uid, siblings);
    }

    function test_migrate_setsRoot_andLocks() public {
        bytes32 imported = keccak256("precomputed root");
        registry.migrate(imported);
        assertEq(registry.smtRoot(), imported);
        assertTrue(registry.migrated());

        vm.expectRevert(KaiSignRegistry.AlreadyMigrated.selector);
        registry.migrate(keccak256("again"));
    }

    function test_migrate_zeroRoot_reverts() public {
        vm.expectRevert(KaiSignRegistry.InvalidRoot.selector);
        registry.migrate(bytes32(0));
    }

    function test_migrate_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.migrate(keccak256("x"));
    }

    function test_revoke_proofTampering_reverts() public {
        uint256 chainId = 1;
        bytes32 extcodehash = keccak256("revtamper");
        bytes32 metadataHash = keccak256("meta");
        bytes32 uid = _submit(alice, chainId, extcodehash, metadataHash, keccak256("blob"), 1);
        _finalizeApproved(uid, chainId, extcodehash, metadataHash);

        vm.prank(bob);
        registry.proposeRevoke(uid, BOND);

        bytes32 key = registry.smtKey(chainId, extcodehash);
        bytes32[] memory siblings = smt.proof(key);
        siblings[0] = keccak256("evil");

        vm.expectRevert(KaiSignRegistry.SlotNotApproved.selector);
        registry.finalizeRevoke(uid, siblings);
    }

    function test_threeIndependentKeys_helperAndContractAgree() public {
        // Stress: insert three keys, revoke the middle one, insert another. Roots
        // must stay in lock-step between contract and helper.
        bytes32[3] memory ext = [keccak256("X"), keccak256("Y"), keccak256("Z")];
        bytes32[3] memory meta = [keccak256("mX"), keccak256("mY"), keccak256("mZ")];
        bytes32[3] memory blob = [keccak256("bX"), keccak256("bY"), keccak256("bZ")];

        bytes32[3] memory uids;
        for (uint256 i = 0; i < 3; ++i) {
            uids[i] = _submit(alice, 1, ext[i], meta[i], blob[i], i + 1);
            _finalizeApproved(uids[i], 1, ext[i], meta[i]);
            assertEq(registry.smtRoot(), smt.root());
        }

        // Revoke Y.
        vm.prank(bob);
        registry.proposeRevoke(uids[1], BOND);
        _finalizeRevoke(uids[1], 1, ext[1], meta[1]);
        assertEq(registry.smtRoot(), smt.root());

        // Re-add Y with new metadata.
        bytes32 uidY2 = _submit(alice, 1, ext[1], keccak256("mY2"), keccak256("bY2"), 99);
        _finalizeApproved(uidY2, 1, ext[1], keccak256("mY2"));
        assertEq(registry.smtRoot(), smt.root());

        // X and Z should still verify against current root.
        bytes32 keyX = registry.smtKey(1, ext[0]);
        registry.verifyAttestation(1, ext[0], meta[0], smt.proof(keyX));
        bytes32 keyZ = registry.smtKey(1, ext[2]);
        registry.verifyAttestation(1, ext[2], meta[2], smt.proof(keyZ));
    }
}
