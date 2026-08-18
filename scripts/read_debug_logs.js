#!/usr/bin/env node

/**
 * CLI utility to query and inspect `debug_logs` documents in Firestore.
 *
 * Usage:
 *   node scripts/read_debug_logs.js
 */

const https = require('https');

const PROJECT_ID = 'nellon-vansales';
const API_KEY = 'AIzaSyBdQ-hxJvqgt9-fXiSF0M0X7hGBFazE7as';

const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/debug_logs?pageSize=10&key=${API_KEY}`;

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

function printDocument(doc) {
  const docId = doc.name.split('/').pop();
  const decoded = decodeFields(doc.fields || {});
  
  console.log(`\n======================================================`);
  console.log(`📄 Document: debug_logs/${docId}`);
  console.log(`🕒 Created At:  ${decoded.created_at || doc.createTime || 'N/A'}`);
  console.log(`🕒 Flushed At:  ${decoded.flushed_at || 'N/A'}`);
  console.log(`📱 App Version: ${decoded.app_version || 'N/A'}`);
  console.log(`📁 Source File: ${decoded.source_file || 'N/A'}`);
  console.log(`📊 Line Count:  ${decoded.line_count || (decoded.lines ? decoded.lines.length : 0)}`);
  console.log(`------------------------------------------------------`);
  
  if (Array.isArray(decoded.lines)) {
    console.log(`Lines preview (${decoded.lines.length} total):`);
    const preview = decoded.lines.slice(0, 15);
    preview.forEach((l, idx) => {
      if (typeof l === 'object' && l !== null) {
        console.log(`  [${idx + 1}] ${l.timestamp || ''} ${l.message || JSON.stringify(l)}`);
      } else {
        console.log(`  [${idx + 1}] ${l}`);
      }
    });
    if (decoded.lines.length > 15) {
      console.log(`  ... and ${decoded.lines.length - 15} more lines`);
    }
  }
  console.log(`======================================================`);
}

function fetchDebugLogs() {
  console.log(`🔍 Querying Firestore collection 'debug_logs' for project '${PROJECT_ID}'...`);
  
  https.get(url, (res) => {
    let raw = '';
    res.on('data', (chunk) => raw += chunk);
    res.on('end', () => {
      try {
        const json = JSON.parse(raw);
        if (json.error) {
          console.error(`❌ Firestore API Error:`, json.error.message || json.error);
          return;
        }
        
        const docs = json.documents || [];
        if (docs.length === 0) {
          console.log(`ℹ️ Collection 'debug_logs' is empty (0 documents found).`);
          return;
        }
        
        console.log(`✅ Found ${docs.length} document(s) in 'debug_logs':`);
        // Sort documents by createTime desc
        docs.sort((a, b) => new Date(b.createTime) - new Date(a.createTime));
        docs.forEach(printDocument);
      } catch (err) {
        console.error(`❌ Failed to parse response:`, err.message);
        console.error(`Raw response:`, raw);
      }
    });
  }).on('error', (err) => {
    console.error(`❌ HTTPS request failed:`, err.message);
  });
}

fetchDebugLogs();
