# Transaction sync — seven watermarked lists

Approved plan, saved from the session on 21 Oct 2026 and revised the same day. Nothing in this plan has been implemented yet.

This plan covers the runs from now on only. Backfill of older documents is handled separately and is not part of this work.

Sync only Books transactions whose list accepts `last_modified_time`. Each changed row is written as a header from that list, then its detail is read and its lines are upserted. After all seven lists, one Cost of Sales pass sets invoice and debit-note COGS from the ledger postings. No per-document journal call is made.

A transaction is stored only after every id on it that Zoho filled in already exists in the master table it points at. A missing id is fetched through `masters.ensure`, that master row is written, and only then does the sync return to the transaction. An id Zoho left blank is stored as NULL, except the customer or vendor id, which is required. No Zoho call until a run is explicitly allowed. Pace stays 3 calls per minute unless a faster pace is approved. Token refresh counts.

## What the requirement is

For each changed document:

1. `GET` the list with `last_modified_time` set to the dataset's watermark in `sync_state`. The list does not contain line items.
2. Collect every master id on that list row. For each non-blank id that is not already in its table, call `ensure` for it and wait until the row is stored. Then upsert the header.
3. `GET` the document by id. Collect every master id on the header and on each line. Fetch any that are still missing. Then update the header and replace its lines in the document's line table (`sales_lines`, `debit_note_lines`, `purchase_lines`, `vendor_credit_lines`, `sales_order_lines`, or `vendor_payment_bills`).

Replace lines: upsert by `line_item_id`, delete lines of that document that are no longer in the payload.

After all seven lists, run the Cost of Sales pass (see Step 3). It is the only step that writes `sales_invoices.cogs` and `debit_notes.cogs`.

If the customer or vendor id is blank, or `ensure` fails for a master, store nothing for that document. Leave `lines_synced_at` empty and put the id in `sync_pending`. The next run retries it even when the list filter would no longer return it. The watermark still moves past it (see Watermarks).

Draft and void are stored, once their master ids resolve.

## Ids

Required on every header: `customer_id` (sales documents) or `vendor_id` (purchase documents). Blank means the document is not stored.

Optional, stored as NULL when Zoho leaves them blank, and resolved first when filled in:

- Header: `salesperson_id` (sales documents only; `purchase_docs`, `vendor_credits`, and `vendor_payments` have no salesperson column), `location_id`.
- Line: `item_id` (a description-only line has none), `location_id`, `account_id`.
- Item row, a dependency in the item `MasterSpec`: `account_id`, `purchase_account_id`.

A filled-in id that its script cannot write (the call fails, or Zoho answers 404) is not replaced by NULL. The document stays in `sync_pending` with the error, and is retried each run. After 3 failed attempts it is listed in the run summary as needing attention.

A debit note requires `reference_invoice_id`, when set, to exist on `sales_invoices`. A vendor payment requires each `bill_id` in `bills[]` to exist on `purchase_docs` as `kind='bill'`. A vendor credit requires `bill_id`, when set, to exist the same way. Those are documents, not masters. The sync loads that invoice or bill (detail, then the same master-first rule) before inserting the debit note, payment, or credit. It does not invent a row for them.

## Master scripts

All six masters go through one module, `zoho_sync/masters.py`: a `MasterSpec` per master and one function, `ensure(run, kind, id)`. The transaction sync calls `ensure` and does not insert until it returns. The six `fetch_*.py` files are thin command-line wrappers over `ensure` (about 10 lines each, no logic of their own), so each master is still runnable on its own; `python -m zoho_sync fetch KIND ID` does the same. Every call goes through the run's gateway, so the 3-per-minute cap holds across them.

`ensure(run, kind, id)` does, in order:

