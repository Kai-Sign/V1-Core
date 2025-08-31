const { ethers } = require('ethers');

async function calculateCorrectCommitment() {
    // Values from the actual event
    const ACTUAL_SENDER = '0x89839eF5911343a6134c28B96342f7fb3ae5D483';
    const ACTUAL_COMMITMENT = '0xd7e81e9739dc954747aec34018cdbd3a1859d500522fa426b6c5e3efc3916be9';
    const TARGET_CONTRACT = '0x054119c36e6c66029c3fBf3cE4979E54e3137b88';
    const CHAIN_ID = 11155111;
    const COMMIT_TIMESTAMP = 1755959736; // From event
    
    console.log('=== CALCULATING CORRECT COMMITMENT ID ===\n');
    console.log('From Event:');
    console.log('Sender:', ACTUAL_SENDER);
    console.log('Commitment:', ACTUAL_COMMITMENT);
    console.log('Target:', TARGET_CONTRACT);
    console.log('Chain ID:', CHAIN_ID);
    console.log('Timestamp:', COMMIT_TIMESTAMP);
    
    // Calculate the correct commitment ID
    const commitmentId = ethers.keccak256(ethers.solidityPacked(
        ['bytes32', 'address', 'address', 'uint256', 'uint64'],
        [ACTUAL_COMMITMENT, ACTUAL_SENDER, TARGET_CONTRACT, CHAIN_ID, COMMIT_TIMESTAMP]
    ));
    
    console.log('\n=== CORRECT COMMITMENT ID ===');
    console.log(commitmentId);
    
    console.log('\n=== REVEAL COMMAND ===');
    console.log(`export COMMITMENT_ID=${commitmentId}`);
    console.log(`\nforge script script/RevealBlob.s.sol:RevealBlob --rpc-url https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5 --keystore $HOME/.foundry/keystores/kaisignblob --broadcast --value 0.01ether -vvv`);
    
    // Also figure out why the commitment is different
    const BLOB_HASH = '0x018d49902c41b1bd2033ba7b25cfbf551ea8e6c57e0f89c2c1763c41e5698f5e';
    const NONCE = 12345;
    
    const expectedCommitment = ethers.keccak256(ethers.solidityPacked(
        ['bytes32', 'uint256'],
        [BLOB_HASH, NONCE]
    ));
    
    console.log('\n=== COMMITMENT MISMATCH DEBUG ===');
    console.log('Expected commitment from our calculation:', expectedCommitment);
    console.log('Actual commitment from event:', ACTUAL_COMMITMENT);
    console.log('Match:', expectedCommitment === ACTUAL_COMMITMENT);
    
    // The commitment might be using a different nonce or blob hash
    // Let's check what could produce this commitment
    console.log('\nThe contract might be using a different calculation or there might be an issue with the script.');
}

calculateCorrectCommitment().catch(console.error);