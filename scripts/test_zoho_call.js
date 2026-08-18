const https = require('https');

const PROJECT_ID = 'nellon-vansales';
const API_KEY = 'AIzaSyBdQ-hxJvqgt9-fXiSF0M0X7hGBFazE7as';

function httpsRequest(url, options = {}, body = null) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ statusCode: res.statusCode, headers: res.headers, body: json });
        } catch (e) {
          resolve({ statusCode: res.statusCode, headers: res.headers, raw: data });
        }
      });
    });
    req.on('error', reject);
    if (body) {
      req.write(body);
    }
    req.end();
  });
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
  console.log('=== Step 1: Getting credentials from Firestore ===');
  const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/server_config/zoho?key=${API_KEY}`;
  const firestoreRes = await httpsRequest(firestoreUrl);
  const config = decodeFields(firestoreRes.body.fields || {});
  const { client_id, client_secret, refresh_token, organization_id } = config;

  console.log('=== Step 2: Refreshing Zoho OAuth Token ===');
  const tokenUrl = `https://accounts.zoho.com/oauth/v2/token?grant_type=refresh_token&client_id=${client_id}&client_secret=${client_secret}&refresh_token=${refresh_token}`;
  const tokenRes = await httpsRequest(tokenUrl, { method: 'POST' });
  const accessToken = tokenRes.body.access_token;
  console.log('Access token obtained successfully.');

  const headers = {
    'Authorization': `Zoho-oauthtoken ${accessToken}`,
    'Content-Type': 'application/json'
  };

  const endpoints = {
    'Organization': `/organizations/${organization_id}`,
    'Salesperson Profiles (cm_salesperson_profile)': `/cm_salesperson_profile?organization_id=${organization_id}`,
    'Salespersons': `/salespersons?organization_id=${organization_id}`,
    'Locations (Warehouses)': `/locations?organization_id=${organization_id}`,
    'Bank Accounts': `/bankaccounts?organization_id=${organization_id}`,
  };

  for (const [label, path] of Object.entries(endpoints)) {
    console.log(`\n--- ${label} (${path}) ---`);
    const res = await httpsRequest(`https://www.zohoapis.com/books/v3${path}`, { method: 'GET', headers });
    console.log(`Status: ${res.statusCode}`);
    if (res.body) {
      if (res.body.module_records) {
        console.log(`module_records count: ${res.body.module_records.length}`);
        console.log(JSON.stringify(res.body.module_records, null, 2));
      } else if (res.body.data) {
        console.log(`data count: ${res.body.data.length}`);
        console.log(JSON.stringify(res.body.data.slice(0, 3), null, 2));
      } else if (res.body.locations) {
        console.log(`locations count: ${res.body.locations.length}`);
        console.log(JSON.stringify(res.body.locations.slice(0, 3), null, 2));
      } else if (res.body.bankaccounts) {
        console.log(`bankaccounts count: ${res.body.bankaccounts.length}`);
        console.log(JSON.stringify(res.body.bankaccounts.slice(0, 3), null, 2));
      } else {
        console.log(JSON.stringify(res.body, null, 2));
      }
    } else {
      console.log(res.raw);
    }
  }
}

main().catch(console.error);
