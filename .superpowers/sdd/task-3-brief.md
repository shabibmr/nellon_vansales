### Task 3: Cubit, DI, app providers

**Files:**
- Create: `lib/ui/features/print_settings/cubit/print_settings_cubit.dart`
- Create: `lib/ui/features/print_settings/cubit/print_settings_state.dart` (or emit `PrintSettings` directly)
- Modify: `lib/data/services/injection.dart`
- Modify: `lib/app.dart`
- Create: `test/print_settings_cubit_test.dart`

**Interfaces:**
- Consumes: `PrintSettingsRepository.hydrate` / `refresh` / `supervisorPhone`
- Produces: app-level `PrintSettingsCubit` with `String get supervisorPhone`

- [ ] **Step 1: Cubit**

Hydrate from Hive in the constructor (same race pattern as `ServerConfigCubit._hydrate`: complete a `hydrateDone` future for tests). Then `refresh()` Firestore in the background. Do not block `LicenseGate`.

```dart
class PrintSettingsCubit extends Cubit<PrintSettings> {
  PrintSettingsCubit({required PrintSettingsRepository repository})
      : _repository = repository,
        super(PrintSettings(supervisorPhone: repository.supervisorPhone)) {
    hydrateDone = _start();
  }

  final PrintSettingsRepository _repository;
  late final Future<void> hydrateDone;

  String get supervisorPhone => state.resolvedPhone;

  Future<void> _start() async {
    if (_repository is PrintSettingsRepositoryImpl) {
      await _repository.hydrate();
    }
    emit(PrintSettings(supervisorPhone: _repository.supervisorPhone));
    await _repository.refresh();
    emit(PrintSettings(supervisorPhone: _repository.supervisorPhone));
  }
}
```

Avoid the `is PrintSettingsRepositoryImpl` check in production: add `hydrate()` to the **interface** in Task 2 instead (`Future<void> hydrate();` no-op on fakes). Prefer that.

- [ ] **Step 2: Register in `injection.dart`**

After `LocalStorageService` / `LicenseService`:

```dart
sl.registerLazySingleton<PrintSettingsRepository>(
  () => PrintSettingsRepositoryImpl(localStorage: sl<LocalStorageService>()),
);
```

Call `hydrate()` inside cubit, not at `sl` registration (Hive must already be open — `setupDependencyInjection` already inits Hive first).

- [ ] **Step 3: Provide in `app.dart`**

- `RepositoryProvider<PrintSettingsRepository>(create: (_) => sl())`
- `BlocProvider<PrintSettingsCubit>(create: (_) => PrintSettingsCubit(repository: sl()))`

Place next to `ServerConfigCubit` / `AppUpdateCubit`.

- [ ] **Step 4: Cubit test**

Fake repo: hydrate sets phone `A`, refresh sets phone `B`. After `await cubit.hydrateDone`, state is `B`.

- [ ] **Step 5: Run tests + commit**

```bash
flutter test test/print_settings_cubit_test.dart
git add lib/ui/features/print_settings lib/data/services/injection.dart lib/app.dart test/print_settings_cubit_test.dart
git commit -m "Provide PrintSettingsCubit from cached Firestore print config."
```

---

