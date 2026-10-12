# Task 3 Report: Cubit, DI, app providers

## Status

**Complete.** `PrintSettingsCubit` hydrates Hive then refreshes Firestore in the background; registered in GetIt and provided app-wide. Tests green; committed on `feat/firestore-supervisor-phone`.

## Commit

```
Provide PrintSettingsCubit from cached Firestore print config.
```

Hash: `fd070bb`

Files committed:
- `lib/ui/features/print_settings/cubit/print_settings_cubit.dart` (new)
- `lib/data/services/injection.dart`
- `lib/app.dart`
- `test/print_settings_cubit_test.dart` (new)

## TDD evidence

### Red → green sequence

1. **Test written first** (`test/print_settings_cubit_test.dart`) with `FakePrintSettingsRepository` — hydrate sets phone A (`+971 50 111 1111`), refresh sets phone B (`+971 50 222 2222`).
2. **First run failed to compile** — missing `PrintSettingsCubit`.
3. **Cubit implemented** — emits `PrintSettings` directly (no separate state file).
4. **Second run: 1/1 passed** (`flutter test test/print_settings_cubit_test.dart`).

### Coverage vs brief

| Requirement | Evidence |
|-------------|----------|
| `hydrate()` then `refresh()` on interface | `_start()` calls both without `is PrintSettingsRepositoryImpl` |
| `hydrateDone` for tests | `late final Future<void> hydrateDone` assigned in constructor |
| After `hydrateDone`, state is B | `hydrates from cache then refreshes from Firestore` |
| `supervisorPhone` getter | `state.resolvedPhone` |
| GetIt after `LicenseService` | `injection.dart` section 6 |
| `RepositoryProvider` + `BlocProvider` | `app.dart` next to `ServerConfigCubit` |
| Non-blocking startup | Constructor returns immediately; `_start()` is fire-and-forget |

## Implementation notes

- **State shape** — cubit emits `PrintSettings` directly (brief allowed this over a separate state file).
- **`isClosed` guards** — emit only when cubit still open after async gaps.
- **Not done (Task 4/5)** — PDF/thermal consumers not wired yet.
- **`sl<T>()` usage** — only in `injection.dart` and `app.dart` per project rules.

## Self-review

- Controller resolution #1 satisfied: `await _repository.hydrate()` on interface, no impl type check.
- Controller resolution #2 satisfied: background `_start()` does not block `LicenseGate`.
- Controller resolution #3 satisfied: no PDF/thermal wiring.
- Controller resolution #4 satisfied: `.superpowers` and `docs/superpowers` not committed.
- Pattern matches `ServerConfigCubit.hydrateDone` race-test hook.
- DI order correct: Hive init precedes `PrintSettingsRepositoryImpl` (uses `LocalStorageService`).

## Concerns

- No intermediate-state test for post-hydrate / pre-refresh emit (phone A); brief only required final state B after `hydrateDone`. Task 4 consumers read `supervisorPhone` getter which uses `resolvedPhone` — empty string still falls back correctly via model.
- Firestore `refresh()` runs on every app boot; acceptable per plan (same pattern as other server config). Offline boot uses hydrated cache only until refresh completes or fails (repository fail-open from Task 2).
