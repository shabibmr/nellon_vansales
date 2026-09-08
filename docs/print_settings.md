# Print phone numbers on vouchers (operators)

Van apps read two phone numbers from Firestore and print them on invoice PDFs,
thermal receipts, and related voucher headers/footers. Operators change the
numbers in the Firebase Console; van users cannot edit them from the app.

- **`supervisor_phone`** — printed in the voucher **footer** ("Supervisor : …").
- **`company_phone`** — printed in the voucher **letterhead header** and the
  "Supplier / Dispatcher" block, in place of the Zoho organisation phone.

## Firestore document

Collection / doc: `server_config` / `print`

| Field | Type | Notes |
|---|---|---|
| `supervisor_phone` | string | E.164 or local format with spaces; trimmed on read |
| `company_phone` | string | Company phone for the voucher letterhead; trimmed on read |

### Seed document (production / staging)

Create or update the document **before** shipping an APK that relies on
Firestore as the primary source. Use the current values so behaviour is
unchanged on first deploy:

```json
{
  "supervisor_phone": "+971 501880810",
  "company_phone": "+971589642244"
}
```

### Console steps

1. Open [Firebase Console](https://console.firebase.google.com/) → your project → **Firestore Database**.
2. Open collection `server_config`.
3. If `print` does not exist: **Add document** → Document ID `print` → add fields
   `supervisor_phone` and `company_phone` (both string) with the values above → **Save**.
4. To change a number later: open `server_config/print`, edit the field, **Update**.

Vans pick up the new value on the next app launch (or when `PrintSettingsCubit`
refreshes). No APK rebuild is required for a phone-number change.

## Client behavior

- **Read-only** — Firestore security rules allow public read and deny all client writes (`allow write: if false` on `server_config/{docId}`). Only Console or Admin SDK can change this document.
- **Hive cache** — After a successful fetch with a non-empty value, the app saves each number locally (`supervisor_phone`, `company_phone` keys). An empty or missing Firestore field does **not** wipe the cache; the last good value is kept.
- **Fallback** — If nothing was ever fetched or cached, the app uses `+971 501880810` (supervisor) and `+971589642244` (company) so the header/footer are never blank.

## Security rules

The existing `match /server_config/{docId}` rule already covers `print` (public
read, no client write). Deploy `firestore.rules` from the repo if the console
copy is out of date; do not add a client write path.
