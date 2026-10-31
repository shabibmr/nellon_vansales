# Transaction sync — review fixes: task list

Plan: `review-fixes-plan.md`. Review: `transaction-sync-review.md`. Status as of 21 Oct 2026: all tasks R1–R12 done. No Zoho call was made. 111 tests passing.

Status markers: `[ ]` not started · `[~]` in progress · `[x]` done · `[!]` blocked (reason on the line).

Do these in order. Each fix lands with its test. Run from `reports/mis`: `./.venv/bin/python -m unittest tests.test_zoho_sync tests.test_seed_extractions`.

## R1. Store `update` (review bug 3)

- [x] Add `update(table, key, values)` to the `Store` protocol in `store.py`.
- [x] `MemoryStore.update`: change the named columns of the existing row; raise when no row matches.
- [x] `DbStore.update`: `UPDATE … SET … WHERE key`; same column validation as `upsert`; raise when no row matches.
- [x] Switch the detail patch (`pipeline.py:348`) to `store.update`.
- [x] Switch the COGS writes (`cogs.py:111-121`: `sales_invoices`, `sales_lines`, `debit_notes`) to `store.update`.
- [x] Note in the `upsert` docstring that `update_cols` is for full rows, not partial ones.
- [x] Tests: `MemoryStore.update` changes only the named columns; a missing row raises; `DbStore` builds the expected `UPDATE` SQL with a stub cursor (no database); a mapper key that is not a column raises.

## R2. Watermark encoding (review bug 1)

- [x] `pipeline.py:215,221`: pass the raw watermark in the params dict.
- [x] Remove `encode_watermark`, or keep it only if a caller outside `requests` needs it; fix the docstring either way.
- [x] Replace the assertion at `tests/test_zoho_sync.py:870` with a `requests`-level test: the prepared URL carries `%2B` once (never `%252B`).
- [x] Correct the "Encode `+` as `%2B`" wording in `transaction-sync-plan.md` and `transaction-sync-tasks.md` (tasks 3 and 9) to "pass the raw text; `requests` encodes it".

## R3. Watermark seed and ordering (review bug 2)

- [x] Add pure `to_zoho_watermark(dt)` in `watermark.py`: `YYYY-MM-DDTHH:MM:SS+0400` (Asia/Dubai).
- [x] `watermark.seed` uses it on the value from `store.max_value(header_table, 'last_modified_time')`.
- [x] `highest` compares parsed datetimes, not strings.
- [x] Tests: conversion at midnight and with single-digit fields; seed output has `T` and the offset; `highest` orders mixed offsets correctly.

## R4. No partial documents (review: should fix)

- [x] In `_store_document`, build the union of list-row ids, detail ids and doc refs first; run every `ensure` and doc-ref load; only then upsert header, patch and lines.
- [x] Tests: a line whose item returns 404 leaves no header and no lines, and the document is in `sync_pending`; a debit note whose reference invoice fails stores nothing.

## R5. Retry and doc-ref loads keep list-only fields (review: should fix)

- [x] `_sync_by_id` (`pipeline.py:301,303`) stops passing the detail as `list_row`; write detail-derived columns only, through `store.update`.
- [x] Test: a retried document keeps the list-only fields it had; none become `0` or an empty string.

## R6. One bad list does not stop the run (review: should fix)

- [x] `sync_dataset` catches any exception from the list loop, records `error` in the dataset summary, leaves that watermark unchanged.
- [x] `run_all` continues to the next dataset, writes the summary, and exits non-zero if any dataset errored. `BudgetExceeded` still stops the run.
- [x] Test: an HTTP failure on the second dataset's list leaves the first dataset's watermark moved, the second's unchanged, and the third dataset still runs.

## R7. 02:00 check uses start time and Asia/Dubai (review: should fix)

- [x] `Run` records `started_at` (injectable, timezone-aware, Asia/Dubai); the default clock becomes timezone-aware.
- [x] `run_cost_of_sales` (`pipeline.py:70-72`) reads the hour from `run.started_at`.
- [x] Update any test that injects a naive datetime.
- [x] Tests: a run that starts at 01:59 and ends after 03:00 still does the trailing window and the bill D-to-today re-pulls; a run that starts at 03:01 does not.

