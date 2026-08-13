import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/data/services/zoho_mock/zoho_mock_path.dart';
import 'package:van_sales/domain/models/expense_account.dart';
import 'package:van_sales/domain/models/payment_account.dart';

/// Minimal Hive stand-in for expense account resolution + client construction.
class _FakeDb extends HiveDatabaseService {
  List<ExpenseAccount> expenseAccounts = const [];
  List<PaymentAccount> paymentAccounts = const [];

  @override
  List<ExpenseAccount> getExpenseAccounts() => expenseAccounts;

  @override
  List<PaymentAccount> getPaymentAccounts() => paymentAccounts;

  @override
  String? get assignedWarehouseId => 'van_wh_01';

  @override
  String? get primaryWarehouseId => '3331482000000095023';

  @override
  String? get voucherPrefix => 'SHB-';

  @override
  String? get oauthAccessToken => null;

  @override
  int? get oauthTokenExpiry => null;

  @override
  getCurrentSalesperson() => null;
}

ZohoApiClient _client({
  bool placeholderCredentials = true,
  bool mockTransactions = true,
  bool mockSalesOrders = true,
  bool mockStockTransfers = true,
}) {
  final client = ZohoApiClient(
    dbService: _FakeDb(),
    mockLatency: Duration.zero,
  );
  if (placeholderCredentials) {
    client.updateCredentials(
      clientId: 'YOUR_CLIENT_ID',
      clientSecret: 'YOUR_CLIENT_SECRET',
      refreshToken: 'YOUR_REFRESH_TOKEN',
      organizationId: 'org_test',
    );
  } else {
    // Non-placeholder ids so credential mock mode is off.
    client.updateCredentials(
      clientId: '1000.LIVE_TEST_CLIENT',
      clientSecret: 'live_test_secret',
      refreshToken: 'live_test_refresh',
      organizationId: 'org_live',
    );
  }
  client.updateMockFlags(
    mockTransactions: mockTransactions,
    mockSalesOrderTransactions: mockSalesOrders,
    mockStockTransfers: mockStockTransfers,
  );
  return client;
}

