# Task 2 Report: Hive cache + Firestore repository

## Status

**Complete.** All brief requirements implemented; tests green; committed on `feat/firestore-supervisor-phone`.

## Commit

```
Load supervisor phone from server_config/print with Hive cache.
```

Files committed:
- `lib/data/services/local_storage_service.dart`
- `lib/domain/repositories/print_settings_repository.dart`
- `lib/data/repositories/print_settings_repository_impl.dart`
- `test/local_storage_service_test.dart`
- `test/print_settings_repository_impl_test.dart`

## TDD evidence

### Red → green sequence

1. **Tests written first** (`test/print_settings_repository_impl_test.dart`, `test/local_storage_service_test.dart` supervisor-phone cases) before production code existed.
2. **First run failed to compile** — missing `PrintSettingsRepositoryImpl`, `readSupervisorPhone`, `saveSupervisorPhone`, and `_StubDocumentSnapshot` named-parameter typo (`_data` vs `data`).
3. **Implementation added** — `LocalStorageService` Hive keys, repository interface + impl.
4. **Second run: 20/20 passed** (`flutter test test/local_storage_service_test.dart test/print_settings_repository_impl_test.dart test/print_settings_test.dart`).

### Coverage vs brief resolution rules

| Rule | Test |
|------|------|
| Hive round-trip | `LocalStorageService saveSupervisorPhone persists phone…` (both test files) |
| Empty save ignored | `saveSupervisorPhone ignores empty values` |
| `hydrate()` loads cache | `hydrate loads cached phone from local storage` |
| Fallback before cache | `supervisorPhone uses fallback before hydrate` |
| Non-empty remote overwrites + persists | `non-empty remote overwrites cache and persists to storage` |
| Empty remote keeps last-good cache | `empty remote leaves previous cache and does not save` |
| Thrown fetch keeps cache | `thrown fetch leaves previous cache` |
| Missing doc → fallback | `missing document leaves fallback when cache is empty` |
| Consumer fake (brief) | `MemoryPrintSettingsRepository` |

### Test design

No `fake_cloud_firestore` dependency added. Firestore behavior tested via injectable `FirebaseFirestore?` and lightweight `Fake` stubs for `collection` → `doc` → `get` chain. Local storage uses both in-memory fakes and real Hive temp boxes (matching existing `local_storage_service_test.dart` pattern).

## Implementation notes

- **`hydrate()` on interface** — per controller resolution #1; Task 3 can call `hydrate()` without `is PrintSettingsRepositoryImpl`.
- **Doc path** — `server_config/print`, field `supervisor_phone` via `PrintSettings.fromMap`.
- **Fail-open** — empty remote does not call `saveSupervisorPhone`; prior Hive value and in-memory `_cached` preserved.
- **Permission-denied logging** — extra `AppLogger.error` when `isFirestorePermissionDenied(e)` (LicenseService / ServerConfig style).
- **Not done (Task 3)** — GetIt registration, cubit wiring.

## Self-review

- Interface matches brief + controller `hydrate()` requirement.
- Field names exact: `supervisor_phone` Hive key, Firestore map key.
- No changes to `server_config/zoho`, `injection.dart`, or docs.
- `supervisorPhone` getter never returns empty string (falls back to `PrintSettings.fallbackSupervisorPhone`).

## Concerns

- Stub Firestore fakes in tests are minimal; if Firestore API surface changes, stub chain may need updates. Acceptable trade-off vs adding `fake_cloud_firestore` dev dependency.
- Duplicate Hive round-trip tests exist in both test files (brief asked for both locations); harmless redundancy.
