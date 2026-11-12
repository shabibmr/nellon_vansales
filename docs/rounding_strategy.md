# Money Rounding Strategy

This documents how `van_sales` computes and rounds monetary values across
invoices, orders, returns, receipts, and expenses, and what still needs
verification against a live Zoho Books organization.

## Calculation order (per line item)

For `InvoiceLineItem` / `OrderLineItem`:

1. `subTotal = rate * quantity`
2. `taxAmount = subTotal * (taxPercentage / 100)` — tax is computed on the
   **full pre-discount subtotal**.
3. `total = subTotal + taxAmount - discount` — the line discount is applied
   **after** tax, i.e. it reduces the final total but does not reduce the
   taxable base.

For `SalesReturnLineItem` (see `lib/domain/models/sales_return.dart`), the
same order is mirrored against the *returned* quantity, with the original
line's discount **prorated** to the quantity being returned:

```
subTotal        = invoiceLineItem.rate * returnedQuantity
taxAmount       = subTotal * (invoiceLineItem.taxPercentage / 100)
discountAmount  = (invoiceLineItem.discount / invoiceLineItem.quantity) * returnedQuantity
total           = subTotal + taxAmount - discountAmount
```

So returning 2 of 10 originally-invoiced units credits back 2/10 of that
line's discount, not the full line discount.

**Open question — needs verification against a live org:** Zoho Books
supports both "discount before tax" and "discount after tax" modes
depending on the organization's tax settings. This codebase always computes
tax on the pre-discount subtotal (discount-after-tax). If a given Zoho
organization is configured for discount-before-tax, computed tax/total here
will not match what Zoho computes server-side for the same line. This
should be confirmed against a real sandbox/production org before relying on
penny-perfect reconciliation; no live Zoho environment was available in
this pass to verify it directly.

## Per-value rounding (drift guard)

Every money-bearing getter (subtotal, tax, discount, allocations, expense
totals, etc.) is rounded via `roundMoney()` (`lib/domain/utils/money_math.dart`)
to the active `MoneyScale` (Zoho `price_precision`, else ISO-4217 minor units
for the currency code, else 2) at the point it is computed — including before
being summed by a caller (`fold`). This exists purely to stop binary
floating-point drift from compounding across many line items (e.g. raw
`double` addition of `0.1` thirty times yields `3.0000000000000004`, not
`3.0`). It is not a cash-rounding step.

## Document-level "Round Off"

Zoho applies the org's transaction rounding to API-created invoices (e.g. the
UAE org rounds to the nearest 0.50; verified with a draft invoice, commit
`bf2eb49`). The app mirrors it so printed totals match what Zoho books.

- `SalesInvoice.total` / `SalesOrder.total` = `roundTotal(rawTotal)`, which
  rounds to `MoneyScale.totalStep` (0 = no cash rounding, only `roundMoney`).
- `roundOff = total - rawTotal`; editors, PDFs and thermal tickets show the
  row when it is nonzero.
- The step is `Organization.totalRoundingStep`, cached in Hive. Zoho's
  organization API has no rounding field, so the organization master sync
  detects it (`detectTotalRoundingStep`): one `GET /invoices` page (latest 50,
  void skipped); the largest of 1 / 0.5 / 0.25 / 0.1 / 0.05 that every
  non-zero total is a multiple of, else 0. With fewer than 10 totals, or if
  the call fails, the cached step is kept.
- Limitation: an org with no Zoho rounding whose prices all happen to sit on
  a step (e.g. every total a multiple of 0.05) is detected as that step. The
  local total then differs from Zoho only when a document's raw total is off
  the step. A per-tenant override is planned with the multi-tenant config.
- Local `round_off` is never sent to Zoho (`adjustment` is rejected on VAT
  orgs, error 73006).

## Test coverage

`test/domain_totals_test.dart` covers:
- Line-item and document-level subtotal/tax/discount/total calculations.
- Document totals rounding to the org step, with the round-off row.
- `SalesReturnLineItem` tax + prorated-discount calculation (full and
  partial return quantities).
- The floating-point drift guard (`roundMoney`) across many summed lines.

`test/money_math_test.dart` covers `roundTotal` for steps 0 / 0.5 / 1 and the
step detector (0.5, 1, mixed, KWD 3-decimal, too few samples).

`test/stock_rules_test.dart` covers the related `deductStock` invariant
(not a rounding concern, but lives in the same `domain/utils` layer).
