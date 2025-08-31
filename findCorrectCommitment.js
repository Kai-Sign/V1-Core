const { ethers } = require('ethers');

// The actual values from the commit transaction event
const ACTUAL_SENDER = '0x89839eF5911343a6134c28B96342f7fb3ae5D483';
const COMMITMENT_FROM_EVENT = '0xd7e81e9739dc954747aec34018cdbd3a1859d500522fa426b6c5e3efc3916be9'; 
const TARGET_CONTRACT = '0x054119c36e6c66029c3fBf3cE4979E54e3137b88';
const CHAIN_ID = 11155111;
const REVEAL_PERIOD_END = 1755959736; // From event

// Our blob hash and nonce
const BLOB_HASH = '0x018d49902c41b1bd2033ba7b25cfbf551ea8e6c57e0f89c2c1763c41e5698f5e';
const NONCE = 12345;

console.log('=== COMMITMENT DEBUG ===\n');

// The commitment in the script is calculated as:
const scriptCommitment = ethers.keccak256(ethers.solidityPacked(
    ['bytes32', 'uint256'],
    [BLOB_HASH, NONCE]
));

console.log('Script calculated commitment:', scriptCommitment);
console.log('Event logged commitment:', COMMITMENT_FROM_EVENT);
console.log('Match:', scriptCommitment === COMMITMENT_FROM_EVENT ? 'YES' : 'NO');

// The issue is the commitment doesn't match
// Let's try to find what would produce the event commitment

console.log('\n=== TRYING DIFFERENT CALCULATIONS ===\n');

// Maybe the order is different?
const reverseCommitment = ethers.keccak256(ethers.solidityPacked(
    ['uint256', 'bytes32'],
    [NONCE, BLOB_HASH]
));
console.log('Reverse order:', reverseCommitment);
console.log('Match:', reverseCommitment === COMMITMENT_FROM_EVENT ? 'YES' : 'NO');

// Maybe it's using different encoding?
const abiEncodedCommitment = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
    ['bytes32', 'uint256'],
    [BLOB_HASH, NONCE]
));
console.log('ABI encoded:', abiEncodedCommitment);
console.log('Match:', abiEncodedCommitment === COMMITMENT_FROM_EVENT ? 'YES' : 'NO');

console.log('\n=== SOLUTION ===');
console.log('The commitment in the event does not match our calculation.');
console.log('This means either:');
console.log('1. The script sent a different commitment than what it logged');
console.log('2. The blob hash or nonce is different');
console.log('3. There is a bug in the commitment calculation');

// Let's check the actual input data from the transaction
console.log('\n=== CHECKING TRANSACTION INPUT ===');
const inputData = '0xee5a7f6ef039b182f55c70e757c1082d5d87e85ae391fe9cb668b2c6a83065ce397b0fc5000000000000000000000000054119c36e6c66029c3fbf3ce4979e54e3137b880000000000000000000000000000000000000000000000000000000000aa36a7';

// Decode the function call
// commitSpec(bytes32,address,uint256)
const functionSelector = inputData.slice(0, 10); // 0xee5a7f6e
const commitment = '0x' + inputData.slice(10, 74);
const targetAddress = '0x' + inputData.slice(98, 138);
const chainId = '0x' + inputData.slice(138);

console.log('Function selector:', functionSelector);
console.log('Commitment from tx input:', commitment);
console.log('Target from tx input:', targetAddress);
console.log('Chain ID from tx input:', parseInt(chainId, 16));

console.log('\n=== THE PROBLEM ===');
console.log('Transaction sent commitment:', commitment);
console.log('Script logged commitment:', scriptCommitment);
console.log('Event logged commitment:', COMMITMENT_FROM_EVENT);

console.log('\nThe transaction sent', commitment);
console.log('But the event logged', COMMITMENT_FROM_EVENT);
console.log('These should match but they don\'t!');