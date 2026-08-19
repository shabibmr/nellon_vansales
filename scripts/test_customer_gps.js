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

function requestJson(url, options = {}, data = null) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(body) });
        } catch (e) {
          resolve({ status: res.statusCode, raw: body });
        }
      });
    });
    req.on('error', reject);
    if (data) {
      req.write(data);
    }
    req.end();
  });
}

function postForm(url, params) {
  const postData = new URLSearchParams(params).toString();
  return requestJson(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Content-Length': Buffer.byteLength(postData),
    },
  }, postData);
}

async function fetchZohoCredentials() {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/server_config/zoho?key=${API_KEY}`;
  const { status, body } = await requestJson(url);
  if (status !== 200) {
    throw new Error(`Failed to read server_config/zoho: HTTP ${status}`);
  }
  const cfg = decodeFields(body.fields || {});
  const clientId = cfg.client_id;
  const clientSecret = cfg.client_secret;
  const refreshToken = (cfg.refresh_token && cfg.refresh_token.trim()) || cfg.code;
  const orgId = cfg.organization_id;
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
  const creds = await fetchZohoCredentials();
  console.log(`Credentials fetched for Organization ID: ${creds.orgId}`);

  const accessToken = await getAccessToken(creds);
  console.log('Access token acquired.\n');

  // Exact Test Customer ID
  const contactId = '3331482000182087001';

  // 1. Fetch current contact details
  console.log('Step 1: Fetching details for "Test Customer" (ID: ' + contactId + ')...');
  const detailUrl = `${API_BASE}/contacts/${contactId}?organization_id=${creds.orgId}`;
  const detailRes = await requestJson(detailUrl, {
    method: 'GET',
    headers: { Authorization: `Zoho-oauthtoken ${accessToken}` },
  });

  const contact = detailRes.body?.contact || {};
  const billingAddressBefore = contact.billing_address || {};
  console.log(`Customer Name: "${contact.contact_name}"`);
  console.log('Current billing_address GPS:');
  console.log({
    latitude: billingAddressBefore.latitude,
    longitude: billingAddressBefore.longitude,
    address: billingAddressBefore.address,
    city: billingAddressBefore.city,
  });

  // 2. Generate new test coordinates (Dubai coordinates with randomized decimal)
  const testLat = 25.1972 + Number((Math.random() * 0.05).toFixed(6));
  const testLng = 55.2744 + Number((Math.random() * 0.05).toFixed(6));
  console.log(`\nStep 2: Sending PUT request to update GPS to: lat=${testLat}, lng=${testLng}...`);

  const updatePayload = JSON.stringify({
    billing_address: {
      latitude: testLat,
      longitude: testLng,
    },
  });

  const updateRes = await requestJson(`${API_BASE}/contacts/${contactId}?organization_id=${creds.orgId}`, {
    method: 'PUT',
    headers: {
      Authorization: `Zoho-oauthtoken ${accessToken}`,
      'Content-Type': 'application/json',
      'JSONString': 'true',
    },
  }, updatePayload);

  console.log(`Update Response: HTTP ${updateRes.status}`);
  console.log('Response Code/Message:', updateRes.body?.code, updateRes.body?.message);

  // 3. Re-fetch and verify
  console.log('\nStep 3: Re-fetching contact from Zoho to verify persisted GPS...');
  const verifyRes = await requestJson(detailUrl, {
    method: 'GET',
    headers: { Authorization: `Zoho-oauthtoken ${accessToken}` },
  });

  const billingAddressAfter = verifyRes.body?.contact?.billing_address || {};
  console.log('Verified billing_address in Zoho Books:');
  console.log({
    latitude: billingAddressAfter.latitude,
    longitude: billingAddressAfter.longitude,
    address: billingAddressAfter.address,
    city: billingAddressAfter.city,
  });

  const latMatch = Math.abs(Number(billingAddressAfter.latitude) - testLat) < 0.0001;
  const lngMatch = Math.abs(Number(billingAddressAfter.longitude) - testLng) < 0.0001;

  if (latMatch && lngMatch) {
    console.log('\n✅ VERIFICATION SUCCESS: GPS coordinates updated and verified successfully in Zoho Books for "Test Customer"!');
  } else {
    console.log('\n⚠️ Check coordinates:', billingAddressAfter.latitude, billingAddressAfter.longitude);
  }
}

main().catch((err) => {
  console.error('Execution error:', err);
});
