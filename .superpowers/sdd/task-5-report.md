# Task 5 Report: Thermal invoice + report footer

## Status
**Complete**

## Summary
Thermal voucher and report tickets now print the Firestore-configured supervisor phone instead of a hardcoded constant. The phone flows from `PrintSettingsCubit` through UI → `ThermalPrinterCubit` → repository/service → ticket builders → `EscPosTicketBuilder.footer`, which formats the line via `formatSupervisorLine` with `PrintSettings.fallbackSupervisorPhone` when no value is supplied.

## Changes

### `esc_pos_ticket_builder.dart`
- Removed `static const supervisorContact`.
- Added `supervisorPhone` parameter to `footer()`.
- Uses `formatSupervisorLine` with fallback to `PrintSettings.fallbackSupervisorPhone` when null/empty.

### `voucher_ticket_builder.dart`
- Added `supervisorPhone` to `build`, `buildPreview`, `_compose`, and all voucher-type builders.
- Every `tail.footer(...)` call passes `supervisorPhone`.

### `report_ticket_builder.dart`
- Added `supervisorPhone` to `build`, `buildPreview`, `_compose`.
- Footer tail passes `supervisorPhone`.

### `thermal_printer_repository.dart` / `thermal_printer_service.dart`
- Added optional `supervisorPhone` to `printVoucher`, `buildVoucherPreview`, `printReport`, `buildReportPreview`.

### `thermal_printer_cubit.dart`
- Forwards `supervisorPhone` on all four print/preview methods.

### UI wiring
- `voucher_pdf_actions_widget.dart` — `_thermalContext` includes `context.read<PrintSettingsCubit>().supervisorPhone`; passed to thermal preview/print.
- `sortable_report_scaffold.dart`, `shipment_orders_report_page.dart`, `customer_ledger_page.dart` — read cubit phone at thermal export call sites.

### Tests
- `test/esc_pos_ticket_builder_test.dart` — added `footer uses the supplied supervisor phone` (custom `+971 50 111 2222`; existing fallback assertions unchanged).
- `test/report_ticket_builder_test.dart` — same custom-phone case for report tickets.

## Tests
```
flutter test test/esc_pos_ticket_builder_test.dart test/report_ticket_builder_test.dart
```
**Result:** 24/24 passed

## Commit
```
5113c9d Print Firestore supervisor phone on thermal tickets.
```
12 files, +109 / −4

## Self-review

### What works well
- Parallels the PDF path (Task 4): same `formatSupervisorLine` + fallback constant.
- Supervisor line remains immediately after salesman line, before "Thank you".
- Optional parameter keeps existing call sites valid; tests without `supervisorPhone` still assert fallback `Supervisor : +971 501880810`.
- All three report thermal entry points wired consistently.

### Limitations
- `PrintSettingsCubit` must be in the widget tree at print time (already app-provided in `app.dart`).
- If Firestore hydrate is still in flight, cubit serves cached/fallback phone until refresh completes — same as PDF path.
- Test page (`buildTestPage`) intentionally omits supervisor footer.

### Not changed (by design)
- PDF templates / `shared_pdf_template.dart` layout.
- `money_math`, sales invoice domain totals.
- Settings UI (Task 6 scope if any).

### Working tree note
Uncommitted changes from other tasks remain (PDF templates, `money_math`, etc.) — excluded from this commit per brief.
