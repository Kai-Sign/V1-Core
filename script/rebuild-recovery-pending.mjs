#!/usr/bin/env node

import { readFileSync, readdirSync, writeFileSync } from "fs";
import path from "path";

const root = process.cwd();
const seed = JSON.parse(readFileSync(path.join(root, "script/seed-frontier.json"), "utf8"));
const deploy = JSON.parse(readFileSync(path.join(root, "deployments/sepolia.json"), "utf8"));

const revealDir = path.join(root, "broadcast/BatchRevealRecovered.s.sol/11155111");
const voteDir = path.join(root, "broadcast/BatchVoteRecovered.s.sol/11155111");
const outPath = path.join(root, "deployments/sepolia-recovery-pending.json");

const revealRuns = readdirSync(revealDir)
  .filter((name) => /^run-\d+\.json$/.test(name))
  .sort();
const voteRuns = readdirSync(voteDir)
  .filter((name) => /^run-\d+\.json$/.test(name))
  .sort();

const batchStarts = [281, 286, 291, 296, 301, 306];

if (revealRuns.length < batchStarts.length || voteRuns.length < batchStarts.length) {
  throw new Error(`missing runs: reveal=${revealRuns.length} vote=${voteRuns.length}`);
}

const revealTopic0 = "0x77d5bd03367e2501e50b37419c884872869d3d700d7af4eeae52d3f26e8c2a88";
const entries = [];
const seenTargets = new Map();

for (let batch = 0; batch < batchStarts.length; batch += 1) {
  const startIdx = batchStarts[batch];
  const revealRun = JSON.parse(readFileSync(path.join(revealDir, revealRuns[batch]), "utf8"));
  const voteRun = JSON.parse(readFileSync(path.join(voteDir, voteRuns[batch]), "utf8"));

  const revealTxs = revealRun.transactions.filter((tx) => tx.function === "revealSpec(bytes32,bytes32,uint256,bytes32,uint256)");
  const voteTxs = voteRun.transactions.filter((tx) => tx.function === "submitAnswerERC20(bytes32,bytes32,uint256,uint256)");

  if (revealTxs.length !== 5 || voteTxs.length !== 5) {
    throw new Error(`unexpected tx count in batch ${startIdx}: reveal=${revealTxs.length} vote=${voteTxs.length}`);
  }

  for (let i = 0; i < 5; i += 1) {
    const seedLeaf = seed.leaves[startIdx - 1 + i];
    const revealTx = revealTxs[i];
    const revealReceipt = revealRun.receipts.find((r) => r.transactionHash.toLowerCase() === revealTx.hash.toLowerCase());
    const revealLog = revealReceipt.logs.find(
      (log) =>
        log.address.toLowerCase() === deploy.contracts.kaiSignRegistry.toLowerCase() &&
        log.topics[0].toLowerCase() === revealTopic0
    );

    if (!revealLog) {
      throw new Error(`missing reveal log for idx ${seedLeaf.idx}`);
    }

    const voteTx = voteTxs[i];
    const questionId = voteTx.arguments[0];

    entries.push({
      path: seedLeaf.path,
      idx: seedLeaf.idx,
      chainId: seedLeaf.chainId,
      extcodehash: seedLeaf.extcodehash,
      metadataHash: seedLeaf.metadataHash,
      uid: revealLog.topics[2],
      questionId
    });

    const targetKey = `${seedLeaf.chainId}:${seedLeaf.extcodehash.toLowerCase()}`;
    const prev = seenTargets.get(targetKey);
    if (prev) {
      throw new Error(
        `duplicate pending target for chainId=${seedLeaf.chainId} extcodehash=${seedLeaf.extcodehash}: ` +
        `${prev.path} (idx ${prev.idx}) overlaps ${seedLeaf.path} (idx ${seedLeaf.idx})`
      );
    }
    seenTargets.set(targetKey, { path: seedLeaf.path, idx: seedLeaf.idx });
  }
}

const out = {
  registry: deploy.contracts.kaiSignRegistry,
  realityETH: deploy.contracts.realityETH_ERC20_instance,
  btoken: deploy.contracts.permissionedBToken,
  startIdx: 281,
  endIdx: 310,
  count: entries.length,
  entries
};

writeFileSync(outPath, JSON.stringify(out, null, 2) + "\n");
console.log(`wrote ${outPath} with ${entries.length} entries`);
