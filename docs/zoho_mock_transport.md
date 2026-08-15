# Zoho mock transport

## Goal

Mock and live share the same workflow through payload shaping and Dio call construction. Mock only re-routes at the HTTP layer.

```
payload → ZohoPayloadMapper / inject location / resolve accounts
       → dio.get | post | put
            ├─ live  → real Zoho
            └─ mock  → ZohoMockInterceptor → Zoho-shaped Response
       → parse response.data[…]
```

## Components

| File | Role |
|------|------|
| `lib/data/services/zoho_mock/zoho_mock_interceptor.dart` | Dec interceptor; decides mock vs pass-through from flags |
| `lib/data/services/zoho_mock/zoho_mock_catalog.dart` | Builds Zoho-shaped response bodies |
| `lib/data/services/zoho_mock/zoho_mock_fixtures.dart` | List/detail datasets |
| `lib/data/services/zoho_mock/zoho_mock_path.dart` | Normalizes relative + absolute Inventory URLs |

## When a request is mocked

| Condition | Result |
|-----------|--------|
| Placeholder credentials (`YOUR_CLIENT_ID` / empty) | **All** Books/Inventory calls on this Dio |
| Real credentials + `_mockTransactions` | POST/PUT contacts, invoices, payments, creditnotes, expenses |
| Real credentials + `_mockSalesOrderTransactions` | Sales order create/update/convert |
| Real credentials + `_mockStockTransfers` | Books v3 `transferorders` |
| Real credentials + GET masters | **Live** network |

## Response shapes

Write successes return the same envelopes live parsers use, e.g.:

```json
{ "code": 0, "contact": { "contact_id": "zoho_cust_…" } }
{ "code": 0, "invoice": { "invoice_id": "zoho_inv_…" } }
```

List GETs return plural keys + `page_context.has_more_page` so `_fetchAllPages` works unchanged.

Unknown mocked routes return HTTP 404 (as `DioException`) rather than a silent success.

## Tests

See `test/zoho_mock_transport_test.dart` (mapper stripping, envelope ids, routing flags, list/detail GETs).
