# Task 0.4 — Concrete design: `SalesReturnDialog` → BLoC/Cubit

**Decision: INCLUDE in the setState migration** (complete conversion; no residual `setState` in dashboard widgets).

**Source widget:** `lib/ui/features/dashboard/widgets/sales_return_dialog.dart`  
**Call site:** `DashboardPage._launchSalesReturnFlow` only  
**Related (do not conflate):** global `SalesReturnBloc` + `SalesReturnEditorPage` + `ReturnInvoiceSelectorDialog`

---

## 1. Problem statement

The dashboard “quick return” dialog still uses classic `StatefulWidget` + `setState` for:

| Field | Role |
|-------|------|
| `_selectedItem` | Dropdown selection |
| `_matchingInvoices` | Invoices containing that item (date-desc) |
| (implicit rebuild) | Rebuild invoice qty rows after item change |

Controllers (`_qtyControllers`) and `_formKey` are correctly widget-local already.

Submit path has the same latent bugs called out for create-customer / receipt:

- No try/catch → throw leaves the dialog with no recovery UI  
- No in-flight / double-tap guard  
- Side effects (`Navigator.pop`, snackbars, `onReturnConfirmed`) run inline after `await` with only a `mounted` check

---

## 2. Why not reuse global `SalesReturnBloc`

| Concern | Detail |
|---------|--------|
| **Shared global state** | `SalesReturnBloc` is in `app.dart` `MultiBlocProvider`. Its `editingItems` / `editingCustomer` / `isEditingNew` are co-used by the full return **editor** and list. Driving the dialog through it is the same class of hazard as invoice-flow + `SalesInvoiceBloc` (stale cart / half-edited voucher). |
| **Different product surface** | Dialog: one item, per-invoice qty, fixed reason `'Damaged packaging'`, no date picker, no multi-product lines. Editor: multi-item, reason field, date, customer change, list reload. |
| **Numbering / payload** | Dialog uses `RET-TEMP-…` credit-note prefix; editor uses `CN-TEMP-…`. Preserve dialog behavior unless product unifies later. |
| **DI surface** | Dialog talks to `HiveDatabaseService` + `SyncWorker` directly; editor goes through `SalesRepository` / `SyncRepository`. Migration should move the dialog onto repositories (testable), without expanding editor API. |

**Rule:** Do **not** dispatch `StartNewReturn` / `SaveReturn` from this dialog. Keep the quick path isolated.

Optional later refactor (out of scope): extract shared “eligible items + matching invoices” pure helpers used by both this cubit and `ReturnInvoiceSelectorDialog` / `ReturnItemSearchDialog`.

---

## 3. Chosen type: **Cubit** (not Bloc)

Name: **`SalesReturnQuickCubit`**

| Criterion (from migration plan) | Fit |
|---------------------------------|-----|
| Multiple distinct event types with different async orchestration | No — select item (sync), submit (one async flow) |
| Multi-step failure stages needing explicit events | No |
| Matches existing Cubit peers | Yes — same shape as `CreateCustomerCubit` / `LineEditorCubit` |

Use **Bloc** only if product later adds live open-invoice refresh mid-dialog, multi-item quick returns, or stream-driven stock updates.

---

## 4. Placement & provisioning

```
lib/ui/features/dashboard/cubit/
  sales_return_quick_cubit.dart   // state + cubit (or split state file if preferred)
```

**Scoped provider** (same pattern as `VoucherPdfActionsWidget`):

```dart
showDialog(
  context: context,
  builder: (dialogContext) => BlocProvider(
    create: (_) => SalesReturnQuickCubit(
      customer: customer,
      salesRepository: sl<SalesRepository>(),
      syncRepository: sl<SyncRepository>(), // or SyncWorker via existing trigger API
    )..loadEligibleItems(),
    child: SalesReturnDialog(
      // customer already in cubit; can drop widget.customer if desired
      onReturnConfirmed: () {
        context.read<DailyStatsCubit>().refresh(); // after Group B; else existing callback
      },
    ),
  ),
);
```

- **Not** registered in `app.dart`  
- Cubit lifetime = dialog lifetime (auto-closed when provider disposed)

---

## 5. State model

