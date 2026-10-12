# Zoho Books API Integration & Context Guide

This context document outlines how to authenticate, construct, execute, and handle Zoho Books v3 REST API requests within the `reports/mis` workspace and adjacent tools.

---

## 1. Credentials & Environment Setup

All Zoho Books API interactions require OAuth 2.0 credentials located in the project root's `.env_zoho` file (`../../.env_zoho` from this folder):

```bash
ZOHO_CLIENT_ID="<your_client_id>"
ZOHO_CLIENT_SECRET="<your_client_secret>"
ZOHO_REFRESH_TOKEN="<your_refresh_token>"
ZOHO_ORG_ID="<your_organization_id>"
```

### Base Endpoints
- **Accounts / Token URL**: `https://accounts.zoho.com/oauth/v2/token`
- **Books API Base URL**: `https://www.zohoapis.com/books/v3` *(US DC, adapt to `.in`/`.eu` if multi-datacenter)*

---

## 2. Authentication Flow (OAuth 2.0)

Zoho Books uses short-lived access tokens (typically valid for 1 hour). To obtain an active access token using the persistent refresh token:

### Token Request
```http
POST https://accounts.zoho.com/oauth/v2/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token=<ZOHO_REFRESH_TOKEN>&client_id=<ZOHO_CLIENT_ID>&client_secret=<ZOHO_CLIENT_SECRET>
```

### Token Response
```json
{
  "access_token": "1000.xxxx.yyyy",
  "api_domain": "https://www.zohoapis.com",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

### Request Headers & Parameters
Every API call to Zoho Books requires:
1. **Header**: `Authorization: Zoho-oauthtoken <access_token>`
2. **Header**: `Content-Type: application/json;charset=UTF-8`
3. **Query Parameter**: `organization_id=<ZOHO_ORG_ID>` on **all** calls.

---

## 3. Python API Client (`zoho_client.py`)

The workspace provides [`zoho_client.py`](zoho_client.py) which handles authentication, session headers, and organization injection automatically.

### Basic Usage Example
```python
from zoho_client import ZohoClient

# Initializes client, loads .env_zoho, and fetches access token
client = ZohoClient()

# Example 1: Fetch Failed Workflows report
failed_workflows = client.get(
    "/reports/failedworkflows",
    params={"show_failed_only": "true"}
)
print("Upcoming/Failed:", failed_workflows.get("upcoming_workflows_details"))

# Example 2: Fetch General Ledger report for Trial Balance
ledger = client.get(
    "/reports/generalledger",
    params={
        "filter_by": "TransactionDate.CustomDate",
        "from_date": "2026-04-01",
        "to_date": "2026-10-11",
    }
)
print("Ledger accounts:", len(ledger.get("general_ledger", [])))

# Example 3: Fetch Chart of Accounts
coa = client.get(
    "/chartofaccounts",
    params={"showbalance": "true"}
)
print("Chart of accounts:", len(coa.get("chartofaccounts", [])))
```

---

## 4. Making API Calls via cURL

To test calls directly from the terminal:

### Step 1: Generate Access Token
```bash
ACCESS_TOKEN=$(curl -s -X POST "https://accounts.zoho.com/oauth/v2/token" \
  -d "grant_type=refresh_token" \
  -d "client_id=$ZOHO_CLIENT_ID" \
  -d "client_secret=$ZOHO_CLIENT_SECRET" \
  -d "refresh_token=$ZOHO_REFRESH_TOKEN" | jq -r '.access_token')
```

### Step 2: Make the Request
```bash
curl -X GET "https://www.zohoapis.com/books/v3/reports/failedworkflows?organization_id=$ZOHO_ORG_ID" \
  -H "Authorization: Zoho-oauthtoken $ACCESS_TOKEN" \
  -H "Content-Type: application/json"
```

---

## 5. Important Endpoint Groups

### A. Reports & Monitoring Endpoints (`/reports/...`)
Used for financial exports, data audits, and workflow log inspection:
- `GET /reports/failedworkflows` — Logs of workflow rules that failed during execution.
- `GET /reports/failedworkflowactions` — Logs of specific actions (webhooks, email alerts) that failed.
- `GET /reports/workflowlogs` — Complete workflow execution history logs.
- `GET /reports/upcomingworkflows` — Scheduled/time-based workflows waiting to fire.
- `GET /reports/generalledger` — Account transaction postings (used by [`export_trial_balance.py`](export_trial_balance.py)).
- `GET /reports/trialbalance` — Standard Trial Balance report.
- `GET /reports/profitandloss` — Income statement.
- `GET /reports/balancesheet` — Statement of financial position.

### B. Core Business & Master Data Endpoints
- `GET /chartofaccounts` — Chart of accounts list with classification.
- `GET /invoices` / `POST /invoices` — Sales invoices.
- `GET /bills` / `POST /bills` — Vendor bills.
- `GET /contacts` / `POST /contacts` — Customers and vendors.
- `GET /settings/workflows` — Workflow rules configuration.

---

## 6. Query Parameters, Filters & Pagination

Zoho Books supports standardized query parameters:

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `organization_id` | `string` | **Required**. Organization ID. |
| `page` | `integer` | Page number to fetch (default: `1`). |
| `per_page` | `integer` | Number of records per page (default: `100`, max: `200`). |
| `filter_by` | `string` | Date/status filter (e.g., `TransactionDate.ThisMonth`, `TransactionDate.CustomDate`). |
| `from_date` / `to_date` | `YYYY-MM-DD` | Date range boundary when using `TransactionDate.CustomDate`. |
| `sort_column` | `string` | Column name to sort results by. |
| `sort_order` | `string` | `A` (Ascending) or `D` (Descending). |

---

## 7. Response Format & Error Handling

Standard responses wrap payloads inside a JSON object:

### Successful Response
```json
{
  "code": 0,
  "message": "success",
  "page_context": {
    "page": 1,
    "per_page": 100,
    "has_more_page": false
  },
  "<resource_key>": [...]
}
```

### Error Response
```json
{
  "code": 1002,
  "message": "Invalid OAuth token"
}
```

### Best Practices:
1. **Token Refresh on 401**: Catch HTTP 401 errors and refresh the access token before retrying.
2. **Rate Limits**: Zoho Books enforces API call limits (standard orgs: 2,500–10,000 calls/day; burst limit: 100 calls/minute). Implement backoff on HTTP `429`.
3. **Filter on Server**: Use `filter_by` and date bounds rather than filtering massive recordsets client-side.
