// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KaiSignRegistry.sol";
import "../src/PermissionedBToken.sol";

contract ProposeRevokeStEthEither is Script {
    uint256 internal constant MAINNET_CHAIN_ID = 1;
    bytes32 internal constant STETH_EXTCODEHASH =
        0xb9c1c929064cd21734c102a698e68bf617feefcfa5a9f62407c45401546736bf;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address registryAddr = vm.envOr("REGISTRY", address(0xb910E44893713b072ABC6949fB4441ad09999bC6));

        KaiSignRegistry registry = KaiSignRegistry(registryAddr);
        PermissionedBToken token = PermissionedBToken(address(registry.bondToken()));
        uint256 minBond = registry.minBond();

        bytes32[] memory uids = registry.getSpecsForBytecode(MAINNET_CHAIN_ID, STETH_EXTCODEHASH);
        require(uids.length != 0, "no stETH specs found");

        bytes32 chosenUid;
        IKaiSignRegistry.Attestation memory chosenAtt;

        console.log("=== PROPOSE REVOKE stETH ===");
        console.log("Registry:", registryAddr);
        console.log("Bond token:", address(token));
        console.log("Min bond:", minBond);
        console.log("Candidate specs:", uids.length);

        for (uint256 i = 0; i < uids.length; ++i) {
            IKaiSignRegistry.Attestation memory att = registry.getAttestation(uids[i]);
            console.log("Candidate UID:");
            console.logBytes32(uids[i]);
            console.log("  idx:", att.idx);
            console.log("  finalizedAt:", att.finalizedAt);
            console.log("  revoked:", att.revoked);
            console.log("  revokeProposedAt:", att.revokeProposedAt);

            if (att.finalizedAt != 0 && !att.revoked && att.revokeProposedAt == 0) {
                chosenUid = uids[i];
                chosenAtt = att;
                break;
            }
        }

        require(chosenUid != bytes32(0), "no finalized revokable stETH attestation");

        address sender = vm.addr(privateKey);
        uint256 balance = token.balanceOf(sender);
        uint256 allowance = token.allowance(sender, registryAddr);

        console.log("Selected UID:");
        console.logBytes32(chosenUid);
        console.log("Selected idx:", chosenAtt.idx);
        console.log("Sender:", sender);
        console.log("Sender balance:", balance);
        console.log("Sender allowance:", allowance);

        require(balance >= minBond, "insufficient bond token balance");

        vm.startBroadcast(privateKey);
        if (allowance < minBond) {
            token.approve(registryAddr, type(uint256).max);
            console.log("Approved registry for bond token");
        }

        registry.proposeRevoke(chosenUid, minBond);
        vm.stopBroadcast();

        IKaiSignRegistry.Attestation memory afterAtt = registry.getAttestation(chosenUid);
        (bytes32 questionId,) = registry.revokeQuestions(chosenUid);

        console.log("Revoke proposed for UID:");
        console.logBytes32(chosenUid);
        console.log("Question ID:");
        console.logBytes32(questionId);
        console.log("revokeProposedAt:", afterAtt.revokeProposedAt);
        console.log("revokeAttempt:", afterAtt.revokeAttempt);
    }
}
