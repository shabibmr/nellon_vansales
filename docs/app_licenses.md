# Device license & fleet metadata (`app_licenses`)

Each installed van device owns one Firestore document in `app_licenses`, keyed by
a UUID the app stores in secure storage. The document gates access (`enabled`,
`expiry_at`) and records who/what is running the app.

## When fields are written

| Event | What happens |
|---|---|
| **First login on a device** | `LicenseCubit.registerFirstLogin` creates the document with the full field set. |
| **Every subsequent login** | `LicenseCubit.checkLicense` patches the metadata fields below (best-effort, fire-and-forget — a failed write never blocks login). |

Before this change, the descriptive fields (`app_version`, `device_*`, `user_*`)
were frozen at first login, so a van that sideloaded a new APK still showed its
original build in Firestore.

## Fields refreshed on every login

| Field | Source | Notes |
|---|---|---|
| `last_login_at` | server timestamp | |
| `updated_at` | server timestamp | any-write marker, distinct from `last_login_at` |
| `login_count` | `increment(1)` | total successful logins |
| `app_version` | device | `version+build`, e.g. `1.4.0+42` |
| `device_os_version` | device | catches OS upgrades |
| `device_model` | device | |
| `device_id` | device | changes on factory reset / device swap |
| `user_name` / `user_email` | session | catches profile edits |
| `user_phone` | session | E.164; primary way operators identify a van |
| `previous_app_version` | prior `app_version` | **only** written when the build changed |
| `app_version_updated_at` | server timestamp | **only** written when the build changed — when the van took the update |

## Operator use

- **Which vans are on the latest build?** Filter `app_licenses` by `app_version`.
- **When did a van update?** `app_version_updated_at` + `previous_app_version`.
- **Stale / inactive device?** `last_login_at` far in the past.

## Security rules

No rules change. `match /app_licenses/{licenseId}` already allows an update when
`resource.data.user_id == request.auth.uid`, which covers every field above.
Clients still cannot flip `enabled` / `expiry_at` for a *different* user's
device, and admins change those via the Firebase Console.
