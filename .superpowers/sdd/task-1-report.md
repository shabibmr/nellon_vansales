# Task 1 Report: Domain model, label helper, and tests

## Status

**DONE**

## Summary

Added pure Dart domain types for Firestore-backed supervisor phone printing:

- `PrintSettings` model with `fromMap`, `toMap`, `resolvedPhone`, and `fallbackSupervisorPhone`
- `formatSupervisorLine` helper for consistent "Supervisor : …" footer labeling
- Unit tests covering map parsing, fallback resolution, and label formatting

No Firestore, PDF, or thermal wiring in this task (deferred to later tasks).

## Files Created

| File | Purpose |
|------|---------|
| `lib/domain/models/print_settings.dart` | Equatable domain model |
| `lib/domain/utils/supervisor_label.dart` | Shared supervisor line formatter |
| `test/print_settings_test.dart` | Unit tests (5 cases) |

## TDD Evidence

### RED — tests before implementation

Command:

```
flutter test test/print_settings_test.dart
```

Result: **FAIL** (exit code 1)

```
Error when reading 'lib/domain/models/print_settings.dart': The system cannot find the file specified
Error when reading 'lib/domain/utils/supervisor_label.dart': The system cannot find the file specified
Undefined name 'PrintSettings'
Method not found: 'formatSupervisorLine'
```

Compilation failed because the model and helper did not exist yet.

### GREEN — after implementation

Command:

```
flutter test test/print_settings_test.dart
```

Result: **PASS** (exit code 0)

```
00:00 +5: All tests passed!
```

Tests exercised:

1. `PrintSettings.fromMap` trims `supervisor_phone`
2. Missing/blank `supervisor_phone` → empty string
3. `resolvedPhone` falls back to `+971 501880810` when empty
4. `formatSupervisorLine` prefixes bare phone numbers
5. `formatSupervisorLine` does not double-prefix already labeled lines

## Commit

```
d592b75 Add PrintSettings model for Firestore supervisor phone.
```

3 files changed, 77 insertions(+).

## Self-Review

- **Scope**: Only the three specified files were added; no PDF/thermal/Firestore changes.
- **Conventions**: Matches existing domain models (`ServerConfig`) — `Equatable`, `fromMap`/`toMap`, pure Dart in `domain/`.
- **Fallback constant**: `+971 501880810` matches the brief and preserves current hardcoded invoice footer behavior when Firestore/cache are empty.
- **Label helper**: Case-insensitive `startsWith('supervisor')` prevents double-prefixing; empty input returns empty string (callers use `resolvedPhone` before formatting).
- **Unrelated files**: `license_service.dart`, `license_cubit.dart`, `license_cubit_test.dart`, and `.superpowers` docs were not staged or committed.

## Concerns

None.
