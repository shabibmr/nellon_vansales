# Zoho Books Setup — Salesperson → Location Mapping

This guide lists the changes an admin must make **inside Zoho Books** so the app can resolve each
logged-in salesperson to their assigned Zoho **Location** on login. The app code is already in place;
it only needs the data below to exist.

> **What the app does with this:** on login it matches the Firebase user's email to a Zoho
> **Salesperson**, then looks up that email in a custom module to find the mapped **Location ID**.
> That Location ID becomes the active van/stock location and is stamped onto every transaction
> (sales orders, invoices, receipts, returns, expenses), which are then filtered per location.

---

## Prerequisites — three things must line up per user

For a salesperson to resolve successfully, the **same email** must exist in all three places:

| # | Where | Purpose |
|---|-------|---------|
| 1 | **Firebase Auth** user (login email) | How the person signs into the app |
| 2 | **Zoho Books → Salesperson** record | App matches the login email to a Zoho salesperson |
| 3 | **Custom module record** (below) | Supplies the mapped Location ID for that email |

If email #2 is missing, no salesperson resolves and location filtering is simply skipped (login still works).
If email #3 is missing, the salesperson resolves but with **no** location (again, no filtering).

---

## Step 1 — Confirm your Locations exist and note their IDs

1. In Zoho Books go to **Settings ⚙️ → General → Locations** (may be called *Branches* in some orgs).
2. Make sure a Location exists for each van/territory (e.g. `Van 01`, `Van 02`).
3. **Get each Location's numeric ID.** The ID is not shown in the UI directly — obtain it via the API:
   - `GET https://www.zohoapis.com/books/v3/locations?organization_id=<YOUR_ORG_ID>`
   - Each entry has a `location_id` (a long numeric string, e.g. `460000000038080`).
   - Record the `location_name` → `location_id` pairs; you'll need the IDs in Step 3.

> The app only injects a location onto live Zoho payloads when the ID is **purely numeric**
> (mock placeholders like `van_wh_01` are ignored), so use the real numeric `location_id`.

---

## Step 2 — Create the custom module `salesperson_locations`

1. Go to **Settings ⚙️ → Custom Modules** → **+ New Module**.
2. Name the module so its **API name (module_name) is exactly `salesperson_locations`.**
   - Zoho derives the API name from the module's plural label. Name it **"Salesperson Locations"**
     and confirm Zoho generates the plural API name `salesperson_locations`.
   - ⚠️ **Verify the generated API name** — the app calls `GET /salesperson_locations`. If Zoho
     produces a different name, either rename to match or the code endpoint must be changed.
3. Add two fields to the module:

   | Field label | Field type | **Required API name** |
   |-------------|-----------|------------------------|
   | `Email`       | Email (or Single-line text) | `cf_email` |
   | `Location ID` | Single-line text            | `cf_location_id` |

   - Zoho auto-generates each field's API name from its label with a `cf_` prefix
     (`Email` → `cf_email`, `Location ID` → `cf_location_id`).
   - ⚠️ **Verify each generated API name matches exactly** (`cf_email`, `cf_location_id`).
     The app reads these keys verbatim from each record. If Zoho generates something else
     (e.g. `cf_location_i_d`), rename the field until the API name matches, or the code must change.
   - Use **text** for `Location ID` (the IDs are long numbers; a Number field may round or reformat them).

---

## Step 3 — Add one record per salesperson

For every salesperson who logs into the app, create a record in the **Salesperson Locations** module:

| cf_email (Email)          | cf_location_id (Location ID) |
|---------------------------|------------------------------|
| `agent1@yourcompany.com`  | `460000000038080`            |
| `agent2@yourcompany.com`  | `460000000038094`            |

- `cf_email` **must** match the salesperson's Firebase login email (case-insensitive is fine).
- `cf_location_id` is the numeric `location_id` from Step 1.

---

## Step 4 — Ensure OAuth scope can read custom modules

The app authenticates with a stored refresh token. Reading custom-module records requires the token's
scope to include custom-module (or full) access. If Step 5 verification returns **401/403**, the current
refresh token lacks scope.

1. Regenerate the refresh token (via your Zoho API Console self-client or auth flow) with a scope that
   covers custom modules, e.g. **`ZohoBooks.fullaccess.all`** (or the specific module read scope).
2. Update the credentials the app uses — either the remote **Server Config** that `ServerConfigCubit`
   loads (preferred), or the `_refreshToken` / `_clientId` / `_clientSecret` constants in
   `lib/data/services/zoho_api_client.dart`.

> Note: `GET /salespersons` and `GET /locations` are standard endpoints and are already reachable with
> the existing scope; only the custom module may need the wider scope.

---

## Step 5 — Verify from the API before testing the app

Run these two calls (any REST client) with your org's access token to confirm the data is readable:

```
GET https://www.zohoapis.com/books/v3/salespersons?organization_id=<YOUR_ORG_ID>
GET https://www.zohoapis.com/books/v3/salesperson_locations?organization_id=<YOUR_ORG_ID>
```

Expected from the second call — records with the custom fields inline:

```json
{
  "salesperson_locations": [
    { "cf_email": "agent1@yourcompany.com", "cf_location_id": "460000000038080", ... }
  ]
}
```

- If you get **401/403** → revisit Step 4 (scope).
- If the array is present but keys are `cf_something_else` → revisit Step 2 (field API names).

---

## Step 6 — Test in the app

1. Log in as a mapped salesperson.
2. Trigger a master-data sync (the **Masters Sync** screen now includes a **Salespersons** row).
3. Create a Sales Order (or Invoice). It should be stamped with the mapped Location.
4. Log in as a **different** salesperson mapped to a **different** Location and confirm the first
   salesperson's transactions are filtered out of the list views.

---

## Quick reference — what the app expects

| Item | Exact value the code depends on |
|------|---------------------------------|
| Custom module API name (`module_api_name`) | `cm_salesperson_location` (Zoho auto-prefixed `cm_`) |
| Email field | primary field `record_name` (module `record_name` label = "Email") |
| Location ID field API name | `cf_location_id` |
| List response key | `module_records` |
| Location value format | numeric Zoho `location_id` (not a mock `van_wh_*` placeholder) |
| Endpoints used | `GET /salespersons`, `GET /locations`, `GET /cm_salesperson_location` |

> **This module was provisioned via the Zoho Books API** (not the UI) on org `783019958`.
> Zoho auto-generated the module api_name `cm_salesperson_location` and stores the salesperson
> email in the module's **primary field `record_name`** (labeled "Email"), with the mapped
> location in the custom field **`cf_location_id`**. The app code
> (`fetchSalespersonLocationMappings` in `lib/data/services/zoho_api_client.dart` and the email
> match in `lib/data/repositories/salesperson_repository_impl.dart`) is already reconciled to
> these exact names.

### ⚠️ Prerequisite that is NOT yet satisfied for most users

The native Zoho **Salesperson** records mostly have a **blank `salesperson_email`** (only a few are
populated). The login match is `Firebase email → salesperson_email → record_name`, so a salesperson
whose Zoho email is blank will **never resolve a location**. To onboard a user you must first set that
salesperson's `salesperson_email` in Zoho (Step 2 in the app's setup) **and** add a matching record in
`cm_salesperson_location`. So far this has been done for **MANSOOR** (`algoraytechnologies@gmail.com`
→ location `MANSOOR` / `3331482000177581063`) as a test.