## R8. COGS repeatable and bounded (review: should fix)

- [x] `cogs.apply_cogs` weights each line by its own cost from stored `quantity`, `purchase_price` and `conversion_rate`; no fallback to the stored `cogs`.
- [x] Posted invoice whose postings are gone: header and lines take the sum of the lines' own cost (same source), not the stale spread.
- [x] Add a filtered read to `Store` (`iter_where`, or equivalent) with the filter pushed into SQL for `DbStore`.
- [x] Replace the whole-table reads (`cogs.py:84-88`, `pipeline.py:122`) with keyed reads: invoices by id or date range, lines by invoice id, `gl_journals` by account and date range.
- [x] Tests: a second COGS pass over the same invoice gives identical rows; postings that disappear fall back to the lines' own cost; keyed reads return the same rows as the old whole-table reads (same-rows test).

## R9. Real-database check (review: test gap)

- [x] Opt-in `DbStore` integration test (environment variable, skipped otherwise) on MariaDB 10.11 in default `STRICT_TRANS_TABLES`, throwaway schema.
- [x] Cover: `upsert` of a full row, `update` of a partial row on a table with NOT NULL columns without defaults, `replace_lines`, `replace_range`, keyed reads from R8.
- [x] Run it once on a real server and record the result here: passed on MariaDB 10.11.14 (Ubuntu 24.04), `DbStoreMariaDbIntegrationTests.test_strict_mode_upsert_update_replace_lines_and_keyed_reads` OK in 0.043s.

## R10. Minor clean-ups (review: minor)

- [x] `_load_detail` (`pipeline.py:358-365`): remove the duplicate cache-currency check.

## R11. Finish task 10 (`transaction-sync-tasks.md`)

Tick each bullet in that file when its test lands.

Core:

- [x] `--replay` makes no network call and writes the same rows; add the empty-database case, where master fetches are served from the cache.

Masters and specs:

- [x] Every `DocSpec` maps its fixture through its three mappers alone; include the sales-order header (`salesorder_id`, `salesorder_number`).

Pipeline:

- [x] Every list sends the stored watermark as raw text (prepared URL check from R2). A bill boundary row with an equal timestamp updates nothing.
- [x] A run stopped by `--max-calls` partway through a list leaves that watermark unchanged. A finished list moves it even when one document is pending.
- [x] No watermark: the dataset is refused and nothing is listed.
- [x] A debit-note id is not inserted into `sales_invoices`, from the list or from a detail `type`.
- [x] A missing item, customer, vendor, salesperson, location, or account id is ensured before the insert. The stored row keeps the id.
- [x] A blank optional id is stored as NULL. A blank customer or vendor id stores nothing.
- [x] A master that fails or 404s stores nothing, records the doc in `sync_pending`, and appears in the summary on the third attempt.
- [x] A debit note whose reference invoice is not stored loads that invoice first.
- [x] Lines missing from a new detail payload are deleted.
- [x] Vendor-payment children come from `bills[]`, keyed by `bill_payment_id`, and only after that `bill_id` is on `purchase_docs`.

Cost of Sales:

- [x] A changed bill dated D re-pulls Cost of Sales from D to today on the 02:00 run; pass `claimed["bills"]` through `run_cost_of_sales` with an injected clock.
- [x] A vendor-credit posting on Cost of Sales is stored in `gl_journals` and changes no invoice or debit-note COGS.

## R12. Close-out

- [x] Full suite passes (77 existing plus new -> 111 passing).
- [x] Update `transaction-sync-tasks.md`: tick task 10 and refresh the status line; correct the watermark wording noted in R2.
- [x] Update `transaction-sync-review.md` task 9 status table: "Raw watermark" met; "Required and optional ids" met.
- [x] Remaining out of scope (unchanged): first customer debit note follow-up under task 7.
