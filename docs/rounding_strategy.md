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
totals, etc.) is rounded to 2 decimal places via `roundMoney()`
(`lib/domain/utils/money_math.dart`) at the point it is computed — including
before being summed by a caller (`fold`). This exists purely to stop binary
floating-point drift from compounding across many line items (e.g. raw
`double` addition of `0.1` thirty times yields `3.0000000000000004`, not
`3.0`). It is not a business-rule rounding step.

## Document-level "Round Off"

`SalesInvoice.total` / `SalesOrder.total` round the summed `rawTotal` to the
**nearest 0.50** (`roundToNearestHalf(rawTotal)`), and expose the
adjustment as `roundOff = total - rawTotal`. This implements 50-fils / 0.50 step
rounding (e.g. `.10` -> `.00`, `.40` -> `.50`, `.90` -> `1.00`). `roundOff`
is surfaced to the user in the invoice/order editors
(`sales_invoice_editor_page.dart`, `sales_order_editor_page.dart`), PDF
templates, and thermal ticket printing whenever it is nonzero.

## Test coverage

`test/domain_totals_test.dart` covers:
- Line-item and document-level subtotal/tax/discount/total calculations.
- Document-level round-off to the nearest whole unit.
- `SalesReturnLineItem` tax + prorated-discount calculation (full and
  partial return quantities).
- The floating-point drift guard (`roundMoney`) across many summed lines.

`test/stock_rules_test.dart` covers the related `deductStock` invariant
(not a rounding concern, but lives in the same `domain/utils` layer).
