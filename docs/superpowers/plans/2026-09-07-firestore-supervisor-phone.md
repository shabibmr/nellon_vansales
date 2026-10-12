# Firestore Supervisor Phone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Invoice (and other voucher/report) print footers show the supervisor phone from Firestore instead of the hardcoded UAE number, while still printing that number if Firestore/cache is empty.

**Architecture:** Store a phone-only string on `server_config/print` (not on `server_config/zoho`). Read it with a dedicated repository, cache it in Hive `app_config_box` for offline vans, expose it from an app-level cubit, and pass it into PDF + ESC/POS footers. Keep a single fallback constant (`+971 501880810`) so existing vans do not print a blank supervisor line before the Firestore doc is seeded.

**Tech Stack:** Flutter/Dart, Cloud Firestore (`server_config/{docId}` already public-read / client-write-denied), Hive (`LocalStorageService` / `app_config_box`), GetIt + `RepositoryProvider` / `BlocProvider` in `app.dart`.

## Global Constraints

- Do **not** put `supervisor_phone` on `server_config/zoho`. That document is Zoho OAuth; `ServerConfig.isValid` and cache-wipe rules must stay credential-only.
- Firestore collection/doc: `server_config` / `print`. Field: `supervisor_phone` (string, E.164 or display form, e.g. `+971 501880810`). Number only — templates prepend `Supervisor : `.
- Existing rules already cover the new doc (`match /server_config/{docId}` in `firestore.rules`: `allow read: if true; allow write: if false`). Clients never write this document.
- Fail-open: missing doc, empty field, permission error, or offline with empty cache → use `PrintSettings.fallbackSupervisorPhone`.
- `sl<T>()` only in `injection.dart` and `app.dart`. Feature widgets/BLoCs take `PrintSettingsRepository` / cubit from `context.read`.
- Cover **PDF invoices and thermal invoices**, and the shared footer used by other vouchers and thermal reports so the number cannot drift.
- Do not add a Settings UI or a write path. Operators change the number in Firebase Console (or Admin SDK).

## File map

| File | Responsibility |
|---|---|
| `lib/domain/models/print_settings.dart` | Domain model + fallback constant + `fromMap` |
| `lib/domain/utils/supervisor_label.dart` | `formatSupervisorLine(String phone)` → `Supervisor : …` |
| `lib/domain/repositories/print_settings_repository.dart` | Sync getter + async refresh |
| `lib/data/repositories/print_settings_repository_impl.dart` | Firestore fetch + Hive cache |
| `lib/data/services/local_storage_service.dart` | Persist `supervisor_phone` |
| `lib/ui/features/print_settings/cubit/print_settings_cubit.dart` | Hydrate cache, refresh remote, emit phone |
| `lib/data/services/injection.dart`, `lib/app.dart` | Register + provide cubit |
| PDF templates / `voucher_pdf_service.dart` / `voucher_pdf_bloc.dart` | Stop defaulting to hardcoded const; take runtime phone |
| `esc_pos_ticket_builder.dart` + ticket builders + thermal cubit/widget | Footer takes `supervisorPhone` |
| Tests listed per task | Model, repo, cubit, PDF/thermal footer |

---

### Task 1: Domain model, label helper, and tests

**Files:**
- Create: `lib/domain/models/print_settings.dart`
- Create: `lib/domain/utils/supervisor_label.dart`
- Create: `test/print_settings_test.dart`

**Interfaces:**
- Produces: `PrintSettings.fallbackSupervisorPhone`, `PrintSettings.fromMap`, `PrintSettings.resolvedPhone`, `formatSupervisorLine(String phone)`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/print_settings.dart';
import 'package:van_sales/domain/utils/supervisor_label.dart';

void main() {
  group('PrintSettings.fromMap', () {
    test('reads supervisor_phone', () {
      final settings = PrintSettings.fromMap({
        'supervisor_phone': ' +971 50 111 2222 ',
      });
      expect(settings.supervisorPhone, '+971 50 111 2222');
    });

    test('empty or missing field yields empty phone', () {
      expect(PrintSettings.fromMap({}).supervisorPhone, '');
      expect(PrintSettings.fromMap({'supervisor_phone': '  '}).supervisorPhone, '');
    });

    test('resolvedPhone uses fallback when empty', () {
      expect(
        const PrintSettings(supervisorPhone: '').resolvedPhone,
        PrintSettings.fallbackSupervisorPhone,
      );
      expect(
        const PrintSettings(supervisorPhone: '+971 50 000 0000').resolvedPhone,
        '+971 50 000 0000',
      );
    });
  });

  group('formatSupervisorLine', () {
    test('prefixes Supervisor when the value is a phone', () {
      expect(
        formatSupervisorLine('+971 501880810'),
        'Supervisor : +971 501880810',
      );
    });

    test('does not double-prefix an already labeled line', () {
      expect(
        formatSupervisorLine('Supervisor : +971 501880810'),
        'Supervisor : +971 501880810',
      );
    });
  });
}
```

- [ ] **Step 2: Run tests (expect FAIL — missing types)**

Run: `flutter test test/print_settings_test.dart`

- [ ] **Step 3: Implement model + helper**

`lib/domain/models/print_settings.dart`:

```dart
import 'package:equatable/equatable.dart';

class PrintSettings extends Equatable {
  /// Last known hardcoded invoice footer number. Used only when Firestore
  /// and cache have no value so vans never print a blank supervisor line.
  static const String fallbackSupervisorPhone = '+971 501880810';

  final String supervisorPhone;

  const PrintSettings({required this.supervisorPhone});

  String get resolvedPhone =>
      supervisorPhone.trim().isEmpty ? fallbackSupervisorPhone : supervisorPhone.trim();