```dart
class SalesReturnQuickState extends Equatable {
  /// Items this customer has purchased (from local invoices ∩ catalog).
  final List<Item> eligibleItems;

  final Item? selectedItem;

  /// Invoices containing [selectedItem], sorted date-desc.
  /// Empty when no item selected.
  final List<SalesInvoice> matchingInvoices;

  /// invoiceId → return qty (source of truth for submit).
  /// Controllers are a focus-friendly mirror; see §7.
  final Map<String, int> quantities;

  final bool submitting;
  final String? errorMessage;   // validation or save failure (listener or inline)
  final bool success;           // one-shot; listener pops + callback

  /// Convenience: eligibleItems.isEmpty after load.
  bool get hasNoPurchaseHistory => eligibleItems.isEmpty;

  /// Confirm enabled when item selected, not submitting, and total qty > 0
  /// (form max-qty validators still run in the widget).
  bool get canSubmit =>
      selectedItem != null &&
      !submitting &&
      quantities.values.any((q) => q > 0);

  // copyWith + props: always new Map/List instances (mechanics #2)
}
```

**Initial state:** `eligibleItems: []`, nothing selected, `submitting: false`.

No need for a sealed union unless you prefer `freezed`; plain Equatable + flags matches the rest of the app.

---

## 6. Public API (Cubit methods)

| Method | Behavior |
|--------|----------|
| `loadEligibleItems()` | Called from `create:` or ctor. Read local invoices for `customer.id` → purchased item ids → filter `getItems()`. Emit new `eligibleItems`. Sync only (Hive). |
| `selectItem(Item item)` | Set `selectedItem`. Recompute `matchingInvoices` (customer invoices containing item, sort date-desc). Reset `quantities` to `{}` (or zeros). Clear `errorMessage`. |
| `setQuantity(String invoiceId, int qty)` | Emit new map; clamp/store `qty` (widget validators still enforce max sold qty). Prefer non-negative ints only. |
| `submit()` | See §8. |
| `clearError()` | Optional; clear `errorMessage` after snackbar. |

**Not on cubit:** `TextEditingController`, `FocusNode`, `GlobalKey<FormState>`, `DateFormat`.

---

## 7. Widget responsibilities (mechanics #1–#3)

Remain **StatefulWidget** only if controllers need lifecycle; otherwise Stateless + provider is fine if controllers are owned by a small inner Stateful child.

### Widget-local

- `_formKey`
- `Map<String, TextEditingController> _qtyControllers`
- Optional: recreate controllers when `matchingInvoices` identity changes (item change)

### Reconciliation (item change)

When `BlocListener` / builder sees `selectedItem` / `matchingInvoices` change:

1. Dispose controllers for removed invoice ids  
2. Create controllers for new ids (empty text)  
3. Do **not** put controllers in cubit

### Qty text ↔ state

**Recommended (simpler, matches current dialog):**

- Controllers are primary while editing  
- `onChanged` → `cubit.setQuantity(invoiceId, parsed)` so `canSubmit` stays live  
- On `submit()`, cubit may re-read quantities from state (already updated) **or** accept an explicit `Map<String,int>` argument from the widget after form validate  

**Avoid** writing controller `.text` from cubit on every keystroke (no need; unlike receipt FIFO there is no external recompute pushing into fields).

### Side effects — `BlocListener` only

| State transition | Listener action |
|------------------|-----------------|
| `success == true` | `Navigator.pop`, `showSuccessSnackBar`, `onReturnConfirmed()` |
| `errorMessage != null` (save failure) | `showErrorSnackBar`, optionally `clearError` |
| Validation “no qty” | Either cubit `errorMessage` → snackbar **or** keep pre-submit widget snackbar before calling `submit()` — pick one path and use it consistently |

Do **not** snackbar/pop inside the cubit.

---

## 8. Submit algorithm (preserve behavior + harden)

Port of current `_submit()` with fixes:

