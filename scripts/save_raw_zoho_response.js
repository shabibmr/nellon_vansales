const https = require('https');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'nellon-vansales';
const API_KEY = 'AIzaSyBdQ-hxJvqgt9-fXiSF0M0X7hGBFazE7as';

function httpsRequest(url, options = {}, body = null) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, headers: res.headers, raw: data });
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
  const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/server_config/zoho?key=${API_KEY}`;
  const firestoreRes = await httpsRequest(firestoreUrl);
  const jsonDoc = JSON.parse(firestoreRes.raw);
  const config = decodeFields(jsonDoc.fields || {});
  const { client_id, client_secret, refresh_token, organization_id } = config;

  const tokenUrl = `https://accounts.zoho.com/oauth/v2/token?grant_type=refresh_token&client_id=${client_id}&client_secret=${client_secret}&refresh_token=${refresh_token}`;
  const tokenRes = await httpsRequest(tokenUrl, { method: 'POST' });
  const tokenData = JSON.parse(tokenRes.raw);
  const accessToken = tokenData.access_token;

  const headers = {
    'Authorization': `Zoho-oauthtoken ${accessToken}`,
    'Content-Type': 'application/json'
  };

  const targetUrl = `https://www.zohoapis.com/books/v3/cm_salesperson_profile?organization_id=${organization_id}`;
  console.log(`Fetching from: ${targetUrl}`);
  
  const response = await httpsRequest(targetUrl, { method: 'GET', headers });
  
  const outputFiles = [
    path.join(__dirname, '..', 'zoho_cm_salesperson_profile_raw_response.txt'),
    path.join(__dirname, '..', 'zoho_cm_salesperson_profile_raw_response.json'),
    path.join(__dirname, '..', 'assets', 'data', 'zoho', 'cm_salesperson_profile_raw.json')
  ];

  for (const filePath of outputFiles) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, response.raw, 'utf8');
    console.log(`Saved raw response to: ${filePath}`);
  }

  console.log('\n--- RAW RESPONSE CONTENT ---');
  console.log(response.raw);
}

main().catch(console.error);
