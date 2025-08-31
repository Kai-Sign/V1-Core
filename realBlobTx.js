#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

async function sendRealBlobTx() {
    const PRIVATE_KEY = process.env.PRIVATE_KEY;
    if (!PRIVATE_KEY) {
        console.error('Set PRIVATE_KEY in .env');
        process.exit(1);
    }
    
    // Use the same Alchemy RPC you have
    const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    console.log('Deployer:', wallet.address);
    
    // Read metadata
    const metadata = JSON.parse(fs.readFileSync('kaisign-erc7730.json', 'utf8'));
    const dataStr = JSON.stringify(metadata);
    
    // Create blob content (4096 field elements, 31 bytes each)
    const FIELD_ELEMENTS = 4096;
    const BYTES_PER_FIELD = 31;
    const blob = new Uint8Array(FIELD_ELEMENTS * 32);
    
    const encoder = new TextEncoder();
    const dataBytes = encoder.encode(dataStr);
    
    // Pack data into field elements (31 bytes data + 1 byte padding)
    let dataIndex = 0;
    for (let i = 0; i < FIELD_ELEMENTS && dataIndex < dataBytes.length; i++) {
        const fieldStart = i * 32;
        const bytesToCopy = Math.min(BYTES_PER_FIELD, dataBytes.length - dataIndex);
        
        // First byte is 0 (field element must be < BLS modulus)
        blob[fieldStart] = 0;
        
        // Copy up to 31 bytes of data
        for (let j = 0; j < bytesToCopy; j++) {
            blob[fieldStart + 1 + j] = dataBytes[dataIndex++];
        }
    }
    
    console.log('Blob size:', blob.length, 'bytes');
    console.log('Data encoded:', dataIndex, 'bytes');
    
    // For blob transactions, we need:
    // 1. The blob data itself
    // 2. KZG commitment (48 bytes)
    // 3. KZG proof (48 bytes)
    // 4. Versioned hash (32 bytes starting with 0x01)
    
    // Since we don't have real KZG, create placeholder
    const commitment = new Uint8Array(48);
    const proof = new Uint8Array(48);
    
    // Create versioned hash from blob
    const blobHash = ethers.keccak256(blob);
    const versionedHash = '0x01' + blobHash.substring(4);
    
    console.log('Versioned hash:', versionedHash);
    
    const nonce = await wallet.getNonce();
    const feeData = await provider.getFeeData();
    
    // Type 3 transaction for blobs
    const tx = {
        type: 3,
        chainId: 11155111,
        nonce: nonce,
        to: null, // Blob transactions can have null recipient
        value: 0n,
        data: '0x',
        gasLimit: 21000n,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas || ethers.parseUnits('3', 'gwei'),
        maxFeePerGas: feeData.maxFeePerGas || ethers.parseUnits('100', 'gwei'),
        maxFeePerBlobGas: ethers.parseUnits('100', 'gwei'),
        blobVersionedHashes: [versionedHash],
        // These would be sent separately in the blob sidecar
        blobs: [blob],
        commitments: [commitment],
        proofs: [proof]
    };
    
    console.log('\nSending Type 3 blob transaction...');
    console.log('Gas prices:', {
        maxFeePerGas: ethers.formatUnits(tx.maxFeePerGas, 'gwei') + ' gwei',
        maxFeePerBlobGas: ethers.formatUnits(tx.maxFeePerBlobGas, 'gwei') + ' gwei'
    });
    
    try {
        // Try sending blob transaction directly
        const signedTx = await wallet.signTransaction(tx);
        console.log('Signed transaction created');
        
        // Try eth_sendRawTransaction first (standard method)
        try {
            const txHash = await provider.send('eth_sendRawTransaction', [signedTx]);
            console.log('✅ Transaction hash:', txHash);
            
            const receipt = await provider.waitForTransaction(txHash);
            console.log('Block:', receipt.blockNumber);
            console.log('Type:', receipt.type);
            console.log(`View: https://sepolia.etherscan.io/tx/${txHash}`);
            
            return;
        } catch (e1) {
            console.log('eth_sendRawTransaction failed:', e1.message);
        }
        
        // Try blob-specific method if raw transaction failed
        try {
            const result = await provider.send('eth_sendBlobTransaction', [{
                from: wallet.address,
                to: null,
                gas: '0x5208',
                maxFeePerGas: '0x' + tx.maxFeePerGas.toString(16),
                maxPriorityFeePerGas: '0x' + tx.maxPriorityFeePerGas.toString(16),
                maxFeePerBlobGas: '0x' + tx.maxFeePerBlobGas.toString(16),
                nonce: '0x' + tx.nonce.toString(16),
                value: '0x0',
                data: '0x',
                blobVersionedHashes: [versionedHash],
                blobs: ['0x' + Buffer.from(blob).toString('hex')],
                commitments: ['0x' + Buffer.from(commitment).toString('hex')],
                proofs: ['0x' + Buffer.from(proof).toString('hex')]
            }]);
            
            console.log('✅ Blob transaction hash:', result);
        } catch (e2) {
            console.log('eth_sendBlobTransaction failed:', e2.message);
            throw e2;
        }
        
    } catch (error) {
        console.error('\nError:', error.message);
        if (error.message.includes('Method not found')) {
            console.error('\n❌ This RPC does not support blob transactions');
            console.error('Sepolia supports blobs, but your RPC endpoint needs blob pool access');
        }
    }
}

sendRealBlobTx().catch(console.error);