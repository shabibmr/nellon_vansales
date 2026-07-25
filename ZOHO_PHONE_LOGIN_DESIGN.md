# Zoho Books Design — Phone Login + Van Sales (Option B) — SOURCE OF TRUTH

> Supersedes `ZOHO_SALESPERSON_LOCATION_SETUP.md` (old email-based flow via `cm_salesperson_location`).
> Org: `783019958` · All Zoho state below verified live 2026-07-17.

## Context & decision

Salesmen have no Zoho licenses. The app logs them in by **phone number (Firebase OTP)**, then binds the session to their Zoho Salesperson, van (storage location), personal Cash ledger, and a unique offline document-number prefix.

**Option B (chosen):** keep the live convention exactly as the org already works —
- Invoice/transaction **header** carries `salesperson_id` + `location_id` = **KGT primary business location** (`3331482000000095023`, Koyson General Trading LLC).
- The **van** is a storage location (`type: line_item_only`) set on **line items**; it carries live per-van stock. Vans are NOT business locations, cannot own Zoho number series, and never move to the header.
- **No new Zoho transaction number series.** The existing `KGT-IN-` series is untouched; app documents use app-side numbering (see §Numbering).
- Back office never creates van documents — only the app writes with these prefixes.

---

# PART A — Zoho state (DONE)

## Custom module `cm_salesperson_profile` ✅ created

- `module_id` `3331482000181494001`, API name `cm_salesperson_profile`, list endpoint `GET /cm_salesperson_profile`
- Primary field label: **"Phone Number"** → API field `record_name`

| Field label | API name | Type | Mandatory |
|---|---|---|---|
| Phone Number | `record_name` | Primary (text) | Yes |
| Salesperson | `cf_salesperson` | Lookup → Salespersons | Yes |
| Van (Location) | `cf_van_location` | Lookup → Locations (shows storage locations too) | No |
| Cash Account | `cf_cash_account` | Lookup → Chart of Accounts | No |
| Series Prefix | `cf_series_prefix` | Text (unique per salesperson, by convention) | No |
| Active | `cf_active` | Checkbox | No |

Records: **all 10 populated 2026-07-17** via `POST /cm_salesperson_profile` — `record_name` in E.164, lookups set as plain ID strings, `cf_active=true`. Van left empty for SUNEER, SHAMEER, KHALIFA, DILEEP (pending locations). Records list as `status: draft` (API cannot flip this; optional "Mark as Active" in UI — the app must NOT filter by record status; it relies on `cf_active`).

| record_name | module_record_id |
|---|---|
| +971542891246 | `3331482000181441714` |
| +971501880810 | `3331482000181449002` |
| +971542046733 | `3331482000181484002` |
| +971551128417 | `3331482000181496001` |
| +971542891247 | `3331482000181496007` |
| +971542891249 | `3331482000181497001` |
| +971551327458 | `3331482000181498001` |
| +971581125098 | `3331482000181499001` |
| +971542046726 | `3331482000181500001` |
| +971542046728 | `3331482000181492011` |

**Lookup field JSON shape (verified live):** each lookup returns two flat keys — the ID and a display name, e.g. `"cf_salesperson": "3331482000105822316", "cf_salesperson_formatted": "SHIHAB DEIRA"` (same pattern for `cf_van_location`, `cf_cash_account`). Empty lookups are simply absent from the record JSON.

Old module `cm_salesperson_location` (`3331482000181002001`) is superseded; safe to delete after cutover.

## Salesperson mapping (verified live)

