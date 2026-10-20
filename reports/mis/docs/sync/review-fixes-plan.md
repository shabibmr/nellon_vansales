# Transaction sync — review fixes: implementation plan

Source: `transaction-sync-review.md` (21 Oct 2026). Task list: `review-fixes-tasks.md`. Parent plan: `transaction-sync-plan.md`; original tasks: `transaction-sync-tasks.md`.

No Zoho call is needed for any step. Run tests from `reports/mis`:
`./.venv/bin/python -m unittest tests.test_zoho_sync tests.test_seed_extractions`.

## Goal

Close the three blocking bugs and the "should fix" items from the review, then finish task 10 so the tests lock in the corrected behaviour. Task 10 alone closes nothing in the review: it only adds tests. Fixes come first so the tests assert correct behaviour, not the bugs.

## Order of work

1. **Store layer** (bug 3). Everything else writes through the store, so a real `update` comes first.
2. **Watermark** (bugs 1 and 2). Independent of the store; small.
3. **Pipeline correctness** (partial documents, retry overwrite, per-dataset errors, 02:00 check).
4. **COGS** (repeatability, table loads). Depends on step 1 for its writes.
5. **Tests** (task 10, reworded and extended). Each fix lands with its test; the remaining task 10 bullets follow.
6. **Real-database check** (strict-mode MariaDB), last, once the store changes exist.

## Design decisions

### A. Partial-column writes (bug 3)

- Add `Store.update(table, key, values)` to the protocol, `MemoryStore` and `DbStore`.
- `DbStore.update` runs `UPDATE table SET c1=%s, … WHERE key_cols=%s`. It validates columns the same way `upsert` does (a key that is not a column raises).
- It raises when no row matches, so a patch against a missing header is a visible failure, not a silent no-op. `MemoryStore` raises the same way.
- Callers to switch from `upsert(update_cols=…)`: the detail patch (`pipeline.py:348`) and the COGS writes (`cogs.py:111-121`: `sales_invoices`, `sales_lines`, `debit_notes`).
- `upsert(update_cols=…)` stays for full-row inserts that name the columns to refresh on conflict. Document that it must not be used for partial rows.
- `MemoryStore.upsert` gains a NOT NULL check from a column spec only if cheap; otherwise the real-MariaDB test (task R9) is the guard.

### B. Watermark (bugs 1 and 2)

- **Double encoding.** `ZohoClient.get` hands params to `requests`, which encodes. The pipeline therefore passes the raw watermark (`+` stays `+`). Keep `encode_watermark` only if a non-`requests` caller needs it; otherwise remove it and its docs. Update the plan and tasks wording ("Encode `+` as `%2B`") to "pass the raw text; `requests` encodes it".
- **Seed.** `watermark.seed` converts the stored `DATETIME` into Zoho text: `YYYY-MM-DDTHH:MM:SS+0400` (Asia/Dubai, no DST). The conversion is one pure function, `to_zoho_watermark(dt)`, tested at both ends (midnight, single-digit fields). The seed uses it; nothing else formats a watermark.
- `highest` compares parsed datetimes, not strings, so mixed offsets order correctly.

### C. Pipeline

- **No partial documents.** In `_store_document`, build the full id set first (list-row ids ∪ detail ids ∪ doc refs), run every `ensure` and doc-ref load, and only then upsert header, patch and lines. A raise before the first write leaves nothing stored and the document goes to `sync_pending`.
- **Retry and doc-ref loads.** `_sync_by_id` must not pass the detail payload as `list_row`. Either fetch the list-row fields it needs, or write only the detail-derived columns on those paths (using `Store.update`) so list-only fields are not overwritten with `0` or an empty string.
- **One bad list.** `sync_dataset` catches any exception from the list loop, records `error` in the dataset summary, leaves that watermark alone, and `run_all` continues to the next dataset. The run exits non-zero if any dataset errored. `BudgetExceeded` still stops the whole run (the budget is shared).
- **02:00 check.** `Run` records `started_at` in Asia/Dubai (injectable). `run_cost_of_sales` reads the hour from `run.started_at`, not `run.now()`. The default clock becomes timezone-aware.
- **Minor.** Drop the duplicate `is_current` check in `_load_detail`.

### D. COGS

- **Repeatable weights.** `apply_cogs` weights each line by its own cost, computed from stored `quantity`, `purchase_price` and `conversion_rate` when `baseline_cogs` is absent. Never fall back to the stored `cogs`. A second pass over the same invoice gives the same result.
- **Stale spread.** If postings disappear, a posted invoice falls back to the sum of its lines' own cost (existing rule), computed from the same source, so the stale spread is not kept.
- **Table loads.** Replace the three whole-table reads (`cogs.py:84-88`, `pipeline.py:122`) with keyed reads: invoices by id list or date range, lines by invoice id, `gl_journals` by account and date range. Add a `Store.iter_where` (or equivalent) with the filter pushed into SQL for `DbStore`.

### E. Tests

- Pipeline bullets of task 10 run on `FakeGateway` and `MemoryStore`.
- The watermark test asserts the prepared URL (via `requests.Request(...).prepare()`), expecting `%2B` once. It replaces the assertion at `tests/test_zoho_sync.py:870`.
- A `DbStore` integration test runs against a real MariaDB in strict mode. It is opt-in (environment variable), skipped otherwise, and uses a throwaway schema. This is the one place task 10's "no database" rule is relaxed.
- Replay: add the empty-database case, where master fetches must be served from the cache.

## Risks

- `Store.update` changes the protocol; any other `Store` implementer must follow. Only `MemoryStore` and `DbStore` exist today.
- Making the clock timezone-aware can break tests that inject naive datetimes. Update the injection helper once.
- Moving the header write after the id checks changes when a failed document appears in `sync_pending`; the existing pending tests need a re-check.
- Keyed reads for COGS must return the same rows the whole-table reads did; cover with a before/after same-rows test.

## Done when

- All tasks in `review-fixes-tasks.md` are `[x]`.
- The 77 existing tests plus the new ones pass.
- The strict-mode MariaDB test passes once on a real server.
- Task 10 in `transaction-sync-tasks.md` is fully ticked and its watermark wording is corrected.
