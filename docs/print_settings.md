# Supervisor phone on printed vouchers (operators)

Van apps read the supervisor phone number from Firestore and print it on
invoice PDFs, thermal receipts, and related voucher footers. Operators change
the number in the Firebase Console; van users cannot edit it from the app.

## Firestore document

Collection / doc: `server_config` / `print`

| Field | Type | Notes |
|---|---|---|
| `supervisor_phone` | string | E.164 or local format with spaces; trimmed on read |

### Seed document (production / staging)

Create or update the document **before** shipping an APK that relies on
Firestore as the primary source. Use the current hardcoded value so behavior
is unchanged on first deploy:

```json
{
  "supervisor_phone": "+971 501880810"
}
```

### Console steps

1. Open [Firebase Console](https://console.firebase.google.com/) → your project → **Firestore Database**.
2. Open collection `server_config`.
3. If `print` does not exist: **Add document** → Document ID `print` → add field `supervisor_phone` (string) with the value above → **Save**.
4. To change the number later: open `server_config/print`, edit `supervisor_phone`, **Update**.

Vans pick up the new value on the next app launch (or when `PrintSettingsCubit`
refreshes). No APK rebuild is required for a phone-number change.

## Client behavior

- **Read-only** — Firestore security rules allow public read and deny all client writes (`allow write: if false` on `server_config/{docId}`). Only Console or Admin SDK can change this document.
- **Hive cache** — After a successful fetch with a non-empty `supervisor_phone`, the app saves the value locally. An empty or missing Firestore field does **not** wipe the cache; the last good value is kept.
- **Fallback** — If nothing was ever fetched or cached, the app uses `+971 501880810` so the footer is never blank.

## Security rules

The existing `match /server_config/{docId}` rule already covers `print` (public
read, no client write). Deploy `firestore.rules` from the repo if the console
copy is out of date; do not add a client write path.
