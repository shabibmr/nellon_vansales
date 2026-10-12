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
