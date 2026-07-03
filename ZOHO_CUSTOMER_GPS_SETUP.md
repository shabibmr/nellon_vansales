# Zoho Books Setup — Customer GPS Location (cf_latitude / cf_longitude)

This guide explains the **one-time admin configuration** required inside Zoho Books so the van sales app can read and write precise GPS coordinates for customers (contacts).

The app already contains the code; it only needs the custom fields to exist with the exact API names.

## Why this is needed

Zoho Books Contacts do not have built-in latitude/longitude fields. The app stores and syncs customer GPS using **Custom Fields** on the Contacts module.

- When masters are synced, any `cf_latitude` / `cf_longitude` values present in Zoho are pulled into the app.
- When a user captures GPS for a customer (either during "New Customer" or when selecting an existing customer that lacks GPS), the app:
  1. Updates the local cache immediately.
  2. **Pushes the values to Zoho immediately** (PUT on the contact) when online.
  3. Falls back to the offline queue if needed.

## Step 1 — Create the two custom fields on Contacts

1. In Zoho Books go to **Settings ⚙️ → Custom Fields**.
2. Select the **Contacts** module (or "Customers & Vendors").
3. Click **+ New Custom Field**.

Create **two** fields:

| Field Label     | Field Type          | **Required API Name** | Notes |
|-----------------|---------------------|-----------------------|-------|
| `Latitude`      | Decimal / Number    | `cf_latitude`         | Allow decimals, up to 6–8 places recommended. |
| `Longitude`     | Decimal / Number    | `cf_longitude`        | Same as above. |

- After saving, **verify the generated API names exactly match** `cf_latitude` and `cf_longitude`.
  - Zoho automatically prefixes `cf_` based on the label.
  - If Zoho generates something different (e.g. `cf_lat` or `cf_latitude_1`), rename the field label until the API name is exact.
- These fields are **not required** on the contact form in Zoho (they can stay blank until the mobile app populates them).

## Step 2 — (Optional) Add the fields to your Contacts list view / form layout

- Go to **Settings → Customization → Layouts and Fields → Contacts**.
- Drag the two new fields into the desired section of the form and list view so back-office users can see them.
- This is purely for visibility — the app works regardless.

## Step 3 — Verify via the Zoho API (recommended)

Before testing the app, confirm the fields exist and are writable by calling:

```
GET https://www.zohoapis.com/books/v3/contacts?contact_type=customer&organization_id=<YOUR_ORG_ID>
```

Look at any contact object. When the fields are present on a contact you should eventually see:

```json
{
  "contact_id": "...",
  ...
  "custom_field_hash": {
    "cf_latitude": "12.9716",
    "cf_longitude": "77.5946"
  },
  "custom_fields": [
    { "api_name": "cf_latitude", "value": "12.9716", ... },
    { "api_name": "cf_longitude", "value": "77.5946", ... }
  ]
}
```

To manually set a test value from the API (POST/PUT example):

```json
PUT /contacts/{contact_id}
{
  "custom_fields": [
    { "api_name": "cf_latitude", "value": "25.2048" },
    { "api_name": "cf_longitude", "value": "55.2708" }
  ]
}
```

## Step 4 — Test in the app

1. Ensure you have performed a **Masters Sync → Customers** after the fields were created.
2. Two ways to populate GPS:
   - **New Customer** dialog → tap "CAPTURE CURRENT LOCATION".
   - **Select an existing customer without GPS** (in invoice, order, receipt, etc.) → the app shows a prompt dialog with a Capture button.
3. After capture:
   - The customer record immediately shows the coordinates in the UI.
   - The values are sent to Zoho right away (visible in the contact under the custom fields or via API).
4. Later master syncs will continue to reflect the GPS values.

## Quick reference (exact values the app depends on)

| Item                        | Exact value |
|-----------------------------|-------------|
| Latitude field API name     | `cf_latitude` |
| Longitude field API name    | `cf_longitude` |
| Update payload shape        | `{ "custom_fields": [ {"api_name": "cf_latitude", "value": "..."}, ... ] }` |
| Used on                     | Contacts module only (customers) |

If your Zoho org uses a different data center (`.in`, `.eu`, etc.) the base URL changes but field names stay the same.

## Troubleshooting

- **Fields not appearing after master sync** — the fields must exist before the first fetch that populates them. Re-run Masters Sync after creation.
- **Update not visible in Zoho** — check that the refresh token used by the app has write access to contacts/custom fields. Re-generate the token with `ZohoBooks.contacts.UPDATE` (or full) scope if needed.
- **API names differ** — the app hard-codes `cf_latitude` / `cf_longitude`. Rename the fields in Zoho until the names match exactly.

Once the two fields exist with the correct API names, the GPS Location feature for Customers is fully operational.
