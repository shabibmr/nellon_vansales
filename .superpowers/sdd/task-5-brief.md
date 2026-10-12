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