```
submit():
  if submitting → return
  if selectedItem == null → return
  if total qty <= 0 → emit errorMessage (or rely on widget gate)
  emit submitting: true, clear errors
  try:
    build List<SalesReturnLineItem> from quantities > 0:
      originalLine = invoice.items.firstWhere(item id match)
      SalesReturnLineItem(
        invoiceLineItem: originalLine,
        returnedQuantity: qty,
        invoiceId: inv.id,
        invoiceNumber: inv.invoiceNumber,
      )
    tempId = 'temp_ret_<ms>'
    creditNoteNumber = 'RET-TEMP-<suffix>'   // keep dialog prefix
    SalesReturn(
      reason: 'Damaged packaging',           // keep hardcoded
      isPendingSync: true,
      ...
    )
    await salesRepository.saveLocalReturn(...)
    await salesRepository.enqueueSyncItem(SyncQueueItem type: 'return', ...)
    syncRepository.triggerSync()             // fire-and-forget (same as today)
    emit success: true, submitting: false
  catch e:
    emit submitting: false, errorMessage: e.toString()
  // isClosed: use emit only if !isClosed (mechanics #4)
```

### Latent bugs fixed

| Bug | Fix |
|-----|-----|
| No try/catch | `failure` path clears `submitting` |
| Double-tap CONFIRM | `if (submitting) return` + disable button when `!canSubmit \|\| submitting` |
| `mounted` after await | Cubit emit-after-close; UI listener only if still mounted (Flutter listener is safe) |

### Explicit non-goals (do not change in this task)

- Stock restore semantics inside `saveLocalReturn` (leave Hive as-is)  
- Unifying `RET-TEMP` vs `CN-TEMP`  
- Making reason user-editable  
- Live Zoho invoice refresh for max qty  
- Multi-item returns in this dialog  

---

## 9. Eligible-items & matching-invoices pure helpers

Extract (same file as cubit or `lib/ui/features/dashboard/cubit/sales_return_quick_queries.dart`) for unit tests:

```dart
List<Item> eligibleReturnItems({
  required List<SalesInvoice> allInvoices,
  required List<Item> catalog,
  required String customerId,
});

List<SalesInvoice> invoicesContainingItem({
  required List<SalesInvoice> allInvoices,
  required String customerId,
  required String itemId,
});
// sort date-desc inside helper or cubit
```

Today both queries re-read Hive on item change; keep that (fresh local data after concurrent invoice) or seed invoices once in `loadEligibleItems` — **prefer re-query on `selectItem`** to match current dialog (invoices re-read every item change).

---

## 10. UI mapping

| UI element | Binding |
|------------|---------|
| Empty purchase history | `state.hasNoPurchaseHistory` → existing warning column |
| Item dropdown | `items: state.eligibleItems`, `value: state.selectedItem`, `onChanged: cubit.selectItem` |
| Invoice cards | `state.matchingInvoices` + max qty from line |
| Qty fields | controllers + validators (`qty > maxQty`) unchanged |
| CANCEL | `Navigator.pop` (no cubit) |
| CONFIRM RETURN | disabled if `!state.canSubmit`; `onPressed` → validate form → `cubit.submit()` |
| Loading on button | optional `CircularProgressIndicator` when `submitting` |

`DropdownButtonFormField.initialValue` / `value`: follow Flutter version in project; after migration prefer controlled `value: state.selectedItem` so cubit is sole source of selection.

---

## 11. Edge cases (complete)

| # | Case | Expected |
|---|------|----------|
| 1 | Customer with no local invoices / no purchased items | `eligibleItems` empty; warning UI; CONFIRM disabled |
| 2 | Customer has invoices but catalog missing item ids | Item omitted from dropdown (intersection) |
| 3 | Select item A then B | Controllers for A disposed; quantities cleared; B’s invoices shown |
| 4 | Select item with no matching invoices (should be rare if eligibility correct) | Empty invoice list; cannot submit |
| 5 | All qty fields empty / zero | `canSubmit` false; if forced submit → error snackbar |
| 6 | Qty > sold qty on one invoice | Form validator blocks submit (widget) |
| 7 | Non-numeric / negative | Digits-only formatter + validator (existing) |
| 8 | Multiple invoices, partial qtys | Only `qty > 0` lines in payload |
| 9 | Double-tap CONFIRM | Second ignored; button disabled while `submitting` |
| 10 | `saveLocalReturn` / enqueue throws | `submitting` false; error snackbar; dialog stays open |
| 11 | Dispose / pop while submit in flight | No emit-after-close crash; parent may still get no callback (OK) |
| 12 | Success | Pop dialog, success snackbar, `onReturnConfirmed` → daily stats refresh |
| 13 | Item line appears twice on one invoice | Preserve `firstWhere` behavior (same as today) |
| 14 | Offline | Local save + queue still succeed if Hive works; sync no-op/fail later |
| 15 | Concurrent: new invoice saved while dialog open | Next `selectItem` re-reads invoices (if we re-query) |
| 16 | Global `SalesReturnBloc` has an in-progress editor | Unaffected (separate cubit instance) |
| 17 | Hardcoded reason / RET-TEMP prefix | Unchanged |
| 18 | `onReturnConfirmed` during rebuild | Only from `BlocListener` on `success` |

