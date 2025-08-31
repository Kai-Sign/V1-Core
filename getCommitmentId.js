const { ethers } = require('ethers');

// Connect to Sepolia
const provider = new ethers.JsonRpcProvider('https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5');

// Transaction hash from the commit
const txHash = '0x9cb56a0ff45e10ca4ddac75a0268cef239ba4be16150a27e4ccf0ad750fb02f9';

// Constants
const METADATA_HASH = '0xb269bee2273ffe631057a429f0aed9a094c89c5038ed014aa8abee2bcd991f17';
const NONCE = 12345;
const TARGET_CONTRACT = '0x4dFEA0C2B472a14cD052a8f9DF9f19fa5CF03719';
const CHAIN_ID = 11155111;
const COMMITTER = '0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38';

async function getCommitmentId() {
    // Get the transaction receipt to find the block
    const receipt = await provider.getTransactionReceipt(txHash);
    console.log('Transaction Block:', receipt.blockNumber);
    
    // Get the block to get the timestamp
    const block = await provider.getBlock(receipt.blockNumber);
    console.log('Block Timestamp:', block.timestamp);
    
    // Calculate commitment (metadataHash + nonce)
    const commitment = ethers.keccak256(
        ethers.solidityPacked(['bytes32', 'uint256'], [METADATA_HASH, NONCE])
    );
    console.log('Commitment:', commitment);
    
    // Calculate commitment ID
    const commitmentId = ethers.keccak256(
        ethers.solidityPacked(
            ['bytes32', 'address', 'address', 'uint256', 'uint64'],
            [commitment, COMMITTER, TARGET_CONTRACT, CHAIN_ID, block.timestamp]
        )
    );
    
    console.log('\n=== COMMITMENT DETAILS ===');
    console.log('Commitment:', commitment);
    console.log('Committer:', COMMITTER);
    console.log('Target Contract:', TARGET_CONTRACT);
    console.log('Chain ID:', CHAIN_ID);
    console.log('Timestamp:', block.timestamp);
    console.log('\n=== RESULT ===');
    console.log('Commitment ID:', commitmentId);
    
    // Also check the event logs
    const logs = receipt.logs;
    console.log('\n=== EVENT LOGS ===');
    for (const log of logs) {
        if (log.topics.length > 2) {
            console.log('Event CommitmentId from logs:', log.topics[2]);
        }
    }
}

getCommitmentId().catch(console.error);