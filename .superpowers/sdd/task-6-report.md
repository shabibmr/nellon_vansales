# Task 6 Report: Seed Firestore and document ops

## Status

**Complete.** `firestore.rules` comment updated; operator doc added; committed on `feat/firestore-supervisor-phone`. Production/staging Firestore seed is documented for manual Console work (cannot be done from this machine).

## Commit

```
Document server_config/print supervisor phone for operators.
```

Hash: `ccdf50f`

Files committed:
- `firestore.rules` — `server_config` comment now lists `print` (`supervisor_phone`); rule behavior unchanged (`read: true`, `write: false`).
- `docs/print_settings.md` — operator guide: path, field, JSON seed, Console steps, cache/fallback behavior, security rules note.

## Brief checklist

| Step | Done | Notes |
|------|------|-------|
| Comment `firestore.rules` | Yes | Lists `zoho`, `app_version`, `print` |
| Operator doc | Yes | New `docs/print_settings.md` (not `USER_MANUAL.md` — operator audience) |
| Seed production/staging Firestore | Documented only | Exact JSON and Console steps in doc; operator must run before APK ship |
| Commit rules + docs only | Yes | No `.superpowers/`, no Dart changes |

## Operator actions (manual, pre-ship)

1. Firebase Console → Firestore → `server_config` → create/update doc `print`.
2. Set field `supervisor_phone` to `+971 501880810` (matches `PrintSettings.fallbackSupervisorPhone`).
3. Deploy `firestore.rules` from repo if console ruleset is stale (existing `server_config/{docId}` rule already covers `print`).

## Tests

**n/a** — documentation and rules comment only; no Dart or test changes.

## Self-review

- No client write path invented; doc states Console / Admin SDK only.
- Cache behavior documented: non-empty remote updates Hive; empty remote does not wipe cache (`PrintSettingsRepositoryImpl.refresh`).
- Fallback documented: `+971 501880810` when never fetched/cached.
- No Dart app logic changed.
- Commit scope limited to the two files specified in the brief.

## Concerns

- **Firestore seed not applied** — someone with Console access must create `server_config/print` before relying on Firestore as primary source; fallback keeps current behavior until then.
- **Rules deploy** — if production console rules differ from repo, operator should merge/deploy without replacing unrelated collections (same pattern as `docs/app_update.md`).
