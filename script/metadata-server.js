#!/usr/bin/env node
/**
 * Simple local metadata server for KaiSign Extension testing
 *
 * Usage:
 *   node script/metadata-server.js [port]
 *
 * Then set in browser:
 *   localStorage.setItem('kaisign_local_api', 'http://localhost:3456')
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.argv[2] || 3456;
const METADATA_DIR = path.join(__dirname, 'metadata');

// Map of address -> metadata file
const metadataFiles = {};

// Load all metadata files
function loadMetadata() {
  if (!fs.existsSync(METADATA_DIR)) {
    console.error(`Metadata directory not found: ${METADATA_DIR}`);
    process.exit(1);
  }

  const files = fs.readdirSync(METADATA_DIR).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = fs.readFileSync(path.join(METADATA_DIR, file), 'utf8');
      const metadata = JSON.parse(content);

      // Extract address from metadata
      const address = metadata.context?.contract?.address?.toLowerCase();
      const chainId = metadata.context?.contract?.chainId || 1;

      if (address) {
        const key = `${address}-${chainId}`;
        metadataFiles[key] = metadata;
        console.log(`Loaded: ${file} -> ${address} (chain ${chainId})`);
      }
    } catch (e) {
      console.error(`Error loading ${file}:`, e.message);
    }
  }

  console.log(`\nLoaded ${Object.keys(metadataFiles).length} metadata files\n`);
}

// HTTP server
const server = http.createServer((req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://localhost:${PORT}`);

  console.log(`${req.method} ${url.pathname}${url.search}`);

  // Health check
  if (url.pathname === '/health' || url.pathname === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', metadata_count: Object.keys(metadataFiles).length }));
    return;
  }

  // Get metadata by address - matches KaiSign API format
  // /api/py/contract/{address}?chain_id={chainId}
  const contractMatch = url.pathname.match(/\/api\/py\/contract\/([0-9a-fA-Fx]+)/);
  if (contractMatch) {
    const address = contractMatch[1].toLowerCase();
    const chainId = url.searchParams.get('chain_id') || '1';

    const key = `${address}-${chainId}`;
    const metadata = metadataFiles[key];

    if (metadata) {
      console.log(`  -> Found metadata for ${address}`);
      // Return in the format the extension expects: { success: true, metadata: {...} }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: true,
        metadata: metadata,
        source: 'local'
      }));
    } else {
      console.log(`  -> No metadata for ${address} (chain ${chainId})`);
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: 'Metadata not found', address, chainId }));
    }
    return;
  }

  // Also support simple /metadata endpoint
  if (url.pathname.startsWith('/metadata')) {
    let address, chainId;

    const pathMatch = url.pathname.match(/\/metadata\/([0-9a-fA-Fx]+)(?:\/(\d+))?/);
    if (pathMatch) {
      address = pathMatch[1].toLowerCase();
      chainId = pathMatch[2] || '1';
    } else {
      address = url.searchParams.get('address')?.toLowerCase();
      chainId = url.searchParams.get('chainId') || '1';
    }

    if (!address) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Missing address parameter' }));
      return;
    }

    const key = `${address}-${chainId}`;
    const metadata = metadataFiles[key];

    if (metadata) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(metadata));
    } else {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Metadata not found', address, chainId }));
    }
    return;
  }

  // List all metadata
  if (url.pathname === '/list') {
    const list = Object.entries(metadataFiles).map(([key, meta]) => ({
      key,
      address: meta.context?.contract?.address,
      chainId: meta.context?.contract?.chainId,
      name: meta.context?.contract?.name
    }));
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(list, null, 2));
    return;
  }

  // 404 for unknown routes
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

// Start server
loadMetadata();
server.listen(PORT, () => {
  console.log(`Metadata server running on http://localhost:${PORT}`);
  console.log(`\nEndpoints:`);
  console.log(`  GET /health              - Health check`);
  console.log(`  GET /list                - List all loaded metadata`);
  console.log(`  GET /metadata/0x.../1    - Get metadata by address and chainId`);
  console.log(`  GET /metadata?address=0x...&chainId=1`);
  console.log(`\nSet in browser console:`);
  console.log(`  localStorage.setItem('kaisign_local_api', 'http://localhost:${PORT}')`);
  console.log(`\nPress Ctrl+C to stop\n`);
});
