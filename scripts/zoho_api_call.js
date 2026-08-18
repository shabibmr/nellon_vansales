#!/usr/bin/env node

/**
 * Fetches Zoho OAuth credentials from Firestore server_config/zoho (public
 * read, no auth needed — see firestore.rules), exchanges the refresh token
 * for an access token, then makes a GET call against the Zoho Books API.
 *
 * Usage:
 *   node scripts/zoho_api_call.js <path> [param=value ...]
 *
 * Examples:
 *   node scripts/zoho_api_call.js /cm_salesperson_profile
 *   node scripts/zoho_api_call.js /settings/modules
 *   node scripts/zoho_api_call.js /contacts contact_type=customer per_page=5
 *   node scripts/zoho_api_call.js /invoices/1234567890
 */

const https = require('https');

const PROJECT_ID = 'nellon-vansales';
const API_KEY = 'AIzaSyBdQ-hxJvqgt9-fXiSF0M0X7hGBFazE7as';
const API_BASE = 'https://www.zohoapis.com/books/v3';
const TOKEN_URL = 'https://accounts.zoho.com/oauth/v2/token';

function decodeValue(val) {
  if (!val) return null;
  if ('stringValue' in val) return val.stringValue;
  if ('integerValue' in val) return parseInt(val.integerValue, 10);
  if ('doubleValue' in val) return parseFloat(val.doubleValue);
  if ('booleanValue' in val) return val.booleanValue;
  if ('mapValue' in val) return decodeFields(val.mapValue.fields || {});
  if ('arrayValue' in val) return (val.arrayValue.values || []).map(decodeValue);
  return val;
}

function decodeFields(fields) {
  const result = {};
  for (const [key, value] of Object.entries(fields)) result[key] = decodeValue(value);
  return result;
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, body: JSON.parse(data) });
          } catch (e) {
            reject(e);
          }
        });
      })
      .on('error', reject);
  });
}

function getJsonWithHeaders(url, headers) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers }, (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, body: JSON.parse(data) });
          } catch (e) {
            reject(e);
          }
        });
      })
      .on('error', reject);
  });
}

function postForm(url, params) {
  return new Promise((resolve, reject) => {
    const postData = new URLSearchParams(params).toString();
    const req = https.request(
      url,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(postData),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, body: JSON.parse(data) });
          } catch (e) {
            reject(e);
          }
        });
      },
    );
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

async function fetchZohoCredentials() {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/server_config/zoho?key=${API_KEY}`;
  const { status, body } = await getJson(url);
  if (status !== 200) {
    throw new Error(`Failed to read server_config/zoho: HTTP ${status} ${JSON.stringify(body)}`);
  }
  const cfg = decodeFields(body.fields || {});
  const clientId = cfg.client_id;
  const clientSecret = cfg.client_secret;
  const refreshToken = (cfg.refresh_token && cfg.refresh_token.trim()) || cfg.code;
  const orgId = cfg.organization_id;

  if (!clientId || !clientSecret || !refreshToken || !orgId) {
    throw new Error(
      `Incomplete Zoho config in Firestore: ${JSON.stringify({
        hasClientId: !!clientId,
        hasClientSecret: !!clientSecret,
        hasRefreshToken: !!refreshToken,
        hasOrgId: !!orgId,
      })}`,
    );
  }
  return { clientId, clientSecret, refreshToken, orgId };
}

async function getAccessToken({ clientId, clientSecret, refreshToken }) {
  const { body } = await postForm(TOKEN_URL, {
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: clientId,
    client_secret: clientSecret,
  });
  if (!body.access_token) {
    throw new Error(`Token exchange failed: ${JSON.stringify(body)}`);
  }
  return body.access_token;
}

async function main() {
  const [apiPath, ...paramArgs] = process.argv.slice(2);
  if (!apiPath) {
    console.error('Usage: node scripts/zoho_api_call.js <path> [param=value ...]');
    console.error('Example: node scripts/zoho_api_call.js /cm_salesperson_profile');
    process.exit(1);
  }

  const creds = await fetchZohoCredentials();
  console.log(`Fetched credentials from Firestore (org ${creds.orgId}).`);

  const accessToken = await getAccessToken(creds);
  console.log('Obtained Zoho access token.');

  const params = new URLSearchParams({ organization_id: creds.orgId });
  for (const arg of paramArgs) {
    const eq = arg.indexOf('=');
    if (eq === -1) continue;
    params.set(arg.slice(0, eq), arg.slice(eq + 1));
  }

  const url = `${API_BASE}${apiPath}?${params.toString()}`;
  console.log(`GET ${url}\n`);

  const { status, body } = await getJsonWithHeaders(url, {
    Authorization: `Zoho-oauthtoken ${accessToken}`,
  });

  console.log('HTTP', status);
  console.log(JSON.stringify(body, null, 2));
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
