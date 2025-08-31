#!/usr/bin/env node

// THREE-PHASE BLOB TRANSACTION WITH COMMIT-REVEAL
// Phase 1: Commit to metadata hash
// Phase 2: Post blob with metadata
// Phase 3: Reveal to claim ownership

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const cKzg = require('c-kzg');
require('dotenv').config();

// Initialize KZG with the default trusted setup
cKzg.loadTrustedSetup(0, cKzg.DEFAULT_TRUSTED_SETUP_PATH);

// Convert data to blob format
function toBlobs(data) {
    const BLOB_SIZE = 131072; // 4096 * 32
    const blob = new Uint8Array(BLOB_SIZE);
    
    const bytes = Buffer.from(data);
    let blobIndex = 0;
    
    // Each field element is 32 bytes, with first byte 0 for BLS modulus
    for (let i = 0; i < bytes.length; i++) {
        const fieldIndex = Math.floor(blobIndex / 31);
        const byteIndex = blobIndex % 31;
        
        if (fieldIndex >= 4096) break;
        
        blob[fieldIndex * 32 + byteIndex + 1] = bytes[i];
        blobIndex++;
    }
    
    return blob;
}

async function threePhaseBlob() {
    // Setup
    const PRIVATE_KEY = process.env.PRIVATE_KEY;
    if (!PRIVATE_KEY) {
        console.error('Set PRIVATE_KEY in environment');
        process.exit(1);
    }
    
    const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    // Contract setup - update with your deployed address
    const KAISIGN_ADDRESS = process.env.KAISIGN_ADDRESS || '0x...'; // UPDATE THIS
    const kaisignABI = [
        'function commitSpec(bytes32 commitment, address targetContract, uint256 targetChainId)',
        'function revealSpec(bytes32 commitmentId, bytes32 blobHash, bytes32 metadataHash, uint256 nonce) payable returns (bytes32)',
        'event LogCommitSpec(address indexed committer, bytes32 indexed commitmentId, address indexed targetContract, uint256 chainId, uint256 bondAmount, uint64 revealDeadline)'
    ];
    const kaisign = new ethers.Contract(KAISIGN_ADDRESS, kaisignABI, wallet);
    
    console.log('=== THREE-PHASE BLOB POSTING ===');
    console.log('Wallet:', wallet.address);
    console.log('KaiSign:', KAISIGN_ADDRESS);
    
    // Read metadata
    const metadata = JSON.parse(fs.readFileSync('kaisign-erc7730.json', 'utf8'));
    const metadataStr = JSON.stringify(metadata);
    
    // Calculate hashes
    const metadataHash = ethers.keccak256(ethers.toUtf8Bytes(metadataStr));
    const nonce = ethers.hexlify(ethers.randomBytes(32));
    const commitment = ethers.keccak256(ethers.solidityPacked(
        ['bytes32', 'uint256'],
        [metadataHash, nonce]
    ));
    
    console.log('\n📝 Metadata Hash:', metadataHash);
    console.log('🎲 Nonce:', nonce);
    console.log('🔒 Commitment:', commitment);
    
    // === PHASE 1: COMMIT ===
    console.log('\n=== PHASE 1: COMMIT ===');
    const targetContract = '0x0000000000000000000000000000000000000000'; // Example target
    const targetChainId = 11155111; // Sepolia
    
    try {
        console.log('Submitting commitment...');
        const commitTx = await kaisign.commitSpec(
            commitment,
            targetContract,
            targetChainId
        );
        
        console.log('Commit TX:', commitTx.hash);
        const commitReceipt = await commitTx.wait();
        console.log('✅ Commitment confirmed in block:', commitReceipt.blockNumber);
        
        // Extract commitmentId from events
        const commitEvent = commitReceipt.logs.find(
            log => log.topics[0] === ethers.id('LogCommitSpec(address,bytes32,address,uint256,uint256,uint64)')
        );
        const commitmentId = commitEvent.topics[2]; // indexed commitmentId
        console.log('📍 Commitment ID:', commitmentId);
        
        // Save commit data for later phases
        const commitData = {
            commitmentId,
            commitment,
            metadataHash,
            nonce,
            targetContract,
            targetChainId,
            commitBlock: commitReceipt.blockNumber,
            timestamp: new Date().toISOString()
        };
        
        fs.writeFileSync('commit-data.json', JSON.stringify(commitData, null, 2));
        console.log('💾 Commit data saved to commit-data.json');
        
    } catch (error) {
        console.error('❌ Commit failed:', error.message);
        process.exit(1);
    }
    
    // === PHASE 2: POST BLOB ===
    console.log('\n=== PHASE 2: POST BLOB ===');
    console.log('Waiting 10 seconds before posting blob...');
    await new Promise(resolve => setTimeout(resolve, 10000));
    
    // Prepare blob
    const blob = toBlobs(metadataStr);
    const blobCommitment = cKzg.blobToKzgCommitment(blob);
    const proof = cKzg.computeBlobKzgProof(blob, blobCommitment);
    
    // Verify proof
    const isValid = cKzg.verifyBlobKzgProof(blob, blobCommitment, proof);
    console.log('KZG proof valid:', isValid);
    
    if (!isValid) {
        console.error('Invalid KZG proof!');
        process.exit(1);
    }
    
    // Create versioned hash
    const commitmentHash = ethers.sha256(blobCommitment);
    const versionedHash = '0x01' + commitmentHash.substring(4);
    console.log('Blob versioned hash:', versionedHash);
    
    // Create blob transaction
    const blobTx = {
        type: 3,
        to: '0x0000000000000000000000000000000000000000', // Data storage
        data: '0x',
        value: 0n,
        chainId: 11155111,
        nonce: await wallet.getNonce(),
        gasLimit: 21000n,
        maxPriorityFeePerGas: ethers.parseUnits('1', 'gwei'),
        maxFeePerGas: ethers.parseUnits('50', 'gwei'),
        maxFeePerBlobGas: ethers.parseUnits('30', 'gwei'),
        blobVersionedHashes: [versionedHash],
        kzg: cKzg,
        blobs: [blob]
    };
    
    try {
        console.log('Sending blob transaction...');
        const blobTxResponse = await wallet.sendTransaction(blobTx);
        console.log('Blob TX:', blobTxResponse.hash);
        
        const blobReceipt = await blobTxResponse.wait();
        console.log('✅ Blob posted in block:', blobReceipt.blockNumber);
        console.log('Blob gas used:', blobReceipt.blobGasUsed);
        
        // Update commit data with blob info
        const commitData = JSON.parse(fs.readFileSync('commit-data.json'));
        commitData.blobHash = versionedHash;
        commitData.blobTxHash = blobReceipt.hash;
        commitData.blobBlock = blobReceipt.blockNumber;
        fs.writeFileSync('commit-data.json', JSON.stringify(commitData, null, 2));
        
    } catch (error) {
        console.error('❌ Blob posting failed:', error.message);
        console.error('Note: Blob transactions require special RPC support');
        // For testing, we'll continue with a dummy blob hash
        const commitData = JSON.parse(fs.readFileSync('commit-data.json'));
        commitData.blobHash = versionedHash; // Use calculated hash even if TX failed
        fs.writeFileSync('commit-data.json', JSON.stringify(commitData, null, 2));
    }
    
    // === PHASE 3: REVEAL ===
    console.log('\n=== PHASE 3: REVEAL ===');
    console.log('Waiting 10 seconds before revealing...');
    await new Promise(resolve => setTimeout(resolve, 10000));
    
    // Load commit data
    const savedData = JSON.parse(fs.readFileSync('commit-data.json'));
    
    try {
        console.log('Revealing commitment...');
        const revealTx = await kaisign.revealSpec(
            savedData.commitmentId,
            savedData.blobHash,
            savedData.metadataHash,
            savedData.nonce,
            { value: ethers.parseEther('0.01') } // Bond amount
        );
        
        console.log('Reveal TX:', revealTx.hash);
        const revealReceipt = await revealTx.wait();
        console.log('✅ Reveal confirmed in block:', revealReceipt.blockNumber);
        
        // Extract specID from return value or events
        console.log('\n🎉 SUCCESS! You have claimed ownership of this metadata.');
        console.log('📋 Summary:');
        console.log('  - Metadata Hash:', savedData.metadataHash);
        console.log('  - Blob Hash:', savedData.blobHash);
        console.log('  - Commit Block:', savedData.commitBlock);
        console.log('  - Reveal Block:', revealReceipt.blockNumber);
        
    } catch (error) {
        console.error('❌ Reveal failed:', error.message);
        if (error.message.includes('Metadata already claimed')) {
            console.error('Someone else committed to this metadata before you!');
        }
    }
}

// Run the three-phase process
threePhaseBlob().catch(console.error);