void main() {
  group('ZohoMockPath', () {
    test('normalizes absolute Inventory transferorders URL', () {
      final options = RequestOptions(
        path: 'https://www.zohoapis.com/inventory/v1/transferorders',
        method: 'POST',
      );
      expect(ZohoMockPath.normalize(options), '/transferorders');
    });

    test('keeps relative Books paths', () {
      final options = RequestOptions(path: '/invoices', method: 'POST');
      expect(ZohoMockPath.normalize(options), '/invoices');
    });
  });

  group('ZohoMockInterceptor routing', () {
    test('placeholder credentials mock all methods including GET', () {
      final client = _client(placeholderCredentials: true);
      final getReq = RequestOptions(path: '/contacts', method: 'GET');
      final postReq = RequestOptions(path: '/invoices', method: 'POST');
      expect(client.mockInterceptor.shouldMockRequest(getReq), isTrue);
      expect(client.mockInterceptor.shouldMockRequest(postReq), isTrue);
    });

    test('live credentials mock only flagged transaction writes', () {
      final client = _client(
        placeholderCredentials: false,
        mockTransactions: true,
        mockSalesOrders: false,
        mockStockTransfers: true,
      );
      expect(
        client.mockInterceptor.shouldMockRequest(
          RequestOptions(path: '/contacts', method: 'GET'),
        ),
        isFalse,
      );
      expect(
        client.mockInterceptor.shouldMockRequest(
          RequestOptions(path: '/invoices', method: 'POST'),
        ),
        isTrue,
      );
      expect(
        client.mockInterceptor.shouldMockRequest(
          RequestOptions(path: '/salesorders', method: 'POST'),
        ),
        isFalse,
      );
      expect(
        client.mockInterceptor.shouldMockRequest(
          RequestOptions(
            path: 'https://www.zohoapis.com/inventory/v1/transferorders',
            method: 'POST',
          ),
        ),
        isTrue,
      );
    });
  });

  group('sync writes share mapper + Zoho envelope', () {
    late ZohoApiClient client;

    setUp(() {
      client = _client(placeholderCredentials: true);
    });

    test('syncCustomer maps payload and returns contact_id from envelope',
        () async {
      final id = await client.syncCustomer({
        'contact_name': 'Acme',
        'company_name': 'Acme Co',
        'email': 'a@b.com',
        'phone': '123',
        'billing_address': {'address': '1 Main'},
        'credit_limit': 1000,
        'route_id': 'route_north',
        'isPendingSync': true,
        'id': 'temp_cust_1',
      });

      expect(id, startsWith('zoho_cust_'));
      final body = client.mockCatalog.lastRequest!.data as Map;
      expect(body['contact_name'], 'Acme');
      expect(body.containsKey('isPendingSync'), isFalse);
      expect(body.containsKey('route_id'), isFalse);
      expect(body.containsKey('id'), isFalse);
    });

    test('syncInvoice maps payload and returns invoice_id from envelope',
        () async {
      final id = await client.syncInvoice({
        'customer_id': 'cust_101',
        'customer_name': 'Metro',
        'invoice_number': 'SHB-INV-00001',
        'date': '2026-01-01',
        'due_date': '2026-01-08',
        'notes': 'n',
        'isPendingSync': true,
        'line_items': [
          {
            'item_id': 'item_501',
            'quantity': 2,
            'rate': 60.0,
            'tax_percentage': 5.0,
            'discount': 0.0,
            'item': {'name': 'Milk'},
          },
        ],
      });

      expect(id, startsWith('zoho_inv_'));
      final body = client.mockCatalog.lastRequest!.data as Map;
      expect(body['customer_id'], 'cust_101');
      expect(body.containsKey('customer_name'), isFalse);
      expect(body.containsKey('isPendingSync'), isFalse);
      final lines = body['line_items'] as List;
      expect(lines.first.containsKey('item'), isFalse);
      expect(lines.first['item_id'], 'item_501');
    });

    test('syncSalesOrder returns salesorder_id from envelope', () async {
      final id = await client.syncSalesOrder({
        'customer_id': 'cust_101',
        'salesorder_number': 'SO-1',
        'date': '2026-01-01',
        'line_items': [
          {'item_id': 'item_501', 'quantity': 1, 'rate': 10.0},
        ],
      });
      expect(id, startsWith('zoho_so_'));
    });

    test('updateCustomerGps returns same contact id from envelope', () async {
      final id = await client.updateCustomerGps('cust_101', 1.0, 2.0);
      expect(id, 'cust_101');
      expect(client.mockCatalog.lastRequest!.method.toUpperCase(), 'PUT');
    });

    test('syncStockTransfer hits transferorders and returns transfer_order_id',
        () async {
      final id = await client.syncStockTransfer({
        'from_location_id': 'loc_a',
        'to_location_id': 'loc_b',
        'line_items': [
          {'item_id': 'item_501', 'quantity_transfer': 5},
        ],
      });
      expect(id, startsWith('zoho_to_'));
      final path = ZohoMockPath.normalize(client.mockCatalog.lastRequest!);
      expect(path, endsWith('/transferorders'));
    });
  });

  group('reads via mock envelopes', () {
    late ZohoApiClient client;

    setUp(() {
      client = _client(placeholderCredentials: true);
    });

    test('fetchCustomers returns fixture contacts through _fetchAllPages',
        () async {
      final customers = await client.fetchCustomers();
      expect(customers, isNotEmpty);
      expect(customers.first['contact_id'], 'cust_101');
    });

    test('fetchOrganization unwraps organization envelope', () async {
      final org = await client.fetchOrganization();
      expect(org, isNotNull);
      expect(org!['currency_code'], 'AED');
      expect(org['name'], 'Mock Org');
      expect(org['tax_settings']['tax_reg_no'], '100577492000003');
      expect(org['address'], isA<Map>());
    });

    test('fetchContactDetail includes tax_reg_no', () async {
      final contact = await client.fetchContactDetail('cust_101');
      expect(contact['contact_id'], 'cust_101');
      expect(contact['tax_reg_no'], '100533986400003');
    });

    test('fetchInvoiceDetail unwraps invoice envelope', () async {
      final inv = await client.fetchInvoiceDetail('inv_9001');
      expect(inv['invoice_id'], 'inv_9001');
      expect(inv['line_items'], isNotEmpty);
    });

    test('fetchSalesOrders returns list via page envelope', () async {
      final orders = await client.fetchSalesOrders();
      expect(orders.length, greaterThanOrEqualTo(1));
      expect(orders.first['salesorder_id'], isNotNull);
    });
  });
}
