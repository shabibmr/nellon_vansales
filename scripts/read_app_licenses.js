#!/usr/bin/env node
// Lists app_licenses documents ordered by last_login_at, showing app_version.
// Usage: node scripts/read_app_licenses.js [YYYY-MM-DD]   (default: today, UTC)

const path = require('path');
const fs = require('fs');
const https = require('https');

const PROJECT_ID = 'nellon-vansales';

function homeDir() { return process.env.USERPROFILE || process.env.HOME || ''; }
function readJsonIfExists(p) {
  if (!p || !fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}
function httpsRequest(urlString, { method = 'GET', headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(urlString, { method, headers }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
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
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(postData) },
    body: postData,
  });
  let json;
  try { json = JSON.parse(body); } catch { throw new Error(`Token endpoint non-JSON (${statusCode}): ${body}`); }
  return { statusCode, json };
}
const FB_CLIENT = {
  client_id: '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
  client_secret: 'j9iVZfS8kkCEFUPaAeJV0sAi',
};
async function getAccessToken() {
  const cfg = readJsonIfExists(path.join(homeDir(), '.config', 'configstore', 'firebase-tools.json'));
  const tokens = cfg && cfg.tokens;
  if (tokens && tokens.refresh_token) {
    const { json } = await postForm('https://oauth2.googleapis.com/token', {
      grant_type: 'refresh_token',
      client_id: FB_CLIENT.client_id,
      client_secret: FB_CLIENT.client_secret,
      refresh_token: tokens.refresh_token,
    });
    if (json.access_token) return json.access_token;
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
  const r = {};
  for (const [k, v] of Object.entries(fields)) r[k] = decodeValue(v);
  return r;
}

async function main() {
  const dayArg = process.argv[2] || new Date().toISOString().slice(0, 10);
  const start = `${dayArg}T00:00:00Z`;
  const end = `${dayArg}T23:59:59.999Z`;
  const token = await getAccessToken();

  const query = {
    structuredQuery: {
      from: [{ collectionId: 'app_licenses' }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            { fieldFilter: { field: { fieldPath: 'last_login_at' }, op: 'GREATER_THAN_OR_EQUAL', value: { timestampValue: start } } },
            { fieldFilter: { field: { fieldPath: 'last_login_at' }, op: 'LESS_THAN_OR_EQUAL', value: { timestampValue: end } } },
          ],
        },
      },
      orderBy: [{ field: { fieldPath: 'last_login_at' }, direction: 'DESCENDING' }],
    },
  };

  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`;
  const { statusCode, body } = await httpsRequest(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(query),
  });
  if (statusCode !== 200) { console.error(`HTTP ${statusCode}: ${body}`); process.exit(1); }
  const rows = JSON.parse(body).filter((r) => r.document);

  console.log(`app_licenses with last_login_at on ${dayArg} (UTC): ${rows.length} device(s)\n`);
  const byVersion = {};
  for (const r of rows) {
    const f = decodeFields(r.document.fields || {});
    byVersion[f.app_version] = (byVersion[f.app_version] || 0) + 1;
    console.log(`- ${f.user_email || f.user_name || '(no user)'}  |  app_version=${f.app_version || '(none)'}  |  ${f.device_model} (Android ${f.device_os_version})  |  last_login_at=${f.last_login_at}  |  enabled=${f.enabled}`);
  }
  console.log('\nApp version breakdown:');
  for (const [v, c] of Object.entries(byVersion).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${v || '(none)'}: ${c}`);
  }
}
main().catch((e) => { console.error(e); process.exit(1); });
