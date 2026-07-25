# Zoho Books Setup — Login / Registration Identity

This guide lists what an admin must configure **inside Zoho Books** so the app can:

1. Authorize **registered** users after Firebase sign-in  
2. Allow **first-time registration** when Firebase has no user yet  
3. Bind van **location**, **primary HQ**, and optional **voucher prefix** for the session  

---

## Login / registration flow (app)

```
LOGIN PAGE
  1) Firebase signIn(email, password)
  2a) Success → REGISTERED path
  2b) user-not-found → REGISTRATION path
  2c) wrong-password → Invalid email or password (no Zoho)
  Forgot password? → Firebase sendPasswordResetEmail only

REGISTERED
  GET /salespersons
  GET /locations  → cache; store is_primary as primary_warehouse_id
  Email must match an active salesperson
  GET /cm_salesperson_location → require cf_location_id
  Bind session → Authenticated

REGISTRATION (user-not-found)
  Same Zoho verifies as above
  Confirm password twice
  Firebase createUser
  Bind session → Authenticated
```

---

## API endpoints (from `zohodocs` + live)

Base: `https://www.zohoapis.com/books/v3`  
Every call needs query `organization_id`.

| Concern | Method | Path | Doc |
|---------|--------|------|-----|
| Salespersons | `GET` | `/salespersons` | Not in zohodocs; live-verified |
| Locations | `GET` | `/locations` | `zohodocs/locations.yml` → `list_locations` |
| Salesperson location mapping | `GET` | `/cm_salesperson_location` | `zohodocs/custom-modules.yml` → `list_custom_module_records` (`/{module_name}`) |
| Organization | `GET` | `/organizations/{organization_id}` | `zohodocs/organizations.yml` → `get_organization` (masters sync after license) |

**Do not use** `GET /users` for app agents — that is Zoho org users, not salespersons.

---

## Prerequisites — three things must line up per user

| # | Where | Required? | Purpose |
|---|-------|-----------|---------|
| 1 | **Zoho Salesperson** with **`salesperson_email`** | **Yes** | Must match login email (active) |
| 2 | **Custom module** `cm_salesperson_location` | **Yes** | Email + non-empty `cf_location_id` |
| 3 | **Firebase Auth** | Created on first successful registration, or by admin | Password credentials |

### Error messages

| Condition | App message |
|-----------|-------------|
| Not in salespersons | Contact admin — user does not exist in Zoho Books. |
| No mapping / empty location | Contact admin — user is not mapped to a location in Zoho Books. |
| Wrong password | Invalid email or password. |
| Password reset sent | Check your email for a password reset link. |

---

## Step 1 — Locations

1. **Settings → Locations** — one location per van + one **Primary** HQ.  
2. List IDs via API:

```
GET https://www.zohoapis.com/books/v3/locations?organization_id=<ORG_ID>
```

Fields used: `location_id`, `location_name`, `is_primary` (boolean).

- **Primary** → stored as app `primary_warehouse_id` (Issue-to-Van HQ).  
- **Mapped van location** → `assigned_warehouse_id` from the custom module (never overwrite primary with van).

Optional: location custom field **`cf_voucher_prefix`** for local offline document prefixes.

---

## Step 2 — Salespersons

1. Create/activate each agent as a **Salesperson**.  
2. Set **`salesperson_email`** to the exact login email.  

```
GET https://www.zohoapis.com/books/v3/salespersons?organization_id=<ORG_ID>
```

---

## Step 3 — Custom module `cm_salesperson_location`

| Item | Value |
|------|--------|
| Module API name | `cm_salesperson_location` |
| List | `GET /cm_salesperson_location` |
| List key | `module_records` |
| Email | primary field **`record_name`** (label “Email”) |
| Location | **`cf_location_id`** (single-line text, numeric location id) |
| Optional | `cf_voucher_prefix`, `cf_salesperson_id`, `cf_location_name`, `cf_active` |

OAuth scope must allow custom modules, e.g. **`ZohoBooks.fullaccess.all`** or `ZohoBooks.custommodules.ALL` (see `custom-modules.yml`).

Verify:

```
GET https://www.zohoapis.com/books/v3/cm_salesperson_location?organization_id=<ORG_ID>
```

Expected shape:

```json
{
  "module_records": [
    {
      "record_name": "agent1@yourcompany.com",
      "cf_location_id": "460000000038080"
    }
  ]
}
```

---

## Step 4 — Admin onboarding checklist

1. Salesperson + **email**  
2. Van location id  
3. One primary HQ location  
4. Mapping row: email + `cf_location_id`  
5. Optional voucher prefix  
6. Agent opens app → first login registers Firebase after Zoho OK; later logins use Firebase + re-verify  

Password reset is **Firebase only** (Forgot password on login screen).

---

## Quick reference

| Item | Value |
|------|--------|
| Module API name | `cm_salesperson_location` |
| Email field | `record_name` |
| Location field | `cf_location_id` |
| List key | `module_records` |
| Salespersons | `GET /salespersons` |
| Locations | `GET /locations` |
| Org | `GET /organizations/{organization_id}` |
| Van session key | Hive `assigned_warehouse_id` |
| Primary HQ key | Hive `primary_warehouse_id` |
| Voucher prefix key | Hive `voucher_prefix` |

Code entry points:

- `SalespersonRepository.verifyAndBindSession` — `lib/data/repositories/salesperson_repository_impl.dart`  
- Auth orchestration — `lib/ui/features/auth/bloc/auth_bloc.dart`  
- API client — `lib/data/services/zoho_api_client.dart`  

---

## Known live test data (org `783019958`)

Populate **`salesperson_email`** on native salespersons for every app user. Mapping and native email must agree. Example test mapping: MANSOOR van location `3331482000177581063` — keep Firebase email and Zoho salesperson email consistent with `record_name` on the mapping.
