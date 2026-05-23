# Customer & Customer Form — Audit Report

**Date:** 2026-05-23  
**Time:** 17:25 IST  
**Auditor:** Antigravity AI  
**Project:** Van Sales Pro (`E:\work\nellon`)  
**Scope:** Customer domain, `CreateCustomerDialog`, `RouteSequenceTab`, `DashboardPage`, all dashboard widgets

---

## Summary

A full audit was conducted on the customer management flow — from domain entity through data layer, BLoC state, and UI presentation. Eight issues were identified and resolved. Static analysis warnings in the dashboard feature were reduced from **8 → 3** (3 remaining are benign false-positives).

---

## Files Audited

| File | Layer | Status |
|------|-------|--------|
| `lib/domain/models/customer.dart` | Domain | ✅ Clean |
| `lib/data/models/customer_model.dart` | Data | ✅ Clean |
| `lib/data/repositories/sales_repository_impl.dart` | Data | ✅ Clean |
| `lib/domain/repositories/sales_repository.dart` | Domain | ✅ Clean |
| `lib/ui/features/route/bloc/route_bloc.dart` | Presentation | ✅ Clean |
| `lib/ui/features/dashboard/views/dashboard_page.dart` | Presentation | ✅ Fixed |
| `lib/ui/features/dashboard/widgets/create_customer_dialog.dart` | Presentation | ✅ Fixed |
| `lib/ui/features/dashboard/widgets/route_sequence_tab.dart` | Presentation | ✅ Fixed |
| `lib/ui/features/dashboard/widgets/client_operations_sheet.dart` | Presentation | ✅ Fixed |
| `lib/ui/features/dashboard/widgets/global_search_sheet.dart` | Presentation | ✅ Fixed |
| `lib/ui/features/dashboard/widgets/van_action_tile.dart` | Presentation | ✅ Fixed |
| `lib/ui/features/dashboard/widgets/expense_log_dialog.dart` | Presentation | ⚠️ Minor (see below) |
| `lib/ui/features/dashboard/widgets/receipt_payment_dialog.dart` | Presentation | ⚠️ Minor (see below) |
| `lib/ui/features/dashboard/widgets/sales_return_dialog.dart` | Presentation | ⚠️ Minor (see below) |

---

## Issues Found & Fixed

### 🔴 Critical

#### 1. Layer Violation in `CreateCustomerDialog`
- **File:** `lib/ui/features/dashboard/widgets/create_customer_dialog.dart`
- **Before:** Dialog directly instantiated `HiveDatabaseService` via `sl<HiveDatabaseService>()` and called `_db.saveCustomers()`, `_db.enqueueSyncItem()` — bypassing the domain repository boundary.
- **After:** All persistence now goes through `sl<SalesRepository>()` — the correct clean architecture interface.

#### 2. No Form Validation
- **File:** `lib/ui/features/dashboard/widgets/create_customer_dialog.dart`
- **Before:** `TextFormField` widgets with no `validator`, no `Form` widget, no `GlobalKey<FormState>`. Empty or whitespace-only names were accepted silently.
- **After:** Wrapped all fields in a `Form` with a `GlobalKey<FormState>`. Per-field validators added:
  - Name: required, min 2 chars
  - Company: required
  - Phone: required, min 7 digits (strips non-digit chars)
  - Email: optional, regex pattern check if provided
  - Credit Limit: required, must parse as double

#### 3. Auto-Generated Bogus Email
- **File:** `lib/ui/features/dashboard/widgets/create_customer_dialog.dart`
- **Before:** `email: '${company.toLowerCase().replaceAll(' ', '')}@gmail.com'` — fabricated and silently assigned without user knowledge.
- **After:** Dedicated optional **Email Address** field added. If left blank, an empty string is stored. No fabrication.

---

### 🟠 High

