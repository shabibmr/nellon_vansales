---
name: zoho-books-api
description: Guide for integrating with the Zoho Books v3 REST API, covering OAuth 2.0 token management, sync ordering rules, master data caching, and offline-first queue resolution.
metadata:
  model: models/gemini-3.5-flash-high
  last_modified: Sun, 24 May 2026 04:53:00 GMT
---
# Zoho Books v3 REST API Integration Guide

This skill covers the design, architecture, and integration patterns for the Zoho Books v3 REST API inside the offline-first Flutter application. 

## Contents
- [OAuth 2.0 Token Flow](#oauth-20-token-flow)
- [Relational Sync Ordering](#relational-sync-ordering)
- [Temporary ID Resolution](#temporary-id-resolution)
- [API Payloads & Models](#api-payloads--models)
- [Master Data Caching](#master-data-caching)
- [Workflow: Managing Sync Operations](#workflow-managing-sync-operations)

---

## OAuth 2.0 Token Flow

The application interfaces with Zoho Books using OAuth 2.0 client credentials. To bypass expiration issues, a **Dio Interceptor** handles request signing and automatic token renewal.

### Request Signing & Interceptor
Every outgoing request is intercepted via `InterceptorsWrapper` to append authentication headers and organization parameters:

1. **Authorization Header**: Signed as `'Zoho-oauthtoken <ACCESS_TOKEN>'`.
2. **JSON Format String**: Appended as `'JSONString': 'true'`.
3. **Organization Header**: Appended as query parameter `organization_id`.

```dart
_dio.interceptors.add(
  InterceptorsWrapper(
    onRequest: (options, handler) async {
      if (_isMockMode()) return handler.next(options);

      final accessToken = await _getOrRefreshAccessToken();
      if (accessToken != null) {
        options.headers['Authorization'] = 'Zoho-oauthtoken $accessToken';
        options.headers['JSONString'] = 'true';
        options.queryParameters['organization_id'] = _organizationId;
      }
      return handler.next(options);
    },
    onError: (DioException error, handler) async {
      if (error.response?.statusCode == 401 && !_isMockMode()) {
        // Force refresh token on 401 Unauthorized
        final newAccessToken = await _refreshAccessToken(force: true);
        if (newAccessToken != null) {
          final requestOptions = error.requestOptions;
          requestOptions.headers['Authorization'] = 'Zoho-oauthtoken $newAccessToken';
          
          // Retry the original request
          try {
            final response = await _dio.fetch(requestOptions);
            return handler.resolve(response);
          } catch (e) {
            return handler.next(error);
          }
        }
      }
      return handler.next(error);
    },
  ),
);
```

### Expiry Management
* **Expiry Buffer**: Check the cached expiry timestamp with a **60-second buffer** before making requests to prevent tokens from expiring in flight.
* **Auto-Refresh**: If the token is within the buffer window or has expired, a `POST` request is fired to `https://accounts.zoho.com/oauth/v2/token` containing the `refresh_token`, `client_id`, `client_secret`, and `grant_type: 'refresh_token'`.

---

## Relational Sync Ordering

Because transactions inside Zoho Books have foreign key relations (e.g., a Sales Invoice must be linked to a valid Zoho Customer ID), a strict sync ordering is enforced in the `SyncWorker`:

> [!IMPORTANT]
> **Relational Synchronization Rule**
> The sync queue must always prioritize `customer` transactions. All other offline entries (invoices, receipts, returns, expenses) must wait until pending customers have successfully posted to the remote server.

### Queue Sorting Routine
The sorting logic prioritizes `"customer"` type payloads while keeping all other transactions in chronological order:

```dart
pendingItems.sort((a, b) {
  if (a.type == 'customer' && b.type != 'customer') return -1;
  if (a.type != 'customer' && b.type == 'customer') return 1;
  return a.timestamp.compareTo(b.timestamp);
});
```

---

## Temporary ID Resolution

When a new customer is created while the app is offline, a temporary offline ID is generated (e.g. `temp_cust_171658823`).

### The Mapping Challenge
Transactions created offline (like a sales invoice or receipt payment) will reference this local `temp_cust_...` ID. If sent directly to Zoho, the transaction will fail because the reference ID is unrecognized.

### Resolution Steps
1. The `SyncWorker` synchronizes the `customer` entry first.
2. Zoho API returns a successful response containing the permanent Zoho ID (e.g. `20349920199`).
3. The `SyncWorker` fires `_resolveTempCustomerIdsInQueue(tempId, permanentId)`.
4. It iterates through the remaining queue items (`pending` or `failed`) and replaces all instances of `customer_id` and `customerId` with the permanent Zoho ID.

```dart
Future<void> _resolveTempCustomerIdsInQueue(String tempCustomerId, String permanentZohoId) async {
  final currentQueue = _dbService.getSyncQueue();
  for (final item in currentQueue) {
    if (item.status == SyncStatus.pending || item.status == SyncStatus.failed) {
      bool modified = false;
      final updatedPayload = Map<String, dynamic>.from(item.payload);

      if (updatedPayload['customer_id'] == tempCustomerId) {
        updatedPayload['customer_id'] = permanentZohoId;
        modified = true;
      }
      if (updatedPayload['customerId'] == tempCustomerId) {
        updatedPayload['customerId'] = permanentZohoId;
        modified = true;
      }

      if (modified) {
        await _dbService.updateSyncItem(item.copyWith(payload: updatedPayload));
      }
    }
  }
}
```

---

## API Payloads & Models

Below is a summary of the five transaction sync types and their corresponding Zoho Books API endpoints:

| Transaction Type | Target Endpoint / Method | Description |
| :--- | :--- | :--- |
| `customer` | `POST /contacts` | Creates contacts (customers) |
| `invoice` | `POST /invoices` | Generates a new sales invoice |
| `receipt` | `POST /customerpayments` | Logs invoice payments |
| `return` | `POST /creditnotes` | Credits returned products |
| `expense` | `POST /expenses` | Registers fuel, tolls, or meal expenses |

---

## Master Data Caching

To enable offline operations, master data is periodically pulled from Zoho Books and cached locally using **Hive**.

### Refreshable Masters
* **Routes & Warehouses**: Loaded on-demand or during synchronization routines to match inventories and territory restrictions.
* **Taxes**: Holds standard Zoho sales tax rates (e.g. CGST, SGST).
* **Payment & Expense Accounts**: Essential for linking payments to the correct asset account, and expenses to the correct ledger.
* **Open Invoices**: Enables offline payment captures by maintaining unpaid customer accounts.

---

## Workflow: Managing Sync Operations

Use this workflow checklist when modifying or testing Zoho API integration.

- [ ] **1. Credentials Verification**
  Ensure actual OAuth credentials (`_clientId`, `_clientSecret`, `_organizationId`) are populated in `zoho_api_client.dart` when exiting Sandbox Mock Mode.

- [ ] **2. Dependency Injection Wires**
  Verify `ZohoApiClient` and `SyncWorker` are registered as singletons in `injection.dart` and booted after `HiveDatabaseService`.

- [ ] **3. Sync Test Guard**
  When adding new Zoho REST methods, write corresponding mock tests utilizing `mockito` to evaluate HTTP timeouts and payload parsing.

- [ ] **4. Check Queue Ordering**
  Ensure the customer-first sync sorting routine remains intact whenever changes are made to the `SyncWorker` class.
