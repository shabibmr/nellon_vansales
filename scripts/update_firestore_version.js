#!/usr/bin/env node

/**
 * Script to publish / update the app version metadata in Firebase Firestore.
 *
 * Upload the APK to the VPS first, then run this so sha256 matches the hosted file.
 *
 * Usage:
 *   node scripts/update_firestore_version.js [options]
 *
 * Options:
 *   --apk=<path>           Local APK to hash (default: branded release outputs)
 *   --build=<number>       Set build number (default: auto-read from pubspec.yaml)
 *   --version=<string>     Set version name (default: auto-read from pubspec.yaml)
 *   --url=<string>         Set APK download URL (default: https://algoray.cloud/nellon/app-nellon-release.apk)
 *   --channel=<name>       production | beta | test (default: production)
 *   --force=<true|false>   Set force_update flag (default: false)
 *   --notes=<string>       Set release notes
 *   --dry-run              Display the payload without writing to Firestore
 *
 * Auth (first match wins):
 *   FIRESTORE_ACCESS_TOKEN / GOOGLE_OAUTH_ACCESS_TOKEN / CLOUDSDK_AUTH_ACCESS_TOKEN
 *   cached firebase-tools.json access token
 *   refresh of firebase-tools.json / FIREBASE_TOKEN via the current Firebase CLI OAuth client
 *   Google Application Default Credentials (authorized_user or service_account)
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const https = require('https');

// 1. Parse CLI arguments
const args = process.argv.slice(2);
function getArg(name, defaultValue = null) {
  const match = args.find(a => a.startsWith(`--${name}=`));
  if (match) return match.split('=').slice(1).join('=');
  return defaultValue;
}
const hasFlag = (name) => args.includes(`--${name}`);

// 2. Read pubspec.yaml to get default version & buildNumber
const rootDir = path.resolve(__dirname, '..');
const pubspecPath = path.join(rootDir, 'pubspec.yaml');
let defaultVersionName = '1.0.0';
let defaultBuildNumber = 1;

if (fs.existsSync(pubspecPath)) {
  const pubspecContent = fs.readFileSync(pubspecPath, 'utf8');
  const versionMatch = pubspecContent.match(/^version:\s*([^\s#]+)/m);
  if (versionMatch) {
    const rawVersion = versionMatch[1]; // e.g. "1.0.0+1"
    const parts = rawVersion.split('+');
    defaultVersionName = parts[0];
    if (parts[1]) {
      defaultBuildNumber = parseInt(parts[1], 10) || 1;
    }
  }
}

const defaultApkCandidates = [
  path.join(rootDir, 'build', 'app', 'outputs', 'flutter-apk', 'app-nellon-release.apk'),
  path.join(rootDir, 'build', 'app', 'outputs', 'apk', 'release', 'app-nellon-release.apk'),
];

const apkArg = getArg('apk');
const apkPath = apkArg || defaultApkCandidates.find((p) => fs.existsSync(p));

if (!apkPath || !fs.existsSync(apkPath)) {
  console.error(
    'APK file not found. Build a release APK first, then pass --apk=<path>.\n' +
      'The local file is hashed; do not write Firestore before the same file is on the VPS.',
  );
  process.exit(1);
}

const sha256 = crypto.createHash('sha256').update(fs.readFileSync(apkPath)).digest('hex');

const channel = (getArg('channel', 'production') || 'production').toLowerCase();
const isBeta = channel === 'beta' || channel === 'test';
const defaultUrl = isBeta
  ? 'https://algoray.cloud/nellon/test/app-nellon-release.apk'
  : 'https://algoray.cloud/nellon/app-nellon-release.apk';

const buildNumber = parseInt(getArg('build', defaultBuildNumber), 10);
const versionName = getArg('version', defaultVersionName);
const apkUrl = getArg('url', defaultUrl);
const forceUpdate = getArg('force', 'false').toLowerCase() === 'true';
const releaseNotes = getArg('notes', `• Update release v${versionName} (Build ${buildNumber})\n• Performance and stability improvements`);
const isDryRun = hasFlag('dry-run');

// firebase-tools documents these as an installed-app OAuth client, not a secret.
// See firebase-tools/src/api.ts (clientId / clientSecret). The previous ID
// (...ho85qd6) was retired and Google returns invalid_client for it.
const FALLBACK_FIREBASE_OAUTH_CLIENT = {
  client_id: '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
  client_secret: 'j9iVZfS8kkCEFUPaAeJV0sAi',
  label: 'firebase-tools-current',
};

function homeDir() {
  return process.env.USERPROFILE || process.env.HOME || '';
}

function readJsonIfExists(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
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

function findFirebaseToolsRoots() {
  const roots = [];
  const seen = new Set();
  const add = (candidate) => {
    if (!candidate || seen.has(candidate)) return;
    seen.add(candidate);
    if (fs.existsSync(path.join(candidate, 'lib', 'api.js'))) roots.push(candidate);
  };

  add(path.join(rootDir, 'node_modules', 'firebase-tools'));
  if (process.env.APPDATA) {
    add(path.join(process.env.APPDATA, 'npm', 'node_modules', 'firebase-tools'));
  }
  if (homeDir()) {
    add(path.join(homeDir(), 'AppData', 'Roaming', 'npm', 'node_modules', 'firebase-tools'));
    add(path.join(homeDir(), '.npm-global', 'lib', 'node_modules', 'firebase-tools'));
  }

  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    add(path.join(dir, 'node_modules', 'firebase-tools'));
  }
  return roots;
}

function oauthClientFromFirebaseToolsApi(src) {
  const idMatch = src.match(/FIREBASE_CLIENT_ID"\s*,\s*"([^"]+)"/);
  const secretMatch = src.match(/FIREBASE_CLIENT_SECRET"\s*,\s*"([^"]+)"/);
  if (!idMatch) return null;
  return {
    client_id: idMatch[1],
    client_secret: secretMatch ? secretMatch[1] : '',
    label: 'installed-firebase-tools',
  };
}

function firebaseOauthClients() {
  const clients = [];
  const seen = new Set();
  const add = (client) => {
    if (!client || !client.client_id || seen.has(client.client_id)) return;
    seen.add(client.client_id);
    clients.push(client);
  };

  if (process.env.FIREBASE_CLIENT_ID) {
    add({
      client_id: process.env.FIREBASE_CLIENT_ID,
      client_secret: process.env.FIREBASE_CLIENT_SECRET || '',
      label: 'env',
    });
  }

  for (const root of findFirebaseToolsRoots()) {
    const apiSrc = fs.readFileSync(path.join(root, 'lib', 'api.js'), 'utf8');
    add(oauthClientFromFirebaseToolsApi(apiSrc));
  }

  add(FALLBACK_FIREBASE_OAUTH_CLIENT);
  return clients;
}

async function refreshWithClient(refreshToken, client) {
  const params = {
    grant_type: 'refresh_token',
    client_id: client.client_id,
    refresh_token: refreshToken,
  };
  if (client.client_secret) params.client_secret = client.client_secret;

  const { json, raw } = await postForm('https://oauth2.googleapis.com/token', params);
  if (!json.access_token) {
    const description = json.error_description || json.error || raw;
    throw new Error(`${client.label || client.client_id}: ${description}`);
  }
  return json;
}

async function refreshFirebaseRefreshToken(refreshToken) {
  const errors = [];
  for (const client of firebaseOauthClients()) {
    try {
      const json = await refreshWithClient(refreshToken, client);
      return { json, client };
    } catch (err) {
      errors.push(err.message);
    }
  }
  throw new Error(`Failed to refresh Firebase token: ${errors.join(' | ')}`);
}

function adcCredentialPaths() {
  const paths = [];
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    paths.push(process.env.GOOGLE_APPLICATION_CREDENTIALS);
  }
  if (process.env.APPDATA) {
    paths.push(path.join(process.env.APPDATA, 'gcloud', 'application_default_credentials.json'));
  }
  const home = homeDir();
  if (home) {
    paths.push(path.join(home, 'AppData', 'Roaming', 'gcloud', 'application_default_credentials.json'));
    paths.push(path.join(home, '.config', 'gcloud', 'application_default_credentials.json'));
  }
  return paths;
}

function loadAdc() {
  for (const filePath of adcCredentialPaths()) {
    const parsed = readJsonIfExists(filePath);
    if (parsed) return { filePath, parsed };
  }
  return null;
}

function base64Url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString('base64url');
}

async function accessTokenFromServiceAccount(sa) {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${base64Url({ alg: 'RS256', typ: 'JWT' })}.${base64Url({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })}`;
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(unsigned);
  const assertion = `${unsigned}.${signer.sign(sa.private_key, 'base64url')}`;
  const { json, raw } = await postForm('https://oauth2.googleapis.com/token', {
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });
  if (!json.access_token) {
    throw new Error(`Service account token exchange failed: ${json.error_description || json.error || raw}`);
  }
  return json.access_token;
}

function persistFirebaseAccessToken(configPath, config, json) {
  if (!config.tokens) config.tokens = {};
  config.tokens.access_token = json.access_token;
  if (json.expires_in) {
    config.tokens.expires_at = Date.now() + (json.expires_in * 1000);
    config.tokens.expires_in = json.expires_in;
  }
  if (json.token_type) config.tokens.token_type = json.token_type;
  if (json.scope) config.tokens.scope = json.scope;
  if (json.id_token) config.tokens.id_token = json.id_token;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

function authHelpText() {
  return [
    'Could not obtain a Google access token for Firestore.',
    'In an interactive terminal run: firebase login --reauth',
    'Or: gcloud auth application-default login',
    'Or set FIRESTORE_ACCESS_TOKEN / GOOGLE_APPLICATION_CREDENTIALS.',
    'firebase login cannot run inside this non-interactive agent session; use login:ci for CI.',
  ].join('\n');
}

async function getAccessToken() {
  const envToken =
    process.env.FIRESTORE_ACCESS_TOKEN ||
    process.env.GOOGLE_OAUTH_ACCESS_TOKEN ||
    process.env.CLOUDSDK_AUTH_ACCESS_TOKEN;
  if (envToken) {
    console.log('Using access token from environment.');
    return envToken;
  }

  const configPath = path.join(homeDir(), '.config', 'configstore', 'firebase-tools.json');
  const config = readJsonIfExists(configPath);
  const tokens = config && config.tokens;

  if (tokens && tokens.access_token && tokens.expires_at && tokens.expires_at > Date.now() + 60000) {
    console.log('Using cached Firebase CLI access token.');
    return tokens.access_token;
  }

  const refreshCandidates = [];
  if (tokens && tokens.refresh_token) {
    refreshCandidates.push({ refreshToken: tokens.refresh_token, persistConfig: true });
  }
  if (process.env.FIREBASE_TOKEN) {
    refreshCandidates.push({ refreshToken: process.env.FIREBASE_TOKEN, persistConfig: false });
  }

  for (const candidate of refreshCandidates) {
    try {
      console.log('Refreshing Firebase OAuth access token...');
      const { json, client } = await refreshFirebaseRefreshToken(candidate.refreshToken);
      if (candidate.persistConfig && config) {
        persistFirebaseAccessToken(configPath, config, json);
      }
      console.log(`Refreshed access token (${client.label}).`);
      return json.access_token;
    } catch (err) {
      console.warn(err.message);
    }
  }

  const adc = loadAdc();
  if (adc) {
    const creds = adc.parsed;
    if (creds.type === 'authorized_user' && creds.refresh_token && creds.client_id) {
      console.log('Refreshing Google Application Default Credentials...');
      try {
        const json = await refreshWithClient(creds.refresh_token, {
          client_id: creds.client_id,
          client_secret: creds.client_secret || '',
          label: 'gcloud-adc',
        });
        console.log('Refreshed access token (gcloud-adc).');
        return json.access_token;
      } catch (err) {
        console.warn(err.message);
      }
    }
    if (creds.type === 'service_account' && creds.client_email && creds.private_key) {
      console.log('Minting access token from service account credentials...');
      return accessTokenFromServiceAccount(creds);
    }
  }

  if (process.env.FIREBASE_TOKEN) {
    console.log('Using FIREBASE_TOKEN as a bearer token.');
    return process.env.FIREBASE_TOKEN;
  }

  throw new Error(authHelpText());
}

// 4. Update Firestore server_config/app_version document
async function updateFirestore() {
  const projectId = 'nellon-vansales';
  const documentPath = isBeta ? 'server_config/app_version_beta' : 'server_config/app_version';

  console.log('====================================================');
  console.log(`  Nellon Van Sales - Firestore Version Updater (${channel.toUpperCase()})`);
  console.log('====================================================');
  console.log(`• Project ID   : ${projectId}`);
  console.log(`• Channel      : ${channel}`);
  console.log(`• Document     : ${documentPath}`);
  console.log(`• Version Name : ${versionName}`);
  console.log(`• Build Number : ${buildNumber}`);
  console.log(`• APK path     : ${apkPath}`);
  console.log(`• SHA-256      : ${sha256}`);
  console.log(`• APK URL      : ${apkUrl}`);
  console.log(`• Force Update : ${forceUpdate}`);
  console.log(`• Release Notes:\n  ${releaseNotes.split('\n').join('\n  ')}`);
  console.log('----------------------------------------------------');

  if (isDryRun) {
    console.log('[DRY RUN] No changes were written to Firestore.');
    return;
  }

  const accessToken = await getAccessToken();

  const firestorePayload = {
    fields: {
      latest_build_number: { integerValue: String(buildNumber) },
      latest_version_name: { stringValue: versionName },
      apk_url: { stringValue: apkUrl },
      sha256: { stringValue: sha256 },
      force_update: { booleanValue: forceUpdate },
      release_notes: { stringValue: releaseNotes },
    },
  };

  const endpoint = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${documentPath}`;

  const postData = JSON.stringify(firestorePayload);

  return new Promise((resolve, reject) => {
    const req = https.request(endpoint, {
      method: 'PATCH',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
      },
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          console.log('\n✔ Successfully updated Firestore document!');
          console.log('Installed apps pick this up via snapshot or next resume.\n');
          resolve(JSON.parse(data));
        } else {
          console.error(`\n❌ Error updating Firestore (${res.statusCode}):`);
          console.error(data);
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', (err) => {
      console.error('Request failed:', err);
      reject(err);
    });

    req.write(postData);
    req.end();
  });
}

if (require.main === module) {
  updateFirestore().catch((err) => {
    console.error('\nUpdate failed:', err.message);
    process.exit(1);
  });
}

module.exports = {
  getAccessToken,
};
