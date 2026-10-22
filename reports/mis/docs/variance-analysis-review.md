# MIS reports: variance analysis review

Review date: 2026-10-17 (branch `feat/mis-date-range`, commit `f184154`).

Scope: Executive Summary, P&L, Balance Sheet, Trial Balance, Margin, Purchases, Cashflow.

**Summary.** The base is sound: each statement section adds up from its accounts, unmapped accounts
land on their own line instead of disappearing, and GM % is a ratio of sums (never an average of
percentages). What's missing is the variance layer: comparison periods are shown as extra columns
side by side, but nothing measures or explains the change between them.

---

## Fix first

These affect whether the totals can be trusted, so they come before any variance work.

### 1. Statement check rows are never created

The README says each statement ends with a check row (P&L vs TB, Assets vs Capital & Liabilities)
and the command exits with code 1 when one is off. No code creates those rows: `checks()`
(`reports/financials.py:466`) looks for lines of kind `check`, `build_profit_and_loss` and
`build_balance_sheet` never append one, so `checks()` always returns `{}`. An unbalanced P&L or
Balance Sheet passes silently.

Fix: append a `check` line to the P&L (Net Profit − Σ P&L movement in the TB, per column) and to the
BS (Total Assets − Total Capital & Liabilities, per month end). `exporters.py:146` already renders
`check` lines.

### 2. Fallback margin cost restates history

Invoices without `cf_line_cogs_document` are costed at the item's *current* `purchase_rate`
(`reports/invoice_margin.py:330`, `cost_source = "purchase_rate"`). When a purchase rate changes, the
margin of every past period changes too, and any cost variance between periods is fake.

Fix:
- Show the share of net sales costed by `purchase_rate` vs `booked` for each period, so the reader
  knows how much of the margin is estimated.
- Cost fallback lines at the rate in force on the invoice date (e.g. last bill rate on or before the
  date from `purchase_doc_lines`) instead of today's rate.

### 3. Returns are not deducted from Margin

Credit notes / sales returns are not netted, so net sales and the period-to-period change are
overstated. The return rate is itself a variance driver worth showing. Already listed under
"Planned next" in the README; it should come before the variance features below.

---

## Variance features to add

| # | Suggestion | Where |
|---|---|---|
| 4 | **Δ and Δ% columns** next to each comparison period, coloured favourable / unfavourable. | `reports.js` (`renderPivot`, `renderMarginPivot`, `renderTree`, `remapLines`) |
| 5 | **Materiality flags** and a "sort by largest change" option. | `reports.js` |
| 6 | **Same period last year** as a comparison choice. | `date-filter.js` |
| 7 | **Margin bridge** (volume / price / mix / unit cost / returns). | new `/api/margin-bridge` + waterfall |
| 8 | **Ledger COGS vs line-cost COGS** tie-out line. | Executive Summary |
| 9 | **Budget vs actual**. | `db.py` + statements |
| 10 | **Fixed / variable tag** per category, for a flexed budget. | `category_master.py` |
| 11 | **Van-sales KPIs** in the Executive Summary. | sales tables |
| 12 | **Balance Sheet movement column** and working-capital days. | `build_balance_sheet` |
| 13 | **Cashflow forecast accuracy**. | cashflow |
| 14 | **Variance comments** per line and period. | new DB table |

### 4. Δ and Δ% columns

- For each comparison column, add the absolute change and the % change against the main range
  (or against the immediately earlier period — pick one convention and label it).
- Each line needs a "good direction": revenue, income, margin and profit up = favourable; COGS and
  expenses up = unfavourable. The P&L sign flip already knows which lines are income
  (`CREDIT_POSITIVE_PL`), so the direction can come from the same place.
- Margin %, CM %, EBITDA %, Net Profit % and GM % in the Margin tab change in **percentage points**
  (pp), not % change. 32% → 30% is −2.0 pp, not −6.3%.
- Avoid a % change when the base is zero or the sign flips (show "n/m").

### 5. Materiality flags

Flag a row when the change exceeds an amount threshold *or* a % threshold. Suggested starting points:

| Comparison | % threshold | Amount threshold |
|---|---|---|
| Actual vs budget | 10% | ~0.5–1% of period revenue |
| Actual vs prior period | 15% | same |
| Week on week / month on month | 20% | same |

Make both thresholds configurable (env or a settings row). Add "sort by largest absolute change"
next to the existing Largest-first order, so the biggest movers come first.

### 6. Same period last year

Comparison periods today step back by the range's own length (1–17 Oct ↔ 1–17 Sep). Add a
"same period last year" option (1–17 Oct 2026 ↔ 1–17 Oct 2025) to remove seasonality. Only useful
once a year of data is loaded; hide or grey it out when coverage doesn't reach back.

### 7. Margin bridge (price / volume / mix)

`sales_lines` already holds item, base quantity, net sales and cost per line, so this needs no Zoho
calls. For prior period P and current period C, per item *i*:

```
Volume effect  = (Σ qty_C − Σ qty_P) × prior average GM per unit
Mix effect     = Σ_i (qty_C,i − qty_C × share_P,i) × (GM per unit_P,i − prior average GM per unit)
Price effect   = Σ_i qty_C,i × (price_C,i − price_P,i)
Unit cost      = −Σ_i qty_C,i × (cost_C,i − cost_P,i)
Returns        = −(returns_C − returns_P) margin impact   (after #3)

Prior GM + volume + mix + price + unit cost + returns = Current GM
```

- New items (no prior sales) and dropped items go into their own "new / discontinued" bar rather
  than distorting price.
- Same bridge by customer, salesperson or van (mix becomes customer / route mix).
- Show as a waterfall with a reconciliation table; the bars must add up to the change in GM exactly.
- The unit-cost bar is only meaningful once #2 is fixed.

### 8. Ledger COGS vs line-cost COGS

The P&L uses ledger COGS; the Margin tab uses invoice line cost. T2.4 in
`date-range-reports-tasks.md` lists the reconciliation line as optional — make it required. Show
ledger COGS − Σ line cost for the same range on the Executive Summary; the gap (stock adjustments,
returns, write-offs, fallback-costed lines) is itself a variance to explain.

### 9. Budget vs actual

Add a `budgets` table: `(version, category, sub_category NULL, month, amount)`, filled by CSV
upload or a simple grid. The P&L and Executive Summary can then show Budget / Actual / Variance /
Variance % columns, with the same favourable/unfavourable rules as #4. Keep a `version` column so a
revised forecast can sit next to the original budget (actual vs budget and actual vs forecast).

### 10. Fixed / variable tag per category

Add a `behaviour` column to the Category Master (`fixed`, `variable`, `semi`), with defaults by
category (COGS and Direct Expenses variable; rent, salaries fixed). This allows:

- splitting operating cost changes into volume-driven vs fixed;
- a flexed budget (variable costs scaled to actual volume), which separates "spent more because we
  sold more" from "spent more per unit".

### 11. Van-sales KPIs

Add to the Executive Summary, per column: number of invoices, active customers, average invoice
value, sales per van per selling day, lines per invoice. Revenue change then decomposes into
customers × invoices per customer × average invoice value, which is the natural driver tree for
van sales.

### 12. Balance Sheet movement and working-capital days

- A movement column (closing − opening, or month on month) per BS line.
- Days sales outstanding (trade receivables ÷ revenue × days), days of inventory (closing stock ÷
  COGS × days), days payables (trade payables ÷ COGS × days), and the cash conversion cycle.
  These explain working-capital swings that a raw balance doesn't.

### 13. Cashflow forecast accuracy

`cashflow_runs` already stores each forecast with its as-of date. Once enough time has passed,
compare each forecast with actual bank movement over the same days and report:

```
Accuracy = 1 − |Actual − Forecast| / |Actual|
MAPE     = average of |Actual − Forecast| / |Actual| across forecasts
```

Consistent over- or under-forecasting points at wrong payment-term assumptions (customers paying
later than their due date, for example).

### 14. Variance comments

A `variance_notes` table keyed by `(report, line, from_date, to_date)` with driver, outlook
(one-time / continuing / improving / deteriorating), action (none / monitor / investigate / update
forecast) and author. Show the note on the row and include it in the Excel export. Good notes name
the driver and its amount ("Price −12k: 4% discount on SKU X to customer Y"), not "higher than
expected".

---

## Suggested order

| Step | Items | Why |
|---|---|---|
| 1 | #1, #2, #3 | Totals must be trustworthy before changes in them are explained. #1 is a small change in `financials.py`. |
| 2 | #4, #5, #6 | UI-only quick wins on data that already exists. |
| 3 | #7, #8 | Highest-value analysis; no new data needed. |
| 4 | #9–#14 | Need a budget, new tags or time to accumulate forecast history. |

Status: review only — none of these are implemented yet.
