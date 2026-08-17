#!/usr/bin/env node

/**
 * CLI utility to query and inspect `server_config` documents in Firestore.
 *
 * Usage:
 *   node scripts/read_server_config.js [doc_name]
 *
 * Examples:
 *   node scripts/read_server_config.js         # Prints all docs in server_config
 *   node scripts/read_server_config.js zoho    # Prints server_config/zoho
 */

const https = require('https');

const PROJECT_ID = 'nellon-vansales';
const API_KEY = 'AIzaSyBdQ-hxJvqgt9-fXiSF0M0X7hGBFazE7as';

const targetDoc = process.argv[2];

const url = targetDoc
  ? `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/server_config/${targetDoc}?key=${API_KEY}`
  : `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/server_config?key=${API_KEY}`;

function decodeValue(val) {
  if (!val) return null;
  if ('stringValue' in val) return val.stringValue;
  if ('integerValue' in val) return parseInt(val.integerValue, 10);
  if ('doubleValue' in val) return parseFloat(val.doubleValue);
  if ('booleanValue' in val) return val.booleanValue;
  if ('timestampValue' in val) return val.timestampValue;
  if ('nullValue' in val) return null;
  if ('mapValue' in val) return decodeFields(val.mapValue.fields || {});
  if ('arrayValue' in val) return (val.arrayValue.values || []).map(decodeValue);
  return val;
}

function decodeFields(fields) {
  const result = {};
  for (const [key, value] of Object.entries(fields)) {
    result[key] = decodeValue(value);
  }
  return result;
}

function maskSecret(val) {
  if (typeof val !== 'string' || val.length <= 8) return '***';
  return val.slice(0, 6) + '...' + val.slice(-4);
}

function printDocument(doc) {
  const docId = doc.name.split('/').pop();
  const decoded = decodeFields(doc.fields || {});
  
  console.log(`\n======================================================`);
  console.log(`📄 Document: server_config/${docId}`);
  console.log(`🕒 Updated:  ${doc.updateTime || 'N/A'}`);
  console.log(`------------------------------------------------------`);
  
  // Format with friendly presentation
  const formatted = { ...decoded };
  if (formatted.client_secret) formatted.client_secret = maskSecret(formatted.client_secret);
  if (formatted.code) formatted.code = maskSecret(formatted.code);

  console.log(JSON.stringify(formatted, null, 2));

  // Sanity validation report
  if (docId === 'zoho') {
    const isComplete = decoded.client_id && decoded.client_secret && decoded.code && decoded.organization_id;
    console.log(`\n[Validation] Status: ${isComplete ? '✅ COMPLETE' : '⚠️ INCOMPLETE'}`);
    console.log(`             Organization: ${decoded.organization_id || '(missing)'}`);
    console.log(`             Mock Mode:    ${decoded.mock_transactions === true ? 'MOCK' : 'LIVE'}`);
  }
}

https.get(url, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    if (res.statusCode !== 200) {
      console.error(`HTTP ${res.statusCode}: ${data}`);
      process.exit(1);
    }

    try {
      const json = JSON.parse(data);
      if (json.documents) {
        console.log(`Found ${json.documents.length} document(s) in collection 'server_config':`);
        json.documents.forEach(printDocument);
      } else if (json.name && json.fields) {
        printDocument(json);
      } else {
        console.log('No documents found.', json);
      }
      console.log(`\n======================================================\n`);
    } catch (e) {
      console.error('Failed to parse Firestore JSON response:', e);
    }
  });
}).on('error', (err) => {
  console.error('Network error reaching Firestore:', err.message);
  process.exit(1);
});