1. Return when the id is in the run's memo or already in the store. No Zoho call.
2. Call Zoho by id, or read the list and pick the id, as the spec says.
3. Check the type when the spec has a check. A mismatch raises `WrongType` and writes nothing.
4. Save the response to the cache.
5. Call `ensure` for each dependency the spec names that is filled in on the payload.
6. Map with the spec's pure mapper and upsert, updating only the spec's update columns.

A failed call raises, and a 404 raises `NotFound`. The caller records the document in `sync_pending`.

| Kind | Wrapper | Lookup | Call | Type check | Writes | Depends on | Cache |
|---|---|---|---|---|---|---|---|
| customer | `fetch_customer.py CONTACT_ID` | id | `GET /contacts/{contact_id}` | `contact_type` is customer | `customers` | — | `contacts` |
| vendor | `fetch_vendor.py CONTACT_ID` | id | `GET /contacts/{contact_id}` | `contact_type` is vendor | `vendors` | — | `contacts` |
| item | `fetch_item.py ITEM_ID` | id | `GET /items/{item_id}` | — | `items`, `item_units` | `account_id`, `purchase_account_id` → account | `items` |
| account | `fetch_account.py ACCOUNT_ID` | id | `GET /chartofaccounts/{account_id}` | — | `accounts` | `parent_account_id` → account | `chartofaccounts` |
| location | `fetch_location.py LOCATION_ID` | list | `GET /locations` | — | `locations`, the matching id | — | run folder |
| salesperson | `fetch_salesperson.py SALESPERSON_ID` | id, else list | `GET /salespersons/{salesperson_id}`, else `GET /salespersons` | — | `salespersons` | — | `salespersons`, or run folder for the list |

Adding a master later is a new `MasterSpec` and a wrapper. `ensure` does not change.

Customer and vendor are separate kinds. The same display name may exist once as each. A wrapper whose type check fails exits non-zero, and the transaction stays unstored.

The item mapper reads unit conversions from the detail payload. The account spec's update columns are the Zoho columns only, so `category`, `pl_bs`, and `source` are kept on duplicate.

Location uses the list because Books has no `GET /locations/{location_id}` (`zohodocs/locations.yml` defines only PUT and DELETE on that path). The local OpenAPI has no salespersons file. If `GET /salespersons/{id}` is not a Books route, the salesperson spec switches to the list. The transaction still waits for that row.

## The seven

These are the Books transaction lists that take `last_modified_time`. Manual journals (`GET /journals`), recurring bills, and base-currency adjustments are not included. Inventory is not used.

| # | Document | List | Comparison the spec states | Sort by `last_modified_time` | Header table | Lines |
|---|---|---|---|---|---|---|
| 1 | Customer debit notes | `GET /invoices?filter_by=Type.DebitNote` | Modified **after** | Not stated | `debit_notes` | `debit_note_lines` |
| 2 | Sales invoices | `GET /invoices` | Modified **after** the timestamp | No | `sales_invoices` | `sales_lines` |
| 3 | Bills | `GET /bills` | Modified **at or after** | No | `purchase_docs` `kind=bill` | `purchase_lines` |
| 4 | Vendor credits | `GET /vendorcredits` | Not stated | Yes | new `vendor_credits` | new `vendor_credit_lines` |
| 5 | Sales orders | `GET /salesorders` | Not stated | Yes | new `sales_orders` | new `sales_order_lines` |
| 6 | Purchase orders | `GET /purchaseorders` | Not stated | No | `purchase_docs` `kind=purchase_order` | `purchase_lines` |
| 7 | Vendor payments | `GET /vendorpayments` | Not stated | Not stated | new `vendor_payments` | new `vendor_payment_bills` (not item lines) |

Each row of this table is one `DocSpec` in `zoho_sync/specs.py` (fields under Code structure). The pipeline reads everything that differs between documents from the spec.

