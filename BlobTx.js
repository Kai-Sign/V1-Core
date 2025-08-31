#!/usr/bin/env node

// ACTUAL WORKING BLOB TRANSACTION
// Based on Viem's implementation pattern adapted for ethers.js

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const cKzg = require('c-kzg');
require('dotenv').config();

// Initialize KZG with the default trusted setup
// The first argument is the number of G1 points to precompute (0 = default)
// The second argument is the path to trusted setup file
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

async function sendActualBlobTx() {
    const PRIVATE_KEY = process.env.PRIVATE_KEY;
    if (!PRIVATE_KEY) {
        console.error('Set PRIVATE_KEY in environment');
        process.exit(1);
    }
    
    // Create provider and wallet
    const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    console.log('Deployer:', wallet.address);
    
    // Read and prepare data
    const metadata = JSON.parse(fs.readFileSync('kaisign-erc7730.json', 'utf8'));
    const dataStr = JSON.stringify(metadata);
    console.log('Data size:', dataStr.length, 'bytes');
    
    // Convert to blob
    const blob = toBlobs(dataStr);
    console.log('Blob created:', blob.length, 'bytes');
    
    // Generate KZG commitment and proof
    const commitment = cKzg.blobToKzgCommitment(blob);
    const proof = cKzg.computeBlobKzgProof(blob, commitment);
    
    // Verify the proof is valid
    const isValid = cKzg.verifyBlobKzgProof(blob, commitment, proof);
    console.log('KZG proof valid:', isValid);
    
    if (!isValid) {
        console.error('Invalid KZG proof!');
        process.exit(1);
    }
    
    // Create versioned hash
    const commitmentHash = ethers.sha256(commitment);
    const versionedHash = '0x01' + commitmentHash.substring(4);
    
    console.log('Commitment:', ethers.hexlify(commitment));
    console.log('Versioned hash:', versionedHash);
    
    // Get nonce and fees
    const nonce = await wallet.getNonce();
    const baseFee = (await provider.getBlock('latest')).baseFeePerGas;
    
    console.log('\nTransaction details:');
    console.log('Nonce:', nonce);
    console.log('Base fee:', ethers.formatUnits(baseFee, 'gwei'), 'gwei');
    
    // Create the transaction
    // IMPORTANT: ethers.js v6 requires the blobs/commitments/proofs in a specific format
    const tx = {
        type: 3,
        to: '0x0000000000000000000000000000000000000000',
        data: '0x',
        value: 0n,
        chainId: 11155111,
        nonce: nonce,
        gasLimit: 21000n,
        maxPriorityFeePerGas: ethers.parseUnits('1', 'gwei'),
        maxFeePerGas: ethers.parseUnits('50', 'gwei'), // Fixed value high enough
        maxFeePerBlobGas: ethers.parseUnits('30', 'gwei'),
        blobVersionedHashes: [versionedHash]
    };
    
    // For ethers.js v6.15+, we need to attach the KZG object and blob data
    // Ethers expects the kzg library to be passed as a property
    const txWithSidecar = {
        ...tx,
        // Pass the KZG library instance
        kzg: cKzg,
        // Pass the blob data
        blobs: [blob]
    };
    
    try {
        console.log('\nSending Type 3 blob transaction...');
        
        // Method 1: Try sending with ethers.js native support
        try {
            const txResponse = await wallet.sendTransaction(txWithSidecar);
            console.log('✅ Transaction sent:', txResponse.hash);
            
            const receipt = await txResponse.wait();
            console.log('\n🎉 SUCCESS!');
            console.log('Block:', receipt.blockNumber);
            console.log('Type:', receipt.type);
            console.log('Blob gas used:', receipt.blobGasUsed);
            console.log(`View: https://sepolia.etherscan.io/tx/${receipt.hash}`);
            
            return;
        } catch (e1) {
            console.log('ethers.js native method failed:', e1.message);
        }
        
        // Method 2: Try raw RPC call with proper formatting
        console.log('\nTrying raw RPC method...');
        
        // Sign the base transaction (without sidecar)
        const signedTx = await wallet.signTransaction(tx);
        
        // For blob transactions, we need to send the network format:
        // rlp([tx_payload_body, blobs, commitments, proofs])
        // This requires custom encoding beyond what ethers provides
        
        console.log('Signed transaction created');
        console.log('Note: Standard RPC endpoints may not support blob transactions');
        console.log('You need an RPC endpoint with blob pool support');
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        
        if (error.message.includes('kzg') || error.message.includes('KZG')) {
            console.error('\nThe issue is with KZG setup or blob formatting');
            console.error('Ethers.js v6 blob support requires:');
            console.error('1. Proper KZG library initialization');
            console.error('2. Correct blob data format (4096 field elements)');
            console.error('3. Valid commitments and proofs');
            console.error('4. RPC endpoint with blob pool support');
        }
    }
}

sendActualBlobTx().catch(console.error);