---

## 12. Tests

**File:** `test/sales_return_quick_cubit_test.dart`

| Test | Assert |
|------|--------|
| `loadEligibleItems` filters to purchased items only | eligible list ids |
| Empty history | `hasNoPurchaseHistory` |
| `selectItem` builds date-desc invoices + clears quantities | order + empty map |
| `setQuantity` + `canSubmit` | true only when total > 0 |
| `submit` success | `saveLocalReturn` + `enqueueSyncItem` called; `success` true; payload lines correct |
| `submit` with zero qty | no repo calls; error or early return |
| `submit` while already submitting | single repo invocation |
| `submit` throws | `submitting` false, `errorMessage` set |
| Quantities > 0 only included | lines length |
| Emit fresh maps | successive states not identical list/map refs if using Equatable traps |

Use fakes patterned after `test/receipt_bloc_test.dart` (`FakeSalesRepository` / thin fake with invoice + item fixtures).

---

## 13. Implementation tasks (replace vague Task 0.4)

- [ ] **0.4.1** Add pure helpers + unit tests (eligible items / matching invoices).  
- [ ] **0.4.2** Implement `SalesReturnQuickState` + `SalesReturnQuickCubit` (load, select, setQuantity, submit + guards).  
- [ ] **0.4.3** Cubit tests (`bloc_test` / cubit tests).  
- [ ] **0.4.4** Refactor `SalesReturnDialog` UI to provider + listener/builder; remove all `setState`.  
- [ ] **0.4.5** Update `_launchSalesReturnFlow` to wrap `BlocProvider` (and later `DailyStatsCubit.refresh`).  
- [ ] **0.4.6** Manual: empty history, happy path multi-invoice, max-qty validation, double-tap, forced save failure if injectable.  
- [ ] **0.4.7** Confirm editor/list return flows still use only `SalesReturnBloc`.  
- [ ] **0.4.8** Grep: `sales_return_dialog.dart` has zero `setState(`; dashboard quick return path covered.

**Suggested schedule:** implement in **Phase 6** (after Group B so `onReturnConfirmed` can call `DailyStatsCubit`), or any time after Phase 0 if stats still use a callback. Independent of Group I.

**PR slice:** small standalone PR or with Group B (dashboard).

---

## 14. Out of scope / follow-ups (explicit)

| Item | Why deferred |
|------|----------------|
| Migrate `ReturnInvoiceSelectorDialog` to same cubit | No `setState` today; Stateful only for controllers. Share pure helpers only if DRY itch appears. |
| Fold quick return into full editor navigation | Product decision, not state-management. |
| Unify credit-note number prefixes | Product/sync concern. |
| Live invoice balance / prior returns reducing max qty | Not in current dialog; would need domain rules. |

---

## 15. Summary diagram

```
DashboardPage._launchSalesReturnFlow
  └─ BlocProvider(SalesReturnQuickCubit(customer, repos)..loadEligibleItems())
       └─ SalesReturnDialog
            ├─ BlocBuilder  → eligible items / selected / invoices / canSubmit / submitting
            ├─ BlocListener → success → pop + snackbar + onReturnConfirmed
            │               → error   → snackbar
            └─ Widget-local Form + qty TextEditingControllers
                 onChanged → cubit.setQuantity
                 CONFIRM   → form.validate → cubit.submit

SalesReturnBloc (global) ── untouched ── SalesReturnEditorPage / list
```

**Inventory delta for migration plan:** +1 Cubit (`SalesReturnQuickCubit`) → **12 new classes** (5 Bloc, **7** Cubit) + 1 existing-Bloc reuse, and **25** real setState files converted (original 24 + this dialog).
