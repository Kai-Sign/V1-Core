const fs = require('fs');
const { keccak256 } = require('ethers');

// Read the metadata file
const metadataPath = process.argv[2] || '/Users/muhammadaushijri/Desktop/git/v1-core/kaisign-erc7730-1.json';
const metadata = fs.readFileSync(metadataPath, 'utf8');

// Calculate keccak256 hash
const metadataHash = keccak256(Buffer.from(metadata));

console.log('Metadata file:', metadataPath);
console.log('Metadata Hash (keccak256):', metadataHash);
console.log('\nMetadata length:', metadata.length, 'bytes');