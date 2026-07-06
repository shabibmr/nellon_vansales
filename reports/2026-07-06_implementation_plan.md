# Implementation Plan — Van Sales Hardening (from 2026-07-06 Code Review)

## Context

The `van_sales` Flutter app scored **7/10 for production readiness** in the 2026-07-06 review
(`reports/2026-07-06_code_review.md`). Its offline-first design is excellent (9/10), but a set of
**financial-precision, security, and consistency issues** block a wider pilot rollout. This plan
consolidates every "Suggested Improvement" scattered across the report's 20 sections (per-section
recommendations, Top 20 Critical Issues, Top 20 Quick Wins, and the Prioritized Roadmap) into a
**single ordered backlog**, grouped into 5 execution phases from most to least important.

Verified against the current codebase:
- Hard-coded Zoho creds — `lib/data/services/zoho_api_client.dart:17-21`.
- Compile-time mock flags — `zoho_api_client.dart:36` (`_mockTransactions=true`), `:41` (`_mockSalesOrderTransactions=false`).
- No `Money`/`Decimal` type anywhere; all amounts are `double`.
- `SalesReturn.total` omits tax & discount — `lib/domain/models/sales_return.dart:29`.
- 21 `print()` calls across 4 files (`zoho_api_client.dart` ×16, `sync_worker.dart`, `license_cubit.dart` ×3, `main.dart`).
- Duplicate wrapper dialogs under `sales_invoice/widgets/` and `sales_order/widgets/` delegating to `core/widgets/`.
- Date-filter logic repeated in 6 BLoCs (route, sales_invoice, sales_order, receipts, expenses, sales_return).

---

## Phase 1 — Critical (blockers before wider rollout)


**1.2 Introduce a `Money` value object for all amounts**
- Add `lib/domain/value_objects/money.dart` wrapping `package:decimal` (new dep). Central
  arithmetic, rounding, and formatting; kill scattered `double` math.
- Migrate line-item + document totals: `sales_invoice.dart`, `sales_order.dart`,
  `sales_return.dart`, receipt allocations. Keep Hive JSON on-the-wire compatible (store as string
  or scaled int; add adapter migration).
- Route all display through `Money.format` / existing `lib/ui/core/utils/currency.dart`.

**1.3 Fix `SalesReturn` total to include tax & discount**
- `sales_return.dart:29` currently `rate * returnedQuantity`. Align with `InvoiceLineItem` logic
  (subTotal → tax → discount) so returns reconcile with the originating invoice and Zoho.

**1.4 Domain-level stock rules + negative-stock prevention**
- Move the `allowedStock` check out of `SalesInvoiceBloc` into a domain/repository rule so the
  save path (`saveLocalInvoice`) cannot silently floor stock to 0.
- Single enforced invariant used by both UI validation and persistence.

**1.5 Make mock/live behavior runtime-configurable and visible**
- Replace compile-time `_mockTransactions` / `_mockSalesOrderTransactions` with a value from
  server config / `ServerConfigCubit`.
- Surface a persistent "MOCK MODE" indicator in the app bar / sync banner when active.

**1.6 Document + align rounding strategy vs Zoho**
- Write down the discount-vs-tax order and `roundOff` behavior; verify it matches Zoho Books.
  Encode as tests once `Money` exists.

---

## Phase 2 — High (correctness, dedup, tests, workflow)

**2.1 Refactor monolithic BLoC state**
- Split combined list + editor state in `SalesInvoiceBloc`, `SalesOrderBloc` (and peers) into
  dedicated editor Cubits or sealed state classes.

**2.2 Centralize the duplicated date-filter logic**
- Extract a `ui/core/bloc/` mixin (e.g. `DateFilteredListState`) with `startDate/endDate` +
  `filtered*` getters; apply to all 6 list BLoCs.

**2.3 Remove thin per-feature wrapper dialogs**
- Delete `sales_invoice/widgets/item_line_editor_dialog.dart`, `item_search_dialog.dart` and the
  `sales_order/` twins; point call sites at `core/widgets/` (`SharedItemLineEditorDialog`,
  `ItemSearchSheet`). Enforce "use core first".

