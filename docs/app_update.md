# In-app APK updates (no Play Store)

Installed vans poll `server_config/app_version` in Firestore. When
`latest_build_number` is higher than the local `versionCode` (`pubspec.yaml` `+N`)
and both `apk_url` and `sha256` are set, the app downloads the APK from the VPS
and opens the system installer.

The user must tap **Install**. Silent replace is not possible on a normal Android phone.

## Firestore document

Collection / doc: `server_config` / `app_version`

| Field | Type | Notes |
|---|---|---|
| `latest_build_number` | int | Must be greater than the installed `+N` |
| `latest_version_name` | string | e.g. `1.1.0` |
| `apk_url` | string | HTTPS URL of the APK already on the VPS |
| `sha256` | string | Hex digest of **that** file. Required. |
| `force_update` | bool | `true` = full-screen gate; `false` = dismissible dialog |
| `release_notes` | string | Shown in the update UI |

### Security rules (merge into the existing console ruleset)

Do **not** deploy this as the only rules file — it would deny every other collection.

```
match /server_config/app_version {
  allow read: if true;
  allow write: if false;
}
```

Public read is required because `AppUpdateGate` runs on the login screen, before Firebase Auth. Writes go through `scripts/update_firestore_version.js` (admin token). Clients never write this document.

Leave `app_licenses` and `server_config/zoho` rules unchanged.

## Release signing

Release builds fail unless `android/key.properties` exists (gitignored).

One-time, offline:

```text
keytool -genkey -v -keystore android/nellon-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias nellon
```

Copy `android/key.properties.example` to `android/key.properties` and fill in passwords. Back up the `.jks` and passwords off-repo. This key is forever.

Phones already running a **debug-signed** APK cannot upgrade onto this keystore. Those devices need a one-time uninstall / sideload of the first properly signed build.

## Release steps

1. Bump `pubspec.yaml`: `1.0.0+1` → `1.1.0+2`. The number after `+` must increase.
2. `flutter build apk --release` (fails if `key.properties` is missing).
3. Upload `app-nellon-release.apk` to the VPS **first** (`https://algoray.cloud/nellon/app-nellon-release.apk`).
4. Publish metadata (hashes the local APK in the same write):

```bash
node scripts/update_firestore_version.js --apk=build/app/outputs/flutter-apk/app-nellon-release.apk --notes="Stock transfer fix" --force=true
```

Use `--dry-run` to print SHA-256 without writing.

5. Confirm Firestore `sha256` matches `sha256sum` / `Get-FileHash` of the uploaded file.
6. Open vans pick it up on the live snapshot or the next resume. They still tap Install.

Never write Firestore before the APK is actually at `apk_url`.
