# Transaction sync — code review (tasks 0–8 + task 9 in progress)

Reviewed 21 Oct 2026 against `transaction-sync-plan.md` and `transaction-sync-tasks.md`. Scope: all of `reports/mis/zoho_sync/` plus the uncommitted diff to `mapping.py` and `pipeline.py`. No Zoho calls. No repo files changed. Bugs 1 and 3 were checked by experiment (details below).

Test run: `./.venv/bin/python -m unittest tests.test_zoho_sync tests.test_seed_extractions` from `reports/mis` — 77 tests, all pass. None of them calls `sync_dataset` or `run_all` with a bill or an invoice, and `DbStore` is tested only for column validation, never SQL.

## Blocking bugs

### 1. The watermark is double-encoded

- `watermark.encode_watermark` turns `+` into `%2B`. `pipeline.py:215` calls it and `:221` puts the result in the params dict.
- `ZohoClient.get` passes the dict to `requests` (`session.get(url, params=params)`), which encodes it again.
- Checked with `requests`: `…51%2B0400` is sent as `%252B0400`; a raw `+` is sent as `%2B`. Zoho would receive a literal `%2B0400`.
- Fix: pass the raw watermark and let `requests` encode it.
- `tests/test_zoho_sync.py:870` asserts the pre-encoded value, so it locks the bug in. Add a test at `requests` level that checks the prepared URL.

### 2. The seed produces an unusable first watermark

- `watermark.seed` uses `store.max_value(header_table, 'last_modified_time')`. That column is `DATETIME` (`reports/db.py:65`), and `seed_common.parse_dt` cuts the value to 19 characters.
- The seeded watermark is `2026-10-21 14:02:51`, with no `T` and no offset. The plan says to keep the raw Zoho text with its offset, and the plan's own seed step contradicts that.
- Fix: define a conversion (add `T` and the Asia/Dubai offset) and test it.

### 3. Partial-column upserts fail under strict SQL mode

- `DbStore.upsert(update_cols=…)` writes only the key and the named columns. The affected writes:
  - the detail patch at `pipeline.py:348`;
  - the COGS writes at `cogs.py:111-121` (`sales_invoices`, `sales_lines`, `debit_notes`).
- Several NOT NULL columns have no default, for example `sales_invoices.date` and `sales_lines.invoice_id` and `.date`.
- Checked on MariaDB 10.11 with its default `STRICT_TRANS_TABLES`: `INSERT … ON DUPLICATE KEY UPDATE` that omits a NOT NULL column fails with `1364 Field 'd' doesn't have a default value`, even when the row exists. `seed_common.connect()` does not relax `sql_mode`.
- Effect: every document's detail step and every COGS write fails, and the documents pile up in `sync_pending`. `MemoryStore` hides it.
- Fix: patches and COGS need a real `UPDATE … WHERE key`, for example a `Store.update` method on `MemoryStore` and `DbStore`.

## Should fix

- **Partial documents are stored.** `_store_document` upserts the list-row header (`pipeline.py:332`) before it ensures the detail ids and doc refs (`:335-336`). If a line's item returns 404, the header stays with old totals or `net_sales = 0`, and the document goes to pending. The plan says to store nothing. Ensure the union of list ids and detail ids first.
- **COGS is not repeatable.** `cogs.apply_cogs` weights by `ln.get("baseline_cogs", ln.get("cogs"))`. Stored lines have no `baseline_cogs`, so on the nightly trailing-window re-run the weights are the previous spread, not each line's own cost. If postings later disappear, the stale spread is kept. Recompute own cost from stored `quantity`, `purchase_price` and `conversion_rate`.
- **The 02:00 check uses the wrong time and zone.** `run_cost_of_sales` reads the hour from `run.now()` at the end of the run (`pipeline.py:70-72`). `Run.clock` is a naive `datetime.now`. A paced run that crosses 03:00 silently skips the trailing window and the bill D-to-today re-pulls. Take the hour from the run's start time, in Asia/Dubai.
- **One bad list stops the run.** `sync_dataset` catches only `BudgetExceeded`. An HTTP failure after retries in one list aborts `run_all`: no summary, no later datasets. Catch per dataset and record the error.
- **Retry and doc-ref loads can overwrite list-only fields.** `_sync_by_id` (`pipeline.py:301,303`) passes the detail as `list_row`. Any list field missing from the detail overwrites the stored value with `0` or an empty string.
- **The COGS pass loads whole tables.** It reads all of `sales_invoices`, `sales_lines` and `gl_journals` on every run (`cogs.py:84-88`, `pipeline.py:122`). The `iter_table` docstring says small tables only.
- **Minor.**
  - `_load_detail` checks cache currency twice (`pipeline.py:358-365`).
  - `highest` is a string comparison, which is only correct while every timestamp has the same offset.

## Task 9 status

| Rule | Status |
|---|---|
| Debit-note-first order, skip rule, `filter_by`, detail `type` reroute | Met |
| Raw watermark with `%2B` | Met |
| Partial list leaves the watermark; failed document does not hold it back | Met |
| Required and optional ids | Met |
| Doc refs | Met |
| Header from the list row only; `cogs` written only by the COGS pass | Met |
| Draft and void get 0 | Met |
| Failed pull keeps `cogs` and `cogs_synced_at` | Met |
| Posted invoice with no postings takes its lines' cost | Met |
| `lines_synced_at` only after lines are written | Met |

## The uncommitted diff

Both changes are correct.

- `pipeline.py:342-348`: `lines_synced_at` is now set only after `replace_lines`, and the totals patch is written after the lines.
- `mapping.py`: `header_from_list_sales_order` now reads `salesorder_id` and `salesorder_number`. Before, it read the missing `invoice_id` key and stored an empty string.

## Test gaps to close with task 10

- `FakeGateway` pipeline tests for the open pipeline items, including a `requests`-level check of the encoded URL.
- Run `DbStore` once against a real strict-mode MariaDB.
- `--replay` into an empty database: master fetches call the gateway and `ReplayGateway` does not log detail or master calls, so the replay can only be served from the cache.
- A second COGS pass over the same invoice.
- Sales-order header mapping (no test covers the fix above).
