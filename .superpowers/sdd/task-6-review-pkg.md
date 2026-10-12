# Review package Task 6
BASE 5113c9dec6a88318bf7485fb4422c886af11f55b
HEAD ccdf50faec9c9f2da2b102832e39b0a028d1b172
## Commits
ccdf50f Document server_config/print supervisor phone for operators.

## Stat
 docs/print_settings.md | 47 +++++++++++++++++++++++++++++++++++++++++++++++
 firestore.rules        |  3 ++-
 2 files changed, 49 insertions(+), 1 deletion(-)

## Diff
diff --git a/docs/print_settings.md b/docs/print_settings.md
new file mode 100644
index 0000000..a90b0a8
--- /dev/null
+++ b/docs/print_settings.md
@@ -0,0 +1,47 @@
+# Supervisor phone on printed vouchers (operators)
+
+Van apps read the supervisor phone number from Firestore and print it on
+invoice PDFs, thermal receipts, and related voucher footers. Operators change
+the number in the Firebase Console; van users cannot edit it from the app.
+
+## Firestore document
+
+Collection / doc: `server_config` / `print`
+
+| Field | Type | Notes |
+|---|---|---|
+| `supervisor_phone` | string | E.164 or local format with spaces; trimmed on read |
+
+### Seed document (production / staging)
+
+Create or update the document **before** shipping an APK that relies on
+Firestore as the primary source. Use the current hardcoded value so behavior
+is unchanged on first deploy:
+
+```json
+{
+  "supervisor_phone": "+971 501880810"
+}
+```
+
+### Console steps
+
+1. Open [Firebase Console](https://console.firebase.google.com/) → your project → **Firestore Database**.
+2. Open collection `server_config`.
+3. If `print` does not exist: **Add document** → Document ID `print` → add field `supervisor_phone` (string) with the value above → **Save**.
+4. To change the number later: open `server_config/print`, edit `supervisor_phone`, **Update**.
+
+Vans pick up the new value on the next app launch (or when `PrintSettingsCubit`
+refreshes). No APK rebuild is required for a phone-number change.
+
+## Client behavior
+
+- **Read-only** — Firestore security rules allow public read and deny all client writes (`allow write: if false` on `server_config/{docId}`). Only Console or Admin SDK can change this document.
+- **Hive cache** — After a successful fetch with a non-empty `supervisor_phone`, the app saves the value locally. An empty or missing Firestore field does **not** wipe the cache; the last good value is kept.
+- **Fallback** — If nothing was ever fetched or cached, the app uses `+971 501880810` so the footer is never blank.
+
+## Security rules
+
+The existing `match /server_config/{docId}` rule already covers `print` (public
+read, no client write). Deploy `firestore.rules` from the repo if the console
+copy is out of date; do not add a client write path.
diff --git a/firestore.rules b/firestore.rules
index 653c5f9..b42ef03 100644
--- a/firestore.rules
+++ b/firestore.rules
@@ -6,21 +6,22 @@ service cloud.firestore {
     // OTP). The previous `user_id == request.auth.uid` check denied first
     // login on some devices (type/field mismatch) and the app fail-opened
     // into a Zoho bind with no credentials.
     match /app_licenses/{licenseId} {
       allow read: if true;
       allow create: if request.auth != null;
       allow update: if request.auth != null
         && resource.data.user_id == request.auth.uid;
     }
 
-    // Zoho OAuth triple (`zoho`) and APK channel docs (`app_version`).
+    // Zoho OAuth triple (`zoho`), APK channel docs (`app_version`), and print
+    // settings (`print` — `supervisor_phone` for invoice/PDF footers).
     // Public read: AppUpdateGate runs before auth; a fresh phone must be able
     // to load `zoho` immediately after OTP. Clients must never write — any
     // authenticated van user used to be able to overwrite the refresh token.
     match /server_config/{docId} {
       allow read: if true;
       allow write: if false;
     }
 
     // Per-session diagnostic logs flushed on next app launch by DebugFileLogger.
     //
