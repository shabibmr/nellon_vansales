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
 *   --force=<true|false>   Set force_update flag (default: false)
 *   --notes=<string>       Set release notes
 *   --dry-run              Display the payload without writing to Firestore
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

// 3. Resolve Firebase credentials from ~/.config/configstore/firebase-tools.json
async function getAccessToken() {
  const configPath = path.join(process.env.USERPROFILE || process.env.HOME, '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(configPath)) {
    throw new Error('Firebase CLI configuration not found. Please run "firebase login" first.');
  }

  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const tokens = config.tokens;
  if (!tokens) {
    throw new Error('No Firebase tokens found in configstore. Please run "firebase login" first.');
  }

  const isExpired = tokens.expires_at && tokens.expires_at < Date.now() + 60000;
  if (isExpired && tokens.refresh_token) {
    console.log('Refreshing Firebase OAuth access token...');
    return await refreshAccessToken(tokens.refresh_token, configPath, config);
  }

  return tokens.access_token;
}

function refreshAccessToken(refreshToken, configPath, config) {
  return new Promise((resolve, reject) => {
    const postData = new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: '563584335869-fgrhgmd47bqnekij5i8b5pr03ho85qd6.apps.googleusercontent.com',
      refresh_token: refreshToken,
    }).toString();

    const req = https.request('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(postData),
      },
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.access_token) {
            config.tokens.access_token = json.access_token;
            config.tokens.expires_at = Date.now() + (json.expires_in * 1000);
            fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
            resolve(json.access_token);
          } else {
            reject(new Error(`Failed to refresh token: ${data}`));
          }
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
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

updateFirestore().catch((err) => {
  console.error('\nUpdate failed:', err.message);
  process.exit(1);
});
