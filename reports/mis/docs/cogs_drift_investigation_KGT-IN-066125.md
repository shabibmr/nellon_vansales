# Invoice KGT-IN-066125 — investigation

invoice_id `3331482000184106447` · item_id `3331482000182185068` ("J ONE SPECIAL MARRIAGE GHEE RICE 18 KG PRO") · qty 3

## Timeline (from Zoho's own invoice history, `GET /invoices/{id}/comments`)

| Date | Time | Who | Event |
|---|---|---|---|
| 2026-09-01 | 09:23 | Mubashir | Invoice created, AED 362.00 |
| 2026-09-01 | 10:20 | Mubashir | Marked as sent |
| 2026-09-02 | 16:00 | Mubashir | Payment of AED 362.00 received |
| 2026-09-09 | 12:51 | Mubashir | Invoice updated |
| 2026-10-13 | 05:24 | Zoho Books (system) | Workflow "COGS UPDATE" not executed — triggered instead by custom function `calculatecogs` |
| 2026-10-13 | 05:24 | SHIBLI | Invoice updated |
| 2026-10-14 | 10:55 | Zoho Books (system) | Custom function `calculatecogs` executed by workflow "COGS UPDATE" |
| 2026-10-14 | 10:55 | Zoho Books (system) | Workflow "COGS UPDATE" not executed — triggered instead by custom function `calculatecogs` |
| 2026-10-14 | 10:55 | SHIBLI | Invoice updated (= current `last_modified_time`) |

Full raw response: `reports/mis/output/cache/invoice_comments/3331482000184106447.json`.

## Cost drift

- Original journal posting (`cos_2026-09.json:35244`, `transaction_id 3331482000184106447`, dated 2026-09-01): **COGS debit = AED 297.86**. This matches the invoice's "Actual COGS" custom field exactly, and matches `inv_cogs_compare.cogs_from_journal`.
- Current invoice line item `purchase_price = 111.786049` → line cost = qty 3 × 111.786049 = **AED 335.36**.
- Diff: **AED +37.50** (confirmed via DB query joining `invoice_line_items` and `cost_of_sales_nellon`).
- This invoice is one of the 276 rows in `inv_cogs_compare` where `calc_by = 'none'` — none of the pp/pr/cr_pr reconstructions match the journal, because the line's `purchase_price` was rewritten *after* the journal was posted.

## What did NOT happen

- No purchase bill for this item was created or modified in the relevant window: `GET /bills?item_id=3331482000182185068&last_modified_time=2026-10-14T10:55:29+0400` returned **0 bills**. A late/backdated bill correction is ruled out as the trigger.
- The original ledger journal entry (297.86) was not reversed or adjusted — only the invoice's own cached cost fields (`purchase_price`, "Actual COGS" custom field) changed.

## Root cause (revised)

**Correction:** `calculatecogs` only writes to the invoice's `custom_fields` (the "Actual COGS" field) — it does not touch `purchase_price`/`cost_amount` on the line item. The system comments for `calculatecogs` are separate from the plain **"Invoice updated"** comments in the same timeline, which are the actual edits that changed the line item.

The item is a **combo/assembly** (`is_combo_product: true`, BOM = NELLON JEERAKASHALA RICE 18 KG NW + NON WOVEN BAG + SERVICE CHARGE), so its cost is the sum of 3 component costs, not a direct purchase. Checked for a triggering event across the whole BOM:

- Live-tested `GET /items/{id}/comments` and `/items/{id}/history` → both **404 Invalid URL Passed**. Zoho Books has no item-level audit/history API, so a valuation-method change cannot be confirmed or ruled out directly via API for any item in this chain.
- `GET /bills?item_id=...&last_modified_time=2026-10-01` returned **0 bills** for the combo item itself, the rice component, and the bag component — no purchase-bill activity anywhere in the BOM near Oct 13/14.
- The rice component (`item_id 3331482000132110075`) has `stock_on_hand = -4944` (deeply, chronically negative) — a red flag for WAC instability, but its own `last_modified_time` is 2026-09-01, not near the edit window.
- All three items currently show `inventory_valuation_method: wac`.

