#!/usr/bin/env node

const path = require('path');
const fs = require('fs');
const https = require('https');

const PROJECT_ID = 'nellon-vansales';

function homeDir() {
  return process.env.USERPROFILE || process.env.HOME || '';
}

function readJsonIfExists(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  try { return JSON.parse(fs.readFileSync(filePath, 'utf8')); } catch { return null; }
}

function httpsRequest(urlString, { method = 'GET', headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(urlString, { method, headers }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ statusCode: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function postForm(urlString, params) {
  const postData = new URLSearchParams(params).toString();
  const { statusCode, body } = await httpsRequest(urlString, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Content-Length': Buffer.byteLength(postData),
    },
    body: postData,
  });
  let json;
  try {
    json = JSON.parse(body);
  } catch {
    throw new Error(`Token endpoint returned non-JSON (${statusCode}): ${body}`);
  }
  return { statusCode, json, raw: body };
}

const FALLBACK_FIREBASE_OAUTH_CLIENT = {
  client_id: '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
  client_secret: 'j9iVZfS8kkCEFUPaAeJV0sAi',
  label: 'firebase-tools-current',
};

async function getAccessToken() {
  const configPath = path.join(homeDir(), '.config', 'configstore', 'firebase-tools.json');
  const config = readJsonIfExists(configPath);
  const tokens = config && config.tokens;

  if (tokens && tokens.refresh_token) {
    const params = {
      grant_type: 'refresh_token',
      client_id: FALLBACK_FIREBASE_OAUTH_CLIENT.client_id,
      client_secret: FALLBACK_FIREBASE_OAUTH_CLIENT.client_secret,
      refresh_token: tokens.refresh_token,
    };
    const { json } = await postForm('https://oauth2.googleapis.com/token', params);
    if (json.access_token) {
      return json.access_token;
    }
  }
  throw new Error('Could not refresh access token');
}

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

async function main() {
  const token = await getAccessToken();

  // Check debug_logs collection
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/debug_logs?pageSize=100`;
  const { statusCode, body } = await httpsRequest(url, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });

  const json = JSON.parse(body);
  if (!json.documents || json.documents.length === 0) {
    console.log('No documents found in debug_logs.');
    return;
  }

  console.log(`Found ${json.documents.length} document(s) in 'debug_logs'.\n`);
  
  // Sort documents by createTime ascending
  const docs = json.documents.sort((a, b) => (a.createTime > b.createTime ? 1 : -1));

  for (const doc of docs) {
    const docId = doc.name.split('/').pop();
    const fields = decodeFields(doc.fields || {});
    console.log('================================================================================');
    console.log(`📜 Document ID: ${docId}`);
    console.log(`🕒 Created At:   ${doc.createTime}`);
    console.log(`📱 App Version:  ${fields.app_version}`);
    console.log(`📁 Source File:  ${fields.source_file}`);
    console.log(`⏰ Flushed At:   ${fields.flushed_at}`);
    console.log(`🔢 Line Count:   ${fields.line_count}`);
    console.log('--------------------------------------------------------------------------------');
    if (fields.lines && Array.isArray(fields.lines)) {
      fields.lines.forEach((line, idx) => {
        console.log(`  [${idx + 1}] ${line}`);
      });
    } else {
      console.log('  (no lines)');
    }
    console.log('================================================================================\n');
  }
}

main().catch(console.error);