**2.4 Structured logging + error classification**
- Replace all 21 `print()` with a logger (or `debugPrint`); sanitize secrets/PII.
- Distinguish transient (network) vs permanent (validation) errors in state; drive retry UX.

**2.5 Enforce day-close / cash-closing workflow**
- Gate logout / next-day in `SessionGateway` on completed reconciliation.

**2.6 Comprehensive tests on critical paths**
- `mockito` repo mocks. Prioritize: sync ID-resolution (`_resolveTempCustomerIdsInQueue`,
  `_resolveTempOrderIdsInQueue`, `_persistOrderZohoId`), full invoice/receipt/return financial
  round-trip, stock adjustment edge cases, offline-queue failure. Expand `domain_totals_test.dart`.

**2.7 Auto-retry / backoff for failed sync items** + "Retry Failed" / "Clear Queue" sync UI actions.

**2.8 Refresh open-invoice snapshot in the receipt flow** (avoid stale allocation targets).

---

## Phase 3 — Medium (performance, responsiveness, UX speed)

- **Selective rebuilds:** add `buildWhen`/`listenWhen` to heavy screens (dashboard, editors).
- **Memoize / incrementally update daily stats** (dashboard currently full-folds on init).
- **`const` pass** across widgets; add `Key`s to important widgets.
- **Responsive layer:** `LayoutBuilder` + breakpoints for dashboard/editors; apply `SafeArea`
  consistently; improve keyboard handling for tablet/landscape.
- **Barcode / QR scanning** for items & customers (biggest field-productivity win).
- **Persistent offline banner + tap-to-retry** on every screen.
- **Dedup PDF currency formatting** into one shared helper (`currency.dart`).
- **UX speed:** recent/frequent customers & items strip; "repeat last order"; low-stock highlight
  in item search; numeric keypad for quantity; per-master sync progress + ETA.
- Extract magic strings to enums: payment modes (`'Cash'`), queue types (`'customer'`/`'invoice'`).
- Improve error messages with categories; add undo for line-item removal.

---

## Phase 4 — Low / Polish + Future

- Accessibility audit: `Semantics` labels on key actions; text-scaling support.
- Localization: `flutter_localizations` + `l10n.yaml`.
- Advanced inventory: reserved-vs-available, batch/expiry (if domain requires).
- Skeleton loaders; better animations.
- Performance profiling pass on large ListViews.
- Remove dead/legacy cart code paths; drop `ignore_for_file` pragmas where fixable.
- Certificate pinning; input sanitization; harden first-login license provisioning.
- Crash reporting / global error boundary.
- README note documenting sync ID-resolution rules.

---

## Phase 0 — Quick Wins (can run in parallel, low risk)

Pulled from the report's "Top 20 Quick Wins"; safe to land early alongside Phase 1/2:
`dart fix --apply` + `flutter analyze`; `print`→`debugPrint`; `const` sweep; `SafeArea` pass;
surface `roundOff` in editors; stock warning indicators; make mock mode visible; add Retry
Failed/Clear Queue; ensure `context.org` + `formatCurrency` used everywhere.

---

## Execution Order Summary

1. **Phase 0 quick wins** (parallel, low risk) →
2. **Phase 1 Critical** (creds, `Money`, returns, stock, mock-flag, rounding) →
3. **Phase 2 High** (state refactor, dedup, logging, day-close, tests) →
4. **Phase 3 Medium** →
5. **Phase 4 Low/Future**.

Report's recommendation: treat the next **2–4 weeks as a hardening phase** (Phases 0–2) before
expanding the pilot.

---

## Verification

- `flutter analyze` clean; `dart fix --apply` leaves no residual fixes.
- `flutter test` green, with new suites for `Money`, sync ID-resolution, and return totals.
- Grep confirms zero literal credentials and zero `print(` in `lib/`.
- Manual: run app in mock mode → confirm visible indicator; switch server config to live →
  confirm indicator clears and a sales order pushes.
- End-to-end: create invoice → return → receipt for one customer; confirm totals reconcile to the
  cent against Zoho Books.
