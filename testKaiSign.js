const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function testKaiSign() {
    // Configuration
    const RPC_URL = 'https://eth-sepolia.g.alchemy.com/v2/1EFr4OH_BpQp-qxV_7Vv5';
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    
    const KAISIGN_ADDRESS = '0x054119c36e6c66029c3fBf3cE4979E54e3137b88';
    
    console.log('=== TESTING KAISIGN CONTRACT ===');
    console.log('Address:', KAISIGN_ADDRESS);
    
    // Check if contract exists
    const code = await provider.getCode(KAISIGN_ADDRESS);
    if (code === '0x') {
        console.error('ERROR: No contract at this address!');
        process.exit(1);
    }
    
    console.log('Contract exists!');
    console.log('Code length:', code.length, 'characters');
    
    // Read ABI
    const contractPath = path.join(__dirname, 'out/KaiSign.sol/KaiSign.json');
    const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
    
    // Create contract instance
    const kaisign = new ethers.Contract(KAISIGN_ADDRESS, contractJson.abi, provider);
    
    // Test some view functions
    console.log('\n=== CONTRACT STATE ===');
    
    try {
        const minBond = await kaisign.minBond();
        console.log('Min Bond:', ethers.formatEther(minBond), 'ETH');
    } catch (e) {
        console.log('Could not read minBond');
    }
    
    try {
        const commitPeriod = await kaisign.COMMIT_PERIOD();
        console.log('Commit Period:', commitPeriod.toString(), 'seconds');
    } catch (e) {
        console.log('Could not read COMMIT_PERIOD');
    }
    
    try {
        const revealPeriod = await kaisign.REVEAL_PERIOD();
        console.log('Reveal Period:', revealPeriod.toString(), 'seconds');
    } catch (e) {
        console.log('Could not read REVEAL_PERIOD');
    }
    
    // Check for any specs
    const TARGET_CONTRACT = '0x054119c36e6c66029c3fBf3cE4979E54e3137b88';
    const CHAIN_ID = 11155111;
    
    console.log('\n=== CHECKING FOR SPECS ===');
    console.log('Target Contract:', TARGET_CONTRACT);
    console.log('Chain ID:', CHAIN_ID);
    
    try {
        const specs = await kaisign.getSpecsByContract(TARGET_CONTRACT, CHAIN_ID);
        console.log('Number of specs:', specs.length);
        if (specs.length > 0) {
            console.log('Spec blob hashes:');
            specs.forEach((hash, i) => {
                console.log(`  ${i + 1}. ${hash}`);
            });
        }
    } catch (e) {
        console.log('Could not get specs:', e.message);
    }
    
    console.log('\n=== TEST COMPLETE ===');
}

// Run test
testKaiSign().catch(console.error);