| Phone | Zoho name (exact) | salesperson_id | Cash account | Code | cash account_id |
|---|---|---|---|---|---|
| 0542891246 | SHIHAB DEIRA | `3331482000105822316` | Cash In Hand - SHIHAB DEIRA | 1.9.3000 | `3331482000181489002` |
| 0501880810 | SUNEER | `3331482000181486002` | Cash In Hand - SUNEER | 1.9.3010 | `3331482000181450004` |
| 0542046733 | SHAMEER TAYYIL&HASHIM | `3331482000001449184` | Cash In Hand - SHAMEER TAYYIL&HASHIM | 1.9.3020 | `3331482000181490002` |
| 0551128417 | YOONUS | `3331482000006369121` | Cash In Hand - YOONUS | 1.9.3030 | `3331482000181474003` |
| 0542891247 | MANSOOR | `3331482000000796039` | Cash In Hand - MANSOOR | 1.9.3040 | `3331482000181491002` |
| 0542891249 | SHINAD | `3331482000180728088` | Cash In Hand - SHINAD | 1.9.3050 | `3331482000181447431` |
| 0551327458 | ASHRAF ALI | `3331482000015297587` | Cash In Hand - ASHRAF ALI | 1.9.3060 | `3331482000181441705` |
| 0581125098 | MUHAMED SHAFI | `3331482000007794735` | Cash In Hand - MUHAMED SHAFI | 1.9.3070 | `3331482000181492002` |
| 0542046726 | KHALIFA | `3331482000000838397` | Cash In Hand - KHALIFA | 1.9.3080 | `3331482000181493002` |
| 0542046728 | DILEEP KUMAR | `3331482000000796096` | Cash In Hand - DILEEP KUMAR | 1.9.3090 | `3331482000181488007` |

All 10 cash accounts created 2026-07-17 (type `cash`, codes `1.9.3000`–`1.9.3090`).

## Van storage locations (parent = KGT `3331482000000095023`)

| Salesperson | Location name | location_id |
|---|---|---|
| SHIHAB DEIRA | SHIHAB DEIRA | `3331482000163512567` |
| YOONUS | YOONUS | `3331482000005949201` |
| MANSOOR | MANSOOR | `3331482000177581063` |
| SHINAD | SHINAD | `3331482000180671517` |
| ASHRAF ALI | SHARJAH-ASHRAF ALI (Warehouse) | `3331482000005776963` |
| MUHAMED SHAFI | SHAFI-SHARJAH (Warehouse) — **to confirm** | `3331482000003357500` |
| SUNEER | *pending — org location limit reached* | — |
| SHAMEER TAYYIL&HASHIM | *pending* | — |
| KHALIFA | *pending* | — |
| DILEEP KUMAR | *pending* | — |

> Location limit options: delete inactive AJM/SHJ-SHIYAS (`3331482000003356426`), repurpose zero-stock ABDUL NASAR (`3331482000083921005`), or upgrade plan.

## Series prefixes (proposed — confirm before populating records)

| Salesperson | Prefix |
|---|---|
| SHIHAB DEIRA | `SHB-` |
| SUNEER | `SNR-` |
| SHAMEER TAYYIL&HASHIM | `SMR-` |
| YOONUS | `YNS-` |
| MANSOOR | `MNS-` |
| SHINAD | `SND-` |
| ASHRAF ALI | `ASH-` |
| MUHAMED SHAFI | `SHF-` |
| KHALIFA | `KHL-` |
| DILEEP KUMAR | `DLP-` |

---

# PART B — App implementation contract (TO BUILD)

## B1. Phone normalization rule

Firebase Phone Auth returns **E.164**: `+9715xxxxxxxx`. The mapping table above uses local UAE format `05xxxxxxxx`.

**Rule: store `record_name` in E.164** when populating records (`0542891246` → `+971542891246`), and match the Firebase phone verbatim. If a record was entered locally, the app normalizes before compare:

```
normalize(p): strip spaces/dashes; if starts with '05' → '+9715' + rest; if starts with '971' → '+…'; else as-is
```

Apply `normalize()` to BOTH sides of the match so either storage format works.

## B2. Login binding flow

```
Firebase Phone OTP → verified phone (E.164)
  1. GET /cm_salesperson_profile?organization_id=783019958
       list key: "module_records"
       find record where normalize(record_name) == normalize(phone)
       → none          ⇒ ERROR "Not registered — contact admin."
       → cf_active !== true ⇒ ERROR "Login disabled — contact admin."
       → cf_salesperson / cf_cash_account empty ⇒ ERROR "Not fully mapped — contact admin."
       → cf_van_location empty ⇒ login ALLOWED in **orders-only mode**:
           assigned_warehouse_id falls back to the KGT primary location, and the
           app permits ONLY Sales Order creation (no invoices, receipts, returns,
           stock transfers) until a van is mapped. Applies to SUNEER, SHAMEER,
           KHALIFA, DILEEP until their van locations exist.
  2. GET /salespersons → confirm the looked-up salesperson_id exists & is active
  3. GET /locations   → resolve van location + primary (is_primary=true → KGT)
  4. Cache session (see B3), seed number counters (see B5) → Authenticated
```

