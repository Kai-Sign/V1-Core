#!/usr/bin/env node

import { readFileSync, writeFileSync } from "fs";
import { resolve } from "path";
const phase = process.argv[2];

if (!phase || (phase !== "commit" && phase !== "reveal")) {
  console.error("usage: node script/sync-recovery-artifact.mjs <commit|reveal>");
  process.exit(1);
}

const config = {
  commit: {
    artifactPath: resolve("deployments/sepolia-recovery-commits.json"),
    broadcastPath: resolve("broadcast/BatchCommitRecovered.s.sol/11155111/run-latest.json"),
    txFunction: "commitSpec(bytes32,uint256,bytes32)",
    field: "commitmentId",
    topic0: "0xba9decf116c682e02aeb772378d0c1cb316160cad3062fdb63fd819ec581ce3b",
    topicIndex: 2,
  },
  reveal: {
    artifactPath: resolve("deployments/sepolia-recovery-reveals.json"),
    broadcastPath: resolve("broadcast/BatchRevealRecovered.s.sol/11155111/run-latest.json"),
    txFunction: "revealSpec(bytes32,bytes32,uint256,bytes32,uint256)",
    field: "uid",
    topic0: "0x77d5bd03367e2501e50b37419c884872869d3d700d7af4eeae52d3f26e8c2a88",
    topicIndex: 2,
  },
}[phase];

const artifact = JSON.parse(readFileSync(config.artifactPath, "utf8"));
const broadcast = JSON.parse(readFileSync(config.broadcastPath, "utf8"));

const txs = broadcast.transactions.filter((tx) => tx.function === config.txFunction);
if (txs.length !== artifact.entries.length) {
  console.error(
    `mismatched counts: artifact=${artifact.entries.length} txs=${txs.length}`
  );
  process.exit(1);
}

for (let i = 0; i < artifact.entries.length; i += 1) {
  const tx = txs[i];
  const receipt = broadcast.receipts.find(
    (entry) => entry.transactionHash.toLowerCase() === tx.hash.toLowerCase()
  );

  if (!receipt) {
    console.error(`missing receipt for ${phase} tx ${tx.hash}`);
    process.exit(1);
  }

  const log = receipt.logs.find(
    (entry) =>
      entry.address.toLowerCase() === artifact.registry.toLowerCase() &&
      entry.topics[0].toLowerCase() === config.topic0.toLowerCase()
  );

  if (!log) {
    console.error(`missing ${phase} event log for entry ${i}`);
    process.exit(1);
  }

  artifact.entries[i][config.field] = log.topics[config.topicIndex];
}

writeFileSync(config.artifactPath, JSON.stringify(artifact, null, 2) + "\n");
console.log(`synced ${phase} artifact: ${config.artifactPath}`);
