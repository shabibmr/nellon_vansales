### Task 6: Seed Firestore and document ops

**Files:**
- Modify: `firestore.rules` — comment that `{docId}` includes `print` (no rule behavior change)
- Create or extend: `docs/app_update.md` is the wrong home. Add a short section to `docs/USER_MANUAL.md` **or** a new `docs/print_settings.md` (operators, not van users): how to set the number
- Firebase Console (manual, not in git): create document

**Firestore document to create (Console → Firestore → `server_config` → `print`):**

```json
{
  "supervisor_phone": "+971 501880810"
}
```

Start with the current hardcoded value so behavior is unchanged on first deploy. Later, edit only this field to change every van’s invoice footer after the next app launch / cubit refresh.

- [ ] **Step 1: Comment in `firestore.rules`**

Update the `server_config` comment from “Zoho OAuth triple (`zoho`) and APK channel docs (`app_version`)” to also list `print` (`supervisor_phone`).

- [ ] **Step 2: Operator doc (`docs/print_settings.md`)**

Document:
- Path `server_config/print`
- Field `supervisor_phone`
- Clients read-only; change via Console
- App caches last non-empty value in Hive; empty Firestore field does not wipe the cache
- Fallback if never fetched: `+971 501880810`

- [ ] **Step 3: Seed production/staging Firestore** before shipping the APK that removes the old const as the only source (fallback remains in code).

- [ ] **Step 4: Commit rules comment + docs** (not the secret-less console seed)

```bash
git add firestore.rules docs/print_settings.md
git commit -m "Document server_config/print supervisor phone for operators."
```

---

