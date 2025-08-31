const { ethers } = require('ethers');

// Values from the transaction
const commitment = '0xf039b182f55c70e757c1082d5d87e85ae391fe9cb668b2c6a83065ce397b0fc5'; // From tx input
const sender = '0x89839eF5911343a6134c28B96342f7fb3ae5D483'; // From event
const targetContract = '0x054119c36e6c66029c3fBf3cE4979E54e3137b88';
const targetChainId = 11155111;

// Block timestamp from the transaction
const blockTimestamp = 1755956136; // From the block

console.log('=== VERIFYING COMMITMENT ID ===\n');

// Calculate commitmentId as the contract does
const commitmentId = ethers.keccak256(ethers.solidityPacked(
    ['bytes32', 'address', 'address', 'uint256', 'uint64'],
    [commitment, sender, targetContract, targetChainId, blockTimestamp]
));

console.log('Calculated commitmentId:', commitmentId);
console.log('Event commitmentId:', '0xd7e81e9739dc954747aec34018cdbd3a1859d500522fa426b6c5e3efc3916be9');
console.log('Match:', commitmentId === '0xd7e81e9739dc954747aec34018cdbd3a1859d500522fa426b6c5e3efc3916be9' ? 'YES!' : 'NO');

console.log('\n=== THIS IS THE COMMITMENT ID TO USE FOR REVEAL ===');
console.log(commitmentId);

console.log('\n=== REVEAL COMMAND ===');
console.log(`export COMMITMENT_ID=${commitmentId}`);
console.log(`forge script script/RevealBlob.s.sol:RevealBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 --keystore $HOME/.foundry/keystores/kaisignblob --broadcast --value 0.01ether -vvv`);