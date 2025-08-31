const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function debugCommitment() {
    const RPC_URL = 'https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5';
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    
    const KAISIGN_ADDRESS = '0x054119c36e6c66029c3fBf3cE4979E54e3137b88';
    const BLOB_HASH = '0x018d49902c41b1bd2033ba7b25cfbf551ea8e6c57e0f89c2c1763c41e5698f5e';
    const NONCE = 12345;
    const TARGET_CONTRACT = '0x054119c36e6c66029c3fBf3cE4979E54e3137b88';
    const CHAIN_ID = 11155111;
    const DEPLOYER = '0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38';
    
    // Transaction details from your commit
    const TX_HASH = '0x77e3d79105f74d09d2ac0e802574da38e8a9e8e5e1c7f5f6eccda6e0fdeb722d';
    const BLOCK_NUMBER = 9047102;
    
    console.log('=== DEBUGGING COMMITMENT ===\n');
    
    // Get the transaction
    const tx = await provider.getTransaction(TX_HASH);
    console.log('Transaction:', TX_HASH);
    console.log('Block:', tx.blockNumber);
    
    // Get the block to get exact timestamp
    const block = await provider.getBlock(tx.blockNumber);
    console.log('Block Timestamp:', block.timestamp);
    console.log('Converted:', new Date(block.timestamp * 1000).toISOString());
    
    // Calculate commitment
    const commitment = ethers.keccak256(ethers.solidityPacked(
        ['bytes32', 'uint256'],
        [BLOB_HASH, NONCE]
    ));
    console.log('\nCommitment:', commitment);
    
    // Calculate commitment ID using block timestamp
    const commitmentId = ethers.keccak256(ethers.solidityPacked(
        ['bytes32', 'address', 'address', 'uint256', 'uint64'],
        [commitment, DEPLOYER, TARGET_CONTRACT, CHAIN_ID, block.timestamp]
    ));
    
    console.log('\nCalculated Commitment ID:', commitmentId);
    console.log('Expected ID:', '0x71353384f6de97eef523b625ef8593817b1a3ee8397f5fcaa7ff41933f9f0e9a');
    console.log('Match:', commitmentId === '0x71353384f6de97eef523b625ef8593817b1a3ee8397f5fcaa7ff41933f9f0e9a');
    
    // Read contract ABI
    const contractPath = path.join(__dirname, 'out/KaiSign.sol/KaiSign.json');
    const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
    const kaisign = new ethers.Contract(KAISIGN_ADDRESS, contractJson.abi, provider);
    
    // Try to read the commitment from storage
    console.log('\n=== CHECKING CONTRACT STORAGE ===');
    
    // Get transaction receipt to check events
    const receipt = await provider.getTransactionReceipt(TX_HASH);
    console.log('Transaction Status:', receipt.status === 1 ? 'Success' : 'Failed');
    console.log('Events emitted:', receipt.logs.length);
    
    if (receipt.logs.length > 0) {
        console.log('\nEvent logs:');
        for (const log of receipt.logs) {
            try {
                const parsed = kaisign.interface.parseLog(log);
                console.log('Event:', parsed.name);
                console.log('Args:', parsed.args);
            } catch (e) {
                console.log('Raw log:', log);
            }
        }
    }
    
    console.log('\n=== COMMITMENT DETAILS ===');
    console.log('Use this for reveal:');
    console.log(`export COMMITMENT_ID=${commitmentId}`);
    console.log(`\nOr run:`);
    console.log(`forge script script/RevealBlob.s.sol:RevealBlob --rpc-url ${RPC_URL} --keystore $HOME/.foundry/keystores/kaisignblob --broadcast --value 0.01ether -vvv`);
}

debugCommitment().catch(console.error);