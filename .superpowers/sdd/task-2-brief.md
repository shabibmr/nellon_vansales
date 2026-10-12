### Task 2: Hive cache + Firestore repository

**Files:**
- Modify: `lib/data/services/local_storage_service.dart`
- Create: `lib/domain/repositories/print_settings_repository.dart`
- Create: `lib/data/repositories/print_settings_repository_impl.dart`
- Modify: `test/local_storage_service_test.dart` (add supervisor phone round-trip)
- Create: `test/print_settings_repository_impl_test.dart`

**Interfaces:**
- Consumes: `PrintSettings.fromMap`, `PrintSettings.resolvedPhone`
- Produces:
  - `LocalStorageService.saveSupervisorPhone(String phone)` / `readSupervisorPhone()`
  - `PrintSettingsRepository.supervisorPhone` (sync, cache-or-fallback)
  - `PrintSettingsRepository.refresh()` → `Future<PrintSettings>`

- [ ] **Step 1: Extend LocalStorageService**

Add next to the Zoho keys:

```dart
static const String _supervisorPhoneKey = 'supervisor_phone';
```

```dart
Future<String?> readSupervisorPhone() async {
  try {
    final box = await _getBox();
    final value = (box.get(_supervisorPhoneKey) as String?)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  } catch (e) {
    DebugFileLogger.log('[LocalStorage] ❌ readSupervisorPhone error: $e');
    return null;
  }
}

Future<void> saveSupervisorPhone(String phone) async {
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return;
  try {
    final box = await _getBox();
    await box.put(_supervisorPhoneKey, trimmed);
  } catch (e) {
    DebugFileLogger.log('[LocalStorage] ❌ saveSupervisorPhone FAILED: $e');
  }
}
```

Do **not** clear the cache when Firestore returns empty — keep last-good phone (same fail-open idea as Zoho credentials).

- [ ] **Step 2: Repository interface**

```dart
import '../models/print_settings.dart';

abstract class PrintSettingsRepository {
  /// Cached (or fallback) phone for PDF/thermal. Never empty.
  String get supervisorPhone;

  /// Fetches `server_config/print`, updates cache when the field is non-empty.
  Future<PrintSettings> refresh();
}
```

- [ ] **Step 3: Implementation**

Follow `AppUpdateService` / `LicenseService.fetchServerConfig` style (timeout, permission-denied logging). Inject `FirebaseFirestore?` and `LocalStorageService` for tests.

```dart
class PrintSettingsRepositoryImpl implements PrintSettingsRepository {
  PrintSettingsRepositoryImpl({
    required LocalStorageService localStorage,
    FirebaseFirestore? firestore,
  })  : _localStorage = localStorage,
        _firestore = firestore;

  final LocalStorageService _localStorage;
  final FirebaseFirestore? _firestore;
  String _cached = PrintSettings.fallbackSupervisorPhone;

  FirebaseFirestore get firestore =>
      _firestore ?? FirebaseFirestore.instance;

  @override
  String get supervisorPhone =>
      _cached.trim().isEmpty ? PrintSettings.fallbackSupervisorPhone : _cached;

  Future<void> hydrate() async {
    final stored = await _localStorage.readSupervisorPhone();
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
    }
  }

  @override
  Future<PrintSettings> refresh() async {
    try {
      final doc = await firestore
          .collection('server_config')
          .doc('print')
          .get()
          .timeout(const Duration(seconds: 8));
      if (doc.exists && doc.data() != null) {
        final remote = PrintSettings.fromMap(doc.data()!);
        if (remote.supervisorPhone.isNotEmpty) {
          _cached = remote.supervisorPhone;
          await _localStorage.saveSupervisorPhone(_cached);
        }
      }
    } catch (e) {
      AppLogger.warning('PrintSettings', 'Failed to fetch server_config/print: $e');
    }
    return PrintSettings(supervisorPhone: supervisorPhone);
  }
}
```

- [ ] **Step 4: Tests**

`print_settings_repository_impl_test.dart`: fake Firestore is heavy; test the **resolution rules** with a test double of the repository if FakeFirestore is not already used. Prefer a small fake:

```dart
class MemoryPrintSettingsRepository implements PrintSettingsRepository {
  MemoryPrintSettingsRepository([this._phone = PrintSettings.fallbackSupervisorPhone]);
  String _phone;
  @override
  String get supervisorPhone => _phone;
  @override
  Future<PrintSettings> refresh() async => PrintSettings(supervisorPhone: _phone);
  void setPhone(String value) => _phone = value;
}
```

For `LocalStorageService`, add a Hive test (existing `local_storage_service_test.dart` already opens a test box): save then read `supervisor_phone`.

If the project already has a Firestore fake for `LicenseService`, reuse it to assert:
- non-empty remote overwrites cache
- empty remote leaves previous cache
- thrown fetch leaves previous cache / fallback

- [ ] **Step 5: Run tests**

Run: `flutter test test/local_storage_service_test.dart test/print_settings_repository_impl_test.dart test/print_settings_test.dart`

- [ ] **Step 6: Commit**

```bash
git add lib/data/services/local_storage_service.dart lib/domain/repositories/print_settings_repository.dart lib/data/repositories/print_settings_repository_impl.dart test/local_storage_service_test.dart test/print_settings_repository_impl_test.dart
git commit -m "Load supervisor phone from server_config/print with Hive cache."
```

---