#### 4. Hardcoded Route ID Fallback
- **File:** `lib/ui/features/dashboard/widgets/create_customer_dialog.dart`
- **Before:** `final activeRoute = _db.activeRouteId ?? 'route_north';` — fell back to a magic string.
- **After:** Reads from `RouteBloc.state.activeRouteId ?? salesRepo.activeRouteId ?? 'route_default'` — uses live BLoC state, then the repository, then a neutral generic fallback.

#### 5. `_loadDailyStats()` Called Inside `build()`
- **File:** `lib/ui/features/dashboard/views/dashboard_page.dart`
- **Before:** `_loadDailyStats()` was called unconditionally at the top of the `build()` method, triggering a synchronous Hive box read on every widget rebuild (including those caused by theme changes, tab switches, etc.).
- **After:** Removed from `build()`. Stats are correctly loaded only in `initState()` and through the `onXxxLogged` / `onSessionReconciled` callbacks after each user action.

---

### 🟡 Medium

#### 6. `use_build_context_synchronously` Lint Warnings
- **File:** `lib/ui/features/dashboard/widgets/create_customer_dialog.dart`
- **Before:** `context.read<RouteBloc>()`, `Navigator.pop(context)`, and `ScaffoldMessenger.of(context)` were all used after `await` calls, guarded only by `if (!context.mounted)` — the linter correctly flagged these as unsafe.
- **After:** References to `RouteBloc`, `Navigator.of(context)`, and `ScaffoldMessenger.of(context)` are now captured **before the first `await`** and stored in local variables. Post-await guard uses `if (!mounted)` (State's own `mounted` property, which is linter-safe).

---

### 🔵 Info / Code Quality

#### 7. Dead Code — `_tempMatchLength` Method
- **File:** `lib/ui/features/dashboard/widgets/route_sequence_tab.dart`
- **Before:** `int _tempMatchLength(String id)` was defined but never called anywhere.
- **After:** Deleted.

#### 8. Deprecated `withOpacity()` API
- **Files:** `create_customer_dialog.dart`, `route_sequence_tab.dart`, `client_operations_sheet.dart`, `global_search_sheet.dart`, `van_action_tile.dart`
- **Before:** Used deprecated `.withOpacity(double)` which causes color precision loss in newer Flutter versions.
- **After:** Replaced with `.withValues(alpha: double)` — the recommended API since Flutter 3.27+.

---

## Remaining Items (Not Fixed — Intentional)

### ⚠️ `DropdownButtonFormField(value:)` — False Positive Lint

| File | Line | Lint ID |
|------|------|---------|
| `expense_log_dialog.dart` | 139 | `deprecated_member_use` |
| `receipt_payment_dialog.dart` | 61 | `deprecated_member_use` |
| `sales_return_dialog.dart` | 55 | `deprecated_member_use` |

**Explanation:** The linter flags `DropdownButtonFormField(value: _selectedItem)` because the underlying `FormField` base class deprecated `value` in favour of `initialValue`. However, `value` on `DropdownButtonFormField` is its own distinct parameter that controls the *currently selected item* — replacing it with `initialValue` would break reactive dropdown binding on `setState` calls. This is a known SDK false-positive and is **safe to leave as-is**.

---

## Static Analysis Result

```
Before audit:  8 info-level issues
After audit:   3 info-level issues (all benign false-positives)
Errors:        0
Warnings:      0
```

---

## Architecture Observations (No Action Needed)

- **`Customer` entity** is well-structured: immutable, Equatable-based, with `copyWith`. ✅
- **`CustomerModel`** correctly extends `Customer` and handles both Zoho API field names (`contact_id`, `contact_name`, `outstanding_receivable_amount`) and local camelCase aliases. ✅
- **`RouteBloc`** correctly owns all customer search and filter logic; `SearchCustomers` event filters in-memory without hitting Hive. ✅
- **`ClientOperationsSheet`** correctly receives the `Customer` entity and delegates all actions upward via callbacks — no direct business logic. ✅
- **`SalesRepositoryImpl`** is a clean passthrough to `HiveDatabaseService` with no added coupling. ✅

---

*Report generated by Antigravity AI on 2026-05-23 at 17:25 IST.*
