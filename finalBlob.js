#!/usr/bin/env node

// FINAL WORKING BLOB TRANSACTION
const { ethers, Transaction } = require('ethers');
const fs = require('fs');
const cKzg = require('c-kzg');
require('dotenv').config();

// Initialize KZG
cKzg.loadTrustedSetup(0, cKzg.DEFAULT_TRUSTED_SETUP_PATH);

async function sendFinalBlobTx() {
    const PRIVATE_KEY = process.env.PRIVATE_KEY;
    if (!PRIVATE_KEY) {
        console.error('Set PRIVATE_KEY in environment');
        process.exit(1);
    }
    
    const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    console.log('Deployer:', wallet.address);
    
    // Read metadata
    const metadata = JSON.parse(fs.readFileSync('kaisign-erc7730.json', 'utf8'));
    const dataStr = JSON.stringify(metadata);
    
    // Create blob (131072 bytes exactly)
    const BLOB_SIZE = 131072;
    const blob = new Uint8Array(BLOB_SIZE);
    const encoder = new TextEncoder();
    const dataBytes = encoder.encode(dataStr);
    
    // Fill blob properly - each field element is 32 bytes
    let srcIndex = 0;
    for (let i = 0; i < 4096 && srcIndex < dataBytes.length; i++) {
        const fieldStart = i * 32;
        // First byte must be 0 for BLS field constraint
        blob[fieldStart] = 0;
        
        // Copy up to 31 bytes of data
        const bytesToCopy = Math.min(31, dataBytes.length - srcIndex);
        for (let j = 0; j < bytesToCopy; j++) {
            blob[fieldStart + 1 + j] = dataBytes[srcIndex++];
        }
    }
    
    console.log('Blob size:', blob.length, 'bytes');
    console.log('Data encoded:', srcIndex, 'bytes');
    
    // Get transaction parameters
    const nonce = await wallet.getNonce();
    const baseFee = (await provider.getBlock('latest')).baseFeePerGas;
    
    // Create a Transaction object with type 3
    const tx = Transaction.from({
        type: 3,
        chainId: 11155111,
        nonce: nonce,
        to: '0x0000000000000000000000000000000000000000',
        value: 0,
        data: '0x',
        gasLimit: 21000,
        maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
        maxFeePerGas: ethers.parseUnits('50', 'gwei'),
        maxFeePerBlobGas: ethers.parseUnits('30', 'gwei')
    });
    
    // Set the KZG library on the transaction
    tx.kzg = cKzg;
    
    // Set the blobs - ethers will compute commitments and proofs internally
    tx.blobs = [blob];
    
    console.log('\nTransaction details:');
    console.log('Type:', tx.type);
    console.log('Nonce:', tx.nonce);
    console.log('Blob versioned hashes:', tx.blobVersionedHashes);
    
    try {
        console.log('\nSigning and sending Type 3 blob transaction...');
        
        // Sign the transaction
        const signedTx = await wallet.signTransaction(tx);
        console.log('Transaction signed');
        
        // Send the raw transaction
        const txHash = await provider.send('eth_sendRawTransaction', [signedTx]);
        console.log('\n✅ Type 3 Blob Transaction sent!');
        console.log('Transaction hash:', txHash);
        
        // Wait for confirmation
        const receipt = await provider.waitForTransaction(txHash);
        
        console.log('\n🎉 SUCCESS - BLOB TRANSACTION CONFIRMED!');
        console.log('Block:', receipt.blockNumber);
        console.log('Type:', receipt.type);
        console.log('Blob gas used:', receipt.blobGasUsed);
        console.log(`\nView on Etherscan: https://sepolia.etherscan.io/tx/${txHash}`);
        
        // Save success
        fs.writeFileSync('blob-success.json', JSON.stringify({
            success: true,
            type: 3,
            txHash: txHash,
            block: receipt.blockNumber,
            blobGasUsed: receipt.blobGasUsed?.toString()
        }, null, 2));
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        
        if (error.message.includes('underpriced')) {
            console.error('Transaction underpriced - increase gas fees');
        } else if (error.message.includes('invalid')) {
            console.error('Invalid transaction format');
        } else if (error.message.includes('insufficient')) {
            console.error('Insufficient funds for gas');
        }
    }
}

sendFinalBlobTx().catch(console.error);