With no bill or item-master change found at any point in the BOM near the edit timestamps, the two **"Invoice updated"** events on 2026-10-13 05:24 and 2026-10-14 10:55 — both attributed to user **SHIBLI** — are the most direct candidate for what actually rewrote `purchase_price` from ~99.29/unit to 111.786049/unit. Whether this was a manual correction or a scripted/batch job run under that account is not determinable from the API; it needs to be confirmed internally (SHIBLI is the Zoho OAuth token owner on this org per project notes, so a script run under that identity is plausible).

Net effect either way: the invoice's live `purchase_price` (335.36 for the line) no longer matches what was actually posted to the books as COGS (297.86) for September, and the original P&L journal entry was not reversed or adjusted — only the invoice object's own cost fields moved.

## Cross-invoice analysis (2026-10-19)

Source: all 1,645 cached Sept invoices (`output/cache/invoices/`, fetched 2026-10-18) vs `cos_2026-09.json`. Line cost = Σ qty × `purchase_price`.

**SHIBLI edit is not the differentiator.** All 1,645 Sept invoices have `last_modified_by = SHIBLI` on 2026-10-13/14 — drifted (253) and clean (1,386) alike. It was a batch re-save (the "COGS UPDATE" run), not a targeted correction.

**Drift classes (253 invoices, |line − journal| > 0.05):**

| Class | Count | Cause |
|---|---|---|
| Rounding | ~39 (<0.5 AED) | `purchase_price` stored at 2dp (103.61); journal uses full precision (103.6113) |
| Non-stock line | 29 | "excise Tax" line has `purchase_price = 1` but no inventory journal (excluded by `cost_source` filter in the DB query) |
| Material | 185 (≥0.5 AED, excl. excise) | see below |

**Material drift = contiguous time blocks on specific days, per item.** Ordering same-day invoices by `created_time`:

- JEERAKASHALA 18KG (B), 09-19: every invoice to 14:58 booked **103.61**, every invoice from 14:59 booked **96.45**; current `purchase_price` = 96.45 for the whole day.
- Same item, 09-21: booked 96.45 until 10:38, 103.61 from 11:14; `purchase_price` = 103.61 all day.
- Same item, 09-26: booked 103.61, then **89.62** for 11:37–13:28 (14 invoices across KGT/SMR/YNS), then 103.61 again; `purchase_price` = 103.61 all day.
- BASMATHI XXXL 35KG, 09-16: all invoices booked 156.86 (prior rate); `purchase_price` = 160.27. Bill `ARGT/LOC/2026/508` is **dated 09-16 but created 09-19** (backdated) → journal was posted before the bill existed.
- J ONE GHEE RICE (this invoice), 09-01: all 3 invoices that day booked ~99.29/unit; `purchase_price` = 111.79.

Pattern: the **journal** reflects the cost at the moment of posting (intra-day sequence); the **current `purchase_price`** is one value per item per date. Invoices posted before a same-day or backdated cost change carry the gap.

**Item facts found:**

- All three boundary items are combo/assembly products. 164/185 material-drift invoices contain a combo line vs 1,009/1,454 clean ones (89% vs 69%).
- JEERAKASHALA 18KG (B) is **`inventory_valuation_method: fifo`** (`output/cache/compositeitems/3331482000002275246.json`); J ONE is `wac`. So valuation methods differ across items. FIFO lot consumption matches the block shape (a lot at 89.62 consumed 11:37–13:28 on 09-26).
- For Jeerakashala 09-19..09-26 (`output/cache/wac_events/`): 0 bills, 0 inventory adjustments, 0 vendor credits; 1 credit note (KGT-CN-004719, 09-23 11:13, restocks returned goods); 20 transfer orders (all 08:00–10:35). None land on the 14:58/14:59 or 11:37/13:29 edges.
- `GET /items` (list) does not return `inventory_valuation_method`; only item detail does. No item audit API → a FIFO↔WAC change cannot be dated via API.

## `none_single_line_items` — item detail (11 calls, 2026-10-19)

Raw: `output/cache/items/{item_id}.json`.

| Item | Valuation | Combo | Created | Stock now | Sept drift invoices |
|---|---|---|---|---|---|
| JEERAKASHALA 18KG (B) | fifo | assembly | 2022-11-28 | **-931** | 20 |
| BASMATHI XXXL 35KG PRO | **wac** | assembly | 2026-08-07 | 537 | 2 |
| J ONE GHEE RICE 18KG PRO | **wac** | assembly | 2026-08-07 | 92 | 1 |
| ORGANIKA BASMATI 5KG | **wac** | assembly | 2025-11-26 | 4823 | 1 (-4,517.40) |
| CHILLI CRUSHED 1KG | fifo | assembly | 2022-12-15 | 6 | 1 |
| GREEN MASOOR 800GM | fifo | assembly | 2022-08-19 | 121 | 1 |
| SOYA WADI 250GM | fifo | assembly | 2022-08-19 | **-42** | 1 |
| CASSIA WHOLE 500GM | fifo | assembly | 2022-08-18 | 53 | 1 |
| CASHEW NUT 100GM | fifo | assembly | 2022-08-18 | 200 | 0 (rounding only) |
| COCONUT POWDER | fifo | no | 2022-08-18 | **-16.4** | 1 (sold in 7Kg Bag, base kg) |
| POPCORN SEED | fifo | no | 2022-08-18 | 21 | 1 (sold in 20Kg Bag, base kg) |

- Valuation method splits by creation date: all 2022 items = FIFO; items created 2025-11 and 2026-08 = WAC. Consistent with the org default changing between those dates (not confirmable — no audit API).
- Drift occurs under **both** FIFO and WAC, so the method alone is not the cause; the common factor remains intra-day posting time vs one `purchase_price` per item-date.
- 3 of 11 items are currently negative stock.

## Bills and bundles on boundary dates (2026-10-19)

Bills: `bills` / `bill_line_items` (nellon_mis_dev, via `fetch_bills.py`). Bundles: `GET /bundles?date_start=2026-09-01&date_end=2026-09-30` (1 call, 190 rows) → `output/cache/bundles/_list_2026-09_p1.json`.

**189 of 190 Sept bundles (assembly builds) are backdated** — entered 1–17 days after their document date (mostly 1–3 days), 187 by Jithesh, AED 964,277 of stock-in. Bills are backdated too (e.g. ARGT/LOC/2026/508).

Bundle/bill unit cost vs the drifted line's current `purchase_price`:

| Item | Boundary | Stock-in document (date ← entered) | Unit cost | Line pp | Journal booked |
|---|---|---|---|---|---|
| ORGANIKA BASMATI 5KG | 09-30 | BUN-07938/07941 (09-29/09-30 ← 10-01) | 15.6768 | 15.68 | 16.15 |
| CHILLI CRUSHED 1KG | 09-22 | BUN-07885 (09-22 ← 09-24) | 18.0172 | 18.02 | 17.29 |
| GREEN MASOOR 800GM | 09-11 | BUN-07822 (09-11 ← 09-16) | 2.8872 | 2.878 | 3.04 |
| BASMATHI XXXL | 09-16 | bill ARGT/LOC/2026/508 (09-16 ← 09-19) | 160.50 | 160.27 | 156.86 |
| J ONE GHEE RICE | 09-01 | BUN-07776 (09-01 ← 09-08) | 114.5772 | 111.79 | 99.29 |
| JEERAKASHALA (B) | 09-19 / 09-21 | BUN-07890 (09-18 ← 09-25) / BUN-07886, 07891 (09-17, 09-22 ← 09-24/25) | 96.451 / 103.6118 | 96.45 / 103.61 | 103.61 / 96.45 |

J ONE (WAC): 300 @ 114.58 blended with ~67 units at the prior 99.29 gives 111.79 — consistent with the line pp.

**Conclusion:** the journal is posted at invoice time with the cost known then and is not re-posted; the line `purchase_price` is later recomputed with backdated stock-in documents (bundles, bills) placed at their document date. Backdated bundles/bills are the cause for the items above.

**Not explained yet:** SOYA WADI (09-01, no bundle that day), CASSIA (09-09, no bundle that day), JEERAKASHALA 09-26 block at 89.62 (no bundle/bill at that cost), POPCORN SEED and COCONUT POWDER line pp (UOM-sold items; neither bill rate matches).

## Open questions

1. Which items are FIFO vs WAC, and was any switched? (needs 1 detail call per item; 293 distinct items in material-drift invoices)
2. What created the 89.62 lot consumed on 09-26 (credit note KGT-CN-004719 restock is the only candidate found) and what ended the 103.61 run at 14:58 on 09-19 (BOM components JEERAKASHALA RICE `3331482000002184139`, NW BAG `3331482000029351321` — assembly builds/bundles not yet checked).