Lookup fields come back with **both id and name** — `cf_<field>` (ID string) + `cf_<field>_formatted` (display name); see verified shape in Part A. `cf_series_prefix` and `cf_active` come back as plain values.

## B3. Session cache spec (Hive `master_data_box`)

| Key | Value | Source |
|---|---|---|
| `session_phone` | E.164 phone | Firebase |
| `salesperson_id` / `salesperson_name` | from `cf_salesperson` lookup | profile record |
| `assigned_warehouse_id` | van location_id (from `cf_van_location`); **fallback: KGT primary if van unmapped** | profile record (existing key — Issue-to-Van + line items already read it) |
| `orders_only_mode` | `true` when `cf_van_location` was empty — UI gates all transactions except Sales Orders | derived at login |
| `primary_warehouse_id` | KGT primary location_id | `GET /locations` `is_primary` |
| `cash_account_id` | from `cf_cash_account` lookup | profile record |
| `voucher_prefix` | `cf_series_prefix` | profile record (existing key) |

## B4. Transaction payload rules

| Element | Value |
|---|---|
| Header `salesperson_id` | session salesperson_id (all sales docs) |
| Header `location_id` | **KGT primary** (`primary_warehouse_id`) — matches live convention |
| Line item `location_id` | **van** (`assigned_warehouse_id`) — stock deducts from van |
| Receipt (`/customerpayments`) deposit `account_id` | session `cash_account_id` |
| Issue-to-Van | unchanged: transfer KGT → van storage location |

**List fetches — filter by `salesperson_id`** (+ date ranges), NOT by location (van locations are not header filters):
`GET /invoices?salesperson_id=…`, `/salesorders?…`, `/customerpayments?…`, `/creditnotes?…`.

## B5. Duplicate-proof offline numbering

- Document number = `voucher_prefix` + type tag + zero-padded counter, one counter per transaction type:
  - Invoice `SHB-INV-00001`, Order `SHB-SO-00001`, Receipt `SHB-RCT-00001`, Return `SHB-CN-00001`
- **Seed on login and on every full sync:** counter = max(
  - highest number in Zoho: `GET /invoices?invoice_number_startswith=<prefix>` (equivalent param per type),
  - highest unsynced number in local `sync_queue_box` + `local_history_box`
  ) + 1
- Push with **`ignore_auto_number_generation=true`** so Zoho keeps the app's number (KGT-IN- series unaffected).
- Zoho org-wide number uniqueness is the hard backstop: on duplicate rejection → re-seed, renumber, retry the queue item.
- One licensed device per salesperson (existing LicenseGate) = single writer per prefix.

## B6. Code entry points

| Concern | File |
|---|---|
| OTP UI + auth states | `lib/ui/features/auth/bloc/auth_bloc.dart`, `lib/ui/features/auth/views/login_page.dart` |
| Firebase phone auth | `lib/data/services/firebase_auth_service.dart` |
| Profile fetch + session bind | `lib/data/repositories/salesperson_repository_impl.dart` (`verifyAndBindSession`) |
| API calls, credentials, mock flags | `lib/data/services/zoho_api_client.dart` |
| Payload shaping (header/line locations, deposit account) | `lib/data/services/zoho_payload_mapper.dart` |
| Queue processing, number retry | `lib/data/services/sync_worker.dart` |
| Session keys storage | `lib/data/services/hive_database_service.dart` (`master_data_box`) |

## B7. Remaining setup checklist

1. ☑ ~~Populate 10 `cm_salesperson_profile` records~~ — done 2026-07-17 (see record table in Part A)
2. ☐ Create 4 missing van locations once the location-limit is resolved; backfill `cf_van_location` (until then those 4 log in as **orders-only**)
3. ☐ Confirm SHAFI-SHARJAH is MUHAMED SHAFI's van
4. ☑ ~~Capture lookup-field JSON shape~~ — `cf_<field>` + `cf_<field>_formatted`, recorded in Part A
5. ☐ Delete old `cm_salesperson_location` module after cutover
6. ☐ Decide on SHAMIL AUH (11th salesperson? has own location `3331482000142772133`)
7. ☐ Optional: bulk "Mark as Active" the 10 records in the Zoho UI (cosmetic; app ignores record status)
