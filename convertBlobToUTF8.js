#!/usr/bin/env node

const fs = require('fs');

// Read the raw blob data
const rawData = fs.readFileSync('testblob.json', 'utf8').trim();

// Remove 0x prefix if present
const hexData = rawData.startsWith('0x') ? rawData.slice(2) : rawData;

// Remove null bytes (00) from the hex string
const cleanedHex = hexData.replace(/00/g, '');

// Convert hex to UTF-8
const utf8Data = Buffer.from(cleanedHex, 'hex').toString('utf8');

// Write to output file
fs.writeFileSync('testblob_utf8.json', utf8Data);

// Also try to parse as JSON and pretty print
try {
    const jsonData = JSON.parse(utf8Data);
    fs.writeFileSync('testblob_formatted.json', JSON.stringify(jsonData, null, 2));
    console.log('✅ Successfully converted blob data to UTF-8');
    console.log('📄 Files created:');
    console.log('  - testblob_utf8.json (raw UTF-8)');
    console.log('  - testblob_formatted.json (formatted JSON)');
    console.log('\n📊 Parsed data preview:');
    console.log(JSON.stringify(jsonData, null, 2).substring(0, 500) + '...');
} catch (e) {
    console.log('✅ Converted to UTF-8 (saved as testblob_utf8.json)');
    console.log('⚠️  Note: Data is not valid JSON, showing as plain text');
    console.log('\n📊 UTF-8 data preview:');
    console.log(utf8Data.substring(0, 500) + '...');
}