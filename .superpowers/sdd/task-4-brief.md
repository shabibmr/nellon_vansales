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