Debit notes run before invoices. The invoice list row has no `type` field (`zohodocs/invoices.yml`, `list-invoices-response`), so the invoice pass cannot tell a debit note from its list row. The debit-note pass records its ids for the run. The invoice pass skips those ids, and also skips any row that is already on `debit_notes`; in the invoice spec this is `exclude_ids_from='debit_notes'`. The detail step checks `type` again before writing a line, and moves a debit note it finds to the debit-note path instead of `sales_invoices` (the invoice spec's `reroute` hook).

Credit notes are not one of the seven. `GET /creditnotes` has no `last_modified_time` parameter. This plan does not poll them. Their Cost of Sales reversals still arrive with the postings in Step 3, but their headers and lines do not, so net sales does not show returns until credit notes are synced.

## Watermarks

The watermark is the raw Zoho `last_modified_time` text (for example `2026-10-21T14:02:51+0400`) stored in `sync_state.watermark` as `VARCHAR`, not `DATETIME`, because a `DATETIME` drops the offset. Send it percent-encoded: `+` must go as `%2B` (the invoices spec example shows `%2B0800`).

Pass the watermark on every list. Invoices and debit notes are strict "after". Bills are "at or after", so the boundary row comes back and the header upsert is a no-op. The other four do not say equal versus after, so they use the same overlap. Do not add a second: two documents can share a timestamp, and skipping equals would drop one of them.

A dataset's watermark moves only after its whole list for that run has been read and every row has been either stored or put in `sync_pending`. The new value is the highest `last_modified_time` seen on that run's list rows. Invoices, bills, and purchase orders cannot be sorted by `last_modified_time`, so a run that stops partway (`--max-calls`, an error) leaves that dataset's watermark where it was. The next run reads the same list again, and rows already stored are no-ops.

A failed document does not hold back the watermark. It is kept in `sync_pending` and retried on every run until it is stored.

The first run needs a watermark. Before it, seed each dataset in `sync_state` from the highest `last_modified_time` already stored in that dataset's header table. With no watermark, the run refuses to start for that dataset. It does not list from the beginning.

## Step 1 — header from the list row

Write the columns the list row actually carries: id, number, date, due date, status, party id and name, salesperson id and name, location id and name, currency, exchange rate, total, balance, shipping charge and adjustment where present, and `last_modified_time`. Leave detail-only amounts (`sub_total`, discounts, tax, reference, reason) unchanged until the detail step, which updates the same header row. Never write `cogs` here.

`net_sales` on a sales invoice is not on the list. It is computed from the lines (ex-tax amount after discounts, times `exchange_rate`). Until the detail step it stays at its previous value, or 0 on a new row.

The party, salesperson, and location ids on that row are fetched first, as above.

Vendor payments have no item lines. The list header is the payment. The detail step writes `bills[]` (`bill_payment_id`, `bill_id`, `amount_applied`, tax withheld) into `vendor_payment_bills`, after each bill row exists.

New header tables follow the existing invoice column set, cut to what that document has. Vendor credits mirror that shape with a vendor instead of a customer, and no COGS column. Sales orders mirror invoices without COGS. `purchase_docs.kind` stays `bill` or `purchase_order` only.

## Step 2 — detail and lines

| Document | Detail | Cache folder |
|---|---|---|
| Debit note | `GET /invoices/{debit_note_id}` | `debitnotes` |
| Invoice | `GET /invoices/{invoice_id}` | `invoices` |
| Bill | `GET /bills/{bill_id}` | `bills` |
| Vendor credit | `GET /vendorcredits/{vendor_credit_id}` | `vendorcredits` |
| Sales order | `GET /salesorders/{salesorder_id}` | `salesorders` |
| Purchase order | `GET /purchaseorders/{purchaseorder_id}` | `purchaseorders` |
| Vendor payment | `GET /vendorpayments/{payment_id}` | `vendorpayments` |

Before any line insert, call `ensure` for every non-blank item, location, and account id on those lines that is not already stored. Then insert the lines with those ids.

Each line's own cost is set here by `seed_common.line_cogs` (quantity times `purchase_price`, with the pack-versus-base rule already used for this org). That is the line cost before the Cost of Sales pass. The header `cogs` is not touched in this step. Sales lines (invoices and debit notes) are built by `zoho_sync/mapping.build_sales_lines`, which is the per-line block moved out of `seed_missing_sales.build_invoice_rows`; the seeder imports it back.

Skip the detail call when a cache file for that id exists and its `last_modified_time` equals the list row. Cache write stays the bare document object at `output/cache/{folder}/{id}.json`, replaced through a `.tmp` file. No MariaDB `raw_json` on transaction tables.

Set `lines_synced_at` when the lines (or `vendor_payment_bills`) of that document are written.

## Step 3 — Cost of Sales pass

Run once per run, after all seven lists. This is the only place `sales_invoices.cogs` and `debit_notes.cogs` are written.

### Which dates

- Every date of a posted, draft, or void invoice or debit note this run stored.
- On the 02:00 run: every date in a trailing window (the current month, plus the previous month until its 5th day). A backdated bill can revalue stock and replace the postings of later invoices without changing those invoices' `last_modified_time`.
- On the 02:00 run: for every bill this run changed with date D, every date from D to today.
- Every date range left in `sync_pending` with `dataset='cogs'`.

Merge those dates into continuous ranges.

### The call

For each range, `GET /chartofaccounts/transactions?account_id=3331482000000034003&date_start=…&date_end=…&per_page=200`, page by page while `page_context.has_more_page` is true. That account is Cost of Sales - Nellon (5.1.1000). `seed_missing_sales.py` uses `date_start` / `date_end` against this route and reads only the first page; the new pass must read every page.

The fetch is `reports/account_postings.fetch_pages`, the existing pager, changed to take a gateway instead of creating its own `ZohoClient`, and to send `date_start` / `date_end`. Today it sends `date.start` / `date.end` (`reports/account_postings.py:136`), and `refresh_cos_nellon_range.py` notes that `date_start` is the one that works. `fetch_cost_of_sales_nellon.py` and the other `run_cli` callers keep working through a live gateway.

Replace that account's rows in `gl_journals` for the range in one transaction: upsert by `(account_id, categorized_transaction_id)` with `reports/account_postings.to_row`, and delete that account's rows dated in the range that Zoho no longer lists. Zoho replaces revalued postings under a new `categorized_transaction_id`, so an upsert alone would double count. `raw_json` is left NULL; the page file in the run folder is the raw copy.

### What is written

For each invoice dated in a range that was pulled:

| Case | `sales_invoices.cogs` | Lines | `cogs_synced_at` |
|---|---|---|---|
| Posted, postings found | Sum of `amount` (debit minus credit) on that account's `inventory_valuation_for_invoice` rows where `transaction_id` is the invoice id, rounded to 2 decimals | Header total spread by each line's own cost; if those sum to 0, by line `net_sales`; the remainder cent goes to the largest line | Set |
| Posted, no postings (service-only, or not yet posted) | Sum of the lines' own cost | Unchanged | Set |
| Draft or void | 0 | 0 | Set |
| Pull for that range failed | Unchanged | Unchanged | Left as it was; range goes to `sync_pending` |

Debit notes follow the same table into `debit_notes.cogs` and `debit_note_lines.cogs`, once the posting type for a debit note is confirmed from a saved response. Until then a debit note takes the sum of its lines' own cost and `cogs_synced_at` is set.

Credit-note reversals land in the same account. They are kept in `gl_journals` and are not added to any invoice.

`seed_missing_sales.py` (`load_gl_cogs` and the reconcile block in `build_invoice_rows`) already does this matching and spreading. Both move into `zoho_sync/cogs.py` and the seeder imports them back, so there is one version:

- `load_invoice_postings(store, account_id, invoice_ids)` replaces `load_gl_cogs`. It filters on the Cost of Sales account and on the given ids, instead of grouping the whole of `gl_journals`. The seeder passes its own ids.
- `apply_cogs(status, lines, postings_total)` is pure. It returns the header COGS and each line's COGS for the four cases in the table above, spreading with `seed_common.prorate`.

## Files on disk

| What | Where | Kept |
|---|---|---|
| Detail responses | `output/cache/{folder}/{id}.json`, latest version only | Always |
| Master responses | `output/cache/{contacts,items,chartofaccounts,salespersons}/{id}.json` | Always |
| List pages, postings pages, location and salesperson list pages | `output/runs/{run_id}/{dataset}/page-N.json` | 30 days |
| Run summary (calls made, rows stored, pending, watermark before and after) | `output/runs/{run_id}/summary.json` | 30 days |

`run_id` is the run's start time in Asia/Dubai, `YYYYMMDD-HHMMSS`. A saved run folder can be replayed into MariaDB without a Zoho call. `output/` is not tracked in git.

## Code structure

The runner is the package `reports/mis/zoho_sync/`. CLI:

- `python -m zoho_sync run`: without `--yes-live`, no network. `--max-calls N` caps one run.
- `python -m zoho_sync run --replay RUN_ID`: the same pipeline over a saved run folder, with no network.
- `python -m zoho_sync fetch KIND ID`: one master, as the `fetch_*.py` wrappers do.
- `python -m zoho_sync seed-watermarks`: the first-run seed (see Watermarks).

Watermarks live in `sync_state` (`dataset`, `watermark`, `last_run_at`). `sync_state` is for these watermarks only; the existing `sync_coverage` table stays as the record of date ranges loaded by the seeders.

### Rules

- Every Zoho call goes through one gateway. No module in the package, and no master wrapper, creates a `ZohoClient`.
- Nothing is copied from an existing script. Code the sync needs from a script is moved into a module, and that script imports it back. A test shows the script writes the same rows before and after.
- What differs between documents or between masters is data in a spec. The pipeline and `ensure` have no `if dataset == …` branches.
- Row mapping is pure: JSON in, rows out. No database, file, network, or print.
- Modules take a `Run` context, not a growing list of keyword arguments.

### Modules

| Module | Holds | Network or DB |
|---|---|---|
| `gateway.py` | The `Gateway` interface, `get(endpoint, params) -> dict`. `LiveGateway` wraps `ZohoClient`: it signs in only on the first call and counts the sign-in, applies the budget, retries 429 and 5xx with backoff, raises `NotFound` on 404, and hands each list and postings page to `runlog`. `ReplayGateway` answers from a run folder and raises when a page is missing. `FakeGateway` answers from fixtures in tests. | Live only |
| `budget.py` | Pace (20 seconds between calls by default), `--max-calls`, a shared stamp file under `output/` with an exclusive lock | File |
| `context.py` | `Run`: gateway, store, cache, runlog, clock, mode (live, replay, test), `run_id`, the per-run master memo | — |
| `store.py` | The `Store` protocol and `MemoryStore` | — |
| `store_db.py` | The MariaDB `Store`. Imported only by the CLI and wrappers | DB |
| `cache.py` | `output/cache/{folder}/{id}.json` read and atomic write | File |
| `runlog.py` | Run folder pages, `summary.json`, the 30-day clean-up | File |
| `watermark.py` | Read and write `sync_state` through the store, `%2B` encoding, the seed | Through store |
| `masters.py` | `MasterSpec` per master, `ensure(run, kind, id)` | Through run |
| `specs.py` | `DocSpec` per dataset, in run order | — |
| `mapping.py` | Pure mappers per spec: `header_from_list(row)`, `from_detail(doc) -> (header_patch, lines)`, `collect_ids(doc) -> {kind: ids}`; `build_sales_lines(header, lines, units, rates)` | — |
| `pipeline.py` | The one loop: list from the watermark, master-first, header, detail, lines, pending, watermark | Through run |
| `ranges.py` | Cost of Sales date ranges from the run, the clock, changed bills, and pending ranges; merge into continuous ranges | — |
| `postings.py` | Read every postings page for a range (through `account_postings.fetch_pages`) and replace that range in `gl_journals` | Through run |
| `cogs.py` | `load_invoice_postings`, the pure `apply_cogs` | Through store |
| `__main__.py` | Argument parsing, building the `Run` | — |

### `Store` protocol

`get(table, key)`, `has(table, key)`, `upsert(table, rows, update_cols=None)`, `replace_lines(table, parent_col, parent_id, rows)` (upsert and delete those missing), `replace_range(account_id, date_from, date_to, rows)`, `max_value(table, column)`, pending (`add_pending`, `list_pending`, `clear_pending`), and watermarks (`get_watermark`, `set_watermark`). `MemoryStore` and the MariaDB store both implement all of them.

`store_db` builds every upsert with the one `seed_common.upsert_sql`. It reads each table's columns once (`SHOW COLUMNS`) and rejects a mapper key that is not a column, so no hand-kept column list is needed.

### `DocSpec` fields

`dataset`, `list_path`, `list_params` (for example `filter_by=Type.DebitNote`), `list_key`, `id_field`, `detail_path`, `detail_key`, `cache_folder`, `header_table`, `header_key` (`doc_id`, or `(kind, doc_id)` for purchase documents), `line_table`, `line_parent_col`, `line_key`, `line_path` (`line_items`, or `bills` for vendor payments), `party` (`customer_id` or `vendor_id`, required), `optional_ids` (header and line master ids, each with its master kind), `doc_refs` (debit note `reference_invoice_id` → invoices; vendor credit `bill_id` and payment `bills[].bill_id` → bills), `exclude_ids_from`, `reroute`, `has_cogs`, and the three mappers.

Adding a document later (credit notes, for example) is a new `DocSpec` and its mappers. The pipeline does not change.

### Shared helpers

`seed_common.py` stays the home of value helpers: `connect`, `d`, `cents`, `s`, `parse_date`, `parse_dt`, `prorate`, `doc_money`, `resolve_conversion`, `line_cogs`, `table_exists`, and the new `upsert_sql`. The package imports them and adds no copy. Existing copies are removed in this work:

| Copy | Where | Becomes |
|---|---|---|
| `connect`, `d`, `cents`, `prorate`, `table_exists` | `seed_sales_from_inv.py` | imports from `seed_common` |
| `upsert_sql` | `seed_missing_sales.py`, `seed_purchases_from_cache.py` | `seed_common.upsert_sql` |
| Postings row mapper | `fetch_and_seed_gl_journals.to_row`, inline in `seed_missing_sales.sync_recent_gl_journals` | `reports/account_postings.to_row` |
| Per-line sales build, `load_gl_cogs`, reconcile | `seed_missing_sales.py` | `zoho_sync.mapping` and `zoho_sync.cogs` |

`reports/db.connect` stays: it serves the web app's config and is not a seeder helper.

### `ZohoClient` changes

Small and backward compatible, so the other scripts keep working:

- Sign in on the first request, not in `__init__`.
- An `on_auth` callback, so `LiveGateway` counts each sign-in against the budget.
- Failures raise `ZohoHTTPError(RuntimeError)` with `status` and `code`, so a 404 can be told apart.
- Remove the unused `TOKEN_CACHE` constant. The one token cache is `ROOT/.zoho_token_cache.json`.

Retry stays out of `ZohoClient`. It lives in `LiveGateway`.

## How often, and how long

Invoices are the only set that moves through the day (about 55–85 documents a day in Sep–Oct 2026). Each one costs one detail call after the list page, plus a master call only when that customer, item, location, salesperson, or account is not already stored. A heavy day is about 3 invoice list pages, about 80 detail calls, and a few Cost of Sales pages. With the other six lists that is about 30 minutes at 3 per minute. The other six are a few documents a day (bills about 4–6, orders and vendor credits well under that, vendor payments on the order of the 160 already seen in the ledger over seven months).

Run all seven once a night at 02:00 Asia/Dubai, after posting stops, with the trailing Cost of Sales window. Add one invoice-and-debit-note pass at 21:00 on working days, with the Cost of Sales pass for that run's dates only. Do not poll hourly.

Deletes are invisible to a `last_modified_time` list. This plan does not add a delete sweep. A deleted invoice stays in MariaDB until a separate reconcile drops it.

## Tests

No network. Fixture JSON only.

- Every list sends the stored watermark, with `+` sent as `%2B`. A bill boundary row with an equal timestamp updates nothing.
- A run stopped by `--max-calls` partway through a list leaves that dataset's watermark unchanged. A finished list moves it to the highest timestamp seen, even when one document went to `sync_pending`.
- No watermark in `sync_state`: the run refuses that dataset and lists nothing.
- A debit-note id seen on the debit-note list is not inserted into `sales_invoices`, and a detail payload whose `type` is a debit note is not written as an invoice.
- A missing item, customer, vendor, salesperson, location, or account id is ensured before the insert. The stored row keeps the id.
- A blank salesperson, location, or line item id is stored as NULL. A blank customer or vendor id stores nothing.
- A master whose `ensure` fails or gets a 404 stores nothing for that document and records it in `sync_pending` with the error. The third failure appears in the run summary.
- `fetch_customer` does not write a vendor. `fetch_vendor` does not write a customer.
- Item `ensure` ensures its accounts before inserting an item that names an account.
- `fetch_location` uses the list and writes only the matching id.
- A debit note whose `reference_invoice_id` is not stored loads that invoice first.
- Lines missing from a new detail payload are deleted.
- Cost of Sales postings become `sales_invoices.cogs`, and line COGS sums to that total.
- Postings read across more than one page are all stored.
- A posting replaced under a new `categorized_transaction_id` replaces the old row and is not counted twice.
- A changed bill dated D re-pulls Cost of Sales from D to today on the 02:00 run.
- A failed postings pull leaves the previous COGS, leaves `cogs_synced_at` as it was, and records the range in `sync_pending`.
- A posted invoice with no postings takes the sum of its lines' own cost. A void invoice gets 0.
- Vendor-payment children come from `bills[]`, keyed by `bill_payment_id`, and only after that `bill_id` is on `purchase_docs`.
- `--replay` of a saved run folder makes no network call and writes the same rows.
- Every `DocSpec` maps its fixture through its three mappers alone, with no store and no gateway.
- `ensure` with a `FakeGateway` and `MemoryStore` follows each `MasterSpec`'s dependencies, and makes no call for an id already stored or already in the run memo.
- `seed_missing_sales`, `seed_sales_from_inv`, and `seed_purchases_from_cache` build the same rows from the same cache before and after the extractions.
- `account_postings.fetch_pages` sends `date_start` / `date_end` and reads every page through a `FakeGateway`.
- `LiveGateway` with a stub `ZohoClient`: the first call signs in and the sign-in is counted; a 429 is retried; a 404 raises `NotFound`; no call is made while the client is unused.
- `store_db` rejects a mapper key that is not a column (checked against a stub column list, no database).

## Not in this work

Backfill of older documents, credit-note polling, a full master list sync, `gl_journals` as a full ledger beyond the Cost of Sales account, per-document journal calls, expenses, customer payments, a delete sweep, cron installation, and any PUT to Zoho. The retry wrappers in the backfill scripts (`fetch_and_seed_gl_journals.safe_get`, `fetch_missing_oct_invoices.fetch_invoice_with_retry`) are left as they are; they move to `LiveGateway` when those scripts are next touched. No new code adds another retry wrapper.

Task list: `docs/sync/transaction-sync-tasks.md`. Endpoint filter matrix: `docs/last-modified-sync.md`.