  factory PrintSettings.fromMap(Map<String, dynamic> map) {
    return PrintSettings(
      supervisorPhone: (map['supervisor_phone'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {'supervisor_phone': supervisorPhone};

  @override
  List<Object?> get props => [supervisorPhone];
}
```

`lib/domain/utils/supervisor_label.dart`:

```dart
String formatSupervisorLine(String phone) {
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.toLowerCase().startsWith('supervisor')) return trimmed;
  return 'Supervisor : $trimmed';
}
```

Move the prefix logic out of `SharedPdfTemplate.buildFooter` later (Task 4) so PDF and thermal share this helper.

- [ ] **Step 4: Run tests (expect PASS)**

Run: `flutter test test/print_settings_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/print_settings.dart lib/domain/utils/supervisor_label.dart test/print_settings_test.dart
git commit -m "Add PrintSettings model for Firestore supervisor phone."
```

---

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

### Task 4: PDF invoices (and other voucher PDFs)

**Files:**
- Modify: `lib/ui/features/voucher_pdf/templates/shared_pdf_template.dart` — use `formatSupervisorLine`; stop treating `supervisorContact` as the only source
- Modify: `lib/data/services/voucher_pdf_service.dart` — default `supervisorPhone` to `PrintSettings.fallbackSupervisorPhone` (number only) **or** require callers to pass it
- Modify: `lib/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart` — inject `PrintSettingsRepository`, pass `supervisorPhone: printSettings.supervisorPhone` into `generateVoucherPdf`
- Modify: `lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart` — pass repository into `VoucherPdfBloc`
- Modify: per-template default args (`invoice_pdf_template.dart` and siblings) so the default is fallback **number**, not the labeled const
- Modify: `test/voucher_pdf_service_test.dart` (and any template tests) to pass an explicit phone and assert the footer

**Interfaces:**
- Consumes: `PrintSettingsRepository.supervisorPhone`, `formatSupervisorLine`
- Produces: PDF footer line `Supervisor : <firestore or fallback>`

- [ ] **Step 1: Change `SharedPdfTemplate.buildFooter`**

Replace the `startsWith('supervisor')` inline logic with `formatSupervisorLine`. Change `static const supervisorContact` to:

```dart
static const String supervisorContact = PrintSettings.fallbackSupervisorPhone;
```

or delete the const and use `PrintSettings.fallbackSupervisorPhone` everywhere that still needs a default.

- [ ] **Step 2: Thread the phone through `VoucherPdfBloc._buildBytes`**

```dart
final VoucherPdfRepository pdfService;
final PrintSettingsRepository printSettings;
// ...
return pdfService.generateVoucherPdf(
  type: type,
  voucher: voucher,
  org: org,
  customer: customer,
  salesperson: salesperson,
  supervisorPhone: printSettings.supervisorPhone,
  pageFormat: pageFormat,
);
```

Wire the extra constructor arg in `VoucherPdfActionsWidget` via `ctx.read<PrintSettingsRepository>()`.

- [ ] **Step 3: Tests**

Add/adjust a PDF generation test that:
1. Uses a fake `PrintSettingsRepository` with `+971 50 999 0000`
2. Generates an invoice PDF (existing voucher PDF tests already build bytes)
3. Asserts extracted text contains `Supervisor : +971 50 999 0000` and does **not** require the old number

Keep one test that omits override and still contains `Supervisor : +971 501880810` (fallback).

- [ ] **Step 4: Run tests + commit**

```bash
flutter test test/voucher_pdf_service_test.dart
git add lib/ui/features/voucher_pdf lib/data/services/voucher_pdf_service.dart lib/domain/repositories/voucher_pdf_repository.dart test/voucher_pdf_service_test.dart
git commit -m "Print Firestore supervisor phone on voucher PDFs."
```

---

### Task 5: Thermal invoice + report footer

**Files:**
- Modify: `lib/data/services/esc_pos/esc_pos_ticket_builder.dart` — `footer({…, String? supervisorPhone})`; print `formatSupervisorLine(phone ?? PrintSettings.fallbackSupervisorPhone)`; **delete** `static const supervisorContact`
- Modify: `lib/data/services/esc_pos/voucher_ticket_builder.dart` — pass `supervisorPhone` into every `tail.footer(...)`
- Modify: `lib/data/services/esc_pos/report_ticket_builder.dart` — same
- Modify: `lib/data/services/thermal_printer_service.dart` + `lib/domain/repositories/thermal_printer_repository.dart` — add `String? supervisorPhone` to `printVoucher` / `buildVoucherPreview` / `printReport` / `buildReportPreview`
- Modify: `lib/ui/features/thermal_print/cubit/thermal_printer_cubit.dart` — forward the argument
- Modify: `lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart` — `_thermalContext` includes `supervisorPhone: context.read<PrintSettingsCubit>().supervisorPhone`
- Modify: `lib/ui/core/widgets/sortable_report_scaffold.dart`, `lib/ui/features/reports/views/shipment_orders_report_page.dart`, `lib/ui/features/ledger/views/customer_ledger_page.dart` — pass the same cubit phone into preview/print report
- Modify: `test/esc_pos_ticket_builder_test.dart`, `test/report_ticket_builder_test.dart` — default still matches fallback; add a case with a custom number

**Interfaces:**
- Consumes: `formatSupervisorLine`, `PrintSettingsCubit.supervisorPhone`
- Produces: thermal line `Supervisor : <phone>` immediately after the salesman line

- [ ] **Step 1: Change `EscPosTicketBuilder.footer`**

```dart
List<int> footer({
  String? salespersonName,
  String? salespersonPhone,
  String? supervisorPhone,
}) {
  // ... existing salesman line ...
  final supervisorLine = formatSupervisorLine(
    (supervisorPhone == null || supervisorPhone.trim().isEmpty)
        ? PrintSettings.fallbackSupervisorPhone
        : supervisorPhone,
  );
  bytes.addAll(left(truncate(supervisorLine, columns)));
  bytes.addAll(center('Thank you'));
  // ...
}
```

Thread `supervisorPhone` through `VoucherTicketBuilder.build` / `_invoice` / `_order` / etc. (every `tail.footer` call). Same for `ReportTicketBuilder`.

- [ ] **Step 2: Widget wiring**

In `_thermalContext`, add `supervisorPhone` from `PrintSettingsCubit`. Pass it into `printVoucher` / `previewVoucher`.

For reports, read the cubit at the existing `previewReport` / `printReport` call sites (three files listed above). Do not hardcode.

- [ ] **Step 3: Update tests that currently assert `Supervisor : +971 501880810`**

Those assertions stay valid as the **fallback**. Add:

```dart
test('footer uses the supplied supervisor phone', () {
  final preview = /* build invoice ticket with supervisorPhone: '+971 50 111 2222' */;
  expect(preview.plainText, contains('Supervisor : +971 50 111 2222'));
  expect(preview.plainText, isNot(contains('+971 501880810')));
});
```

- [ ] **Step 4: Run tests + commit**

```bash
flutter test test/esc_pos_ticket_builder_test.dart test/report_ticket_builder_test.dart
git add lib/data/services/esc_pos lib/data/services/thermal_printer_service.dart lib/domain/repositories/thermal_printer_repository.dart lib/ui/features/thermal_print lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart lib/ui/core/widgets/sortable_report_scaffold.dart lib/ui/features/reports/views/shipment_orders_report_page.dart lib/ui/features/ledger/views/customer_ledger_page.dart test/esc_pos_ticket_builder_test.dart test/report_ticket_builder_test.dart
git commit -m "Print Firestore supervisor phone on thermal tickets."
```

---

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

### Task 7: Cleanup and verification

- [ ] **Step 1: Grep for leftovers**

```bash
rg "501880810" --glob "*.dart"
rg "supervisorContact" --glob "*.dart"
```

Allowed leftovers: `PrintSettings.fallbackSupervisorPhone` definition and tests that assert fallback. No second hardcoded copy in PDF/thermal builders.

- [ ] **Step 2: Analyzer + tests**

```bash
flutter analyze
flutter test test/print_settings_test.dart test/print_settings_cubit_test.dart test/print_settings_repository_impl_test.dart test/local_storage_service_test.dart test/voucher_pdf_service_test.dart test/esc_pos_ticket_builder_test.dart test/report_ticket_builder_test.dart
```

- [ ] **Step 3: Manual van check**

1. Seed `server_config/print` with `+971 50 111 2222`.
2. Cold start app (so cubit `refresh()` runs).
3. Open a sales invoice → A4 PDF preview footer → `Supervisor : +971 50 111 2222`.
4. Thermal preview of the same invoice → same line.
5. Airplane mode → reprint → still the cached number (not blank).
6. Temporarily delete the field or the doc → still fallback or last cache, never blank.

- [ ] **Step 4: Final commit if grep/analyze required extra deletes**

---

## Out of scope

- Per-salesperson or per-route supervisor numbers (single org-wide string).
- In-app editor for the number.
- Live Firestore snapshots (license/login refresh + cache is enough).
- Putting the field on `app_licenses` (that is per-device, not org branding).

## Spec coverage

| Requirement | Task |
|---|---|
| Fetch supervisor phone from Firestore | 2, 3, 6 |
| Invoice PDF uses it | 4 |
| Stop using hardcoded as the live source | 4, 5, 7 |
| Offline vans still print a number | 2 (Hive) + fallback in model |
| Thermal invoice (same hardcoded string today) | 5 |
| Other vouchers/reports sharing the footer | 4, 5 |

## Placeholder scan

No TBD/TODO steps. Signatures named above are the ones later tasks consume (`supervisorPhone` getter, `refresh()`, `formatSupervisorLine`, `PrintSettings.fallbackSupervisorPhone`).
