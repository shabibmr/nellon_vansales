import 'dart:convert';
import 'package:dio/dio.dart';
import 'hive_database_service.dart';

class ZohoApiClient {
  final Dio _dio = Dio();
  final HiveDatabaseService _dbService;

  // Zoho OAuth 2.0 credentials (in a real-world scenario, read these from secure build config or env)
  final String _accountsUrl = 'https://accounts.zoho.com/oauth/v2/token';
  final String _apiUrl = 'https://www.zohoapis.com/books/v3';
  
  final String _clientId = '1000.45EI6FPO004OW9W6BTB7TUJ9L0C0YP';
  final String _clientSecret = '1d829f7ee3e1eb7debe6ed370ccc87ab45e7b36103';
  final String _organizationId = '783019958';

  // Milestone 1: transaction posting is mocked end-to-end while masters are wired up.
  // Flip to false once invoice/receipt/return/expense/customer payloads are validated against Zoho.
  static const bool _mockTransactions = true;

  ZohoApiClient({required HiveDatabaseService this._dbService}) {
    _dio.options.baseUrl = _apiUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);

    // Request & Refresh Token Interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Check if we are running in mock sandbox mode
          if (_isMockMode()) {
            return handler.next(options);
          }

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
  }

  bool _isMockMode() {
    // Falls back to mock mode if credentials are still placeholder templates
    return _clientId.contains('YOUR_CLIENT_ID');
  }

  // --- OAuth 2.0 Handlers ---
  Future<String?> _getOrRefreshAccessToken() async {
    if (_isMockMode()) return 'mock_access_token';

    final cachedToken = _dbService.oauthAccessToken;
    final expiryMillis = _dbService.oauthTokenExpiry;

    if (cachedToken != null && expiryMillis != null) {
      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      // Use a 60-second buffer to ensure the token doesn't expire mid-request
      if (nowMillis < (expiryMillis - 60000)) {
        return cachedToken;
      }
    }

    return _refreshAccessToken();
  }

  Future<String?> _refreshAccessToken({bool force = false}) async {
    if (_isMockMode()) return 'mock_access_token';

    const refreshToken = '1000.ccb7c895a473ba5569c55565c0aed87d.c2f3a5530356193d39a19c511efed856';
    try {
      final response = await Dio().post(
        _accountsUrl,
        queryParameters: {
          'refresh_token': refreshToken,
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'grant_type': 'refresh_token',
        },
      );
      if (response.statusCode == 200) {
        final newAccessToken = response.data['access_token'];
        final expiresInSeconds = response.data['expires_in'] as int? ?? 3600;
        final expiryMillis = DateTime.now().millisecondsSinceEpoch + (expiresInSeconds * 1000);

        // Save newAccessToken and expire_in to local database
        await _dbService.setOauthAccessToken(newAccessToken);
        await _dbService.setOauthTokenExpiry(expiryMillis);
        
        return newAccessToken;
      }
    } catch (e) {
      // ignore: avoid_print
      print('Zoho OAuth Refresh Error: $e');
    }
    return null;
  }

  // --- Zoho Books REST APIs ---

  // 1. Fetch Routes (Simulated since Zoho Books doesn't have a native Route entity, we map to custom Contact Fields)
  Future<List<Map<String, dynamic>>> fetchRoutes() async {
    await Future.delayed(const Duration(milliseconds: 600)); // Network latency simulator
    
    return [
      {
        'id': 'route_north',
        'name': 'North Downtown Sequence',
        'description': 'Servicing supermarkets in the Northern metro corridor'
      },
      {
        'id': 'route_south',
        'name': 'South Retail Hub',
        'description': 'Main shopping sequence along Southern high street'
      },
      {
        'id': 'route_east',
        'name': 'East Coastal Markets',
        'description': 'General stores and bakeries in the Eastern bay area'
      }
    ];
  }

  // 2. Fetch Customers in Active Route
  Future<List<Map<String, dynamic>>> fetchCustomers(String routeId) async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get(
          '/contacts',
          queryParameters: {
            'contact_type': 'customer',
            'cf_route_id': routeId, // assumes a custom contact field
            'per_page': 200,
          },
        );
        if (response.statusCode == 200) {
          final list = (response.data['contacts'] as List? ?? []);
          return list.map((c) => Map<String, dynamic>.from(c)).toList();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Zoho fetchCustomers error: $e');
      }
      return const [];
    }

    await Future.delayed(const Duration(milliseconds: 700));

    // Realistic Mock Contacts
    final allCustomers = [
      {
        'contact_id': 'cust_101',
        'contact_name': 'Metro Hypermarket',
        'company_name': 'Metro Group Ltd',
        'email': 'procurement@metro.com',
        'phone': '+91 99000 11223',
        'address': 'Plot 42, Sector 5, North Corridor',
        'outstanding_receivable_amount': 2850.00,
        'credit_limit': 5000.00,
        'route_id': 'route_north',
        'sequence': 1
      },
      {
        'contact_id': 'cust_102',
        'contact_name': 'QuickMart Grocery',
        'company_name': 'QuickMart Retail',
        'email': 'billing@quickmart.in',
        'phone': '+91 99000 44556',
        'address': 'Building 3A, North Main St',
        'outstanding_receivable_amount': 450.00,
        'credit_limit': 1500.00,
        'route_id': 'route_north',
        'sequence': 2
      },
      {
        'contact_id': 'cust_103',
        'contact_name': 'Daily Needs Superstore',
        'company_name': 'Daily Needs Retailers',
        'email': 'store@dailyneeds.com',
        'phone': '+91 99000 77889',
        'address': 'Shop 12, Shopping Center 2, North St',
        'outstanding_receivable_amount': 0.00,
        'credit_limit': 3000.00,
        'route_id': 'route_north',
        'sequence': 3
      },
      {
        'contact_id': 'cust_201',
        'contact_name': 'Southside MegaMart',
        'company_name': 'MegaMart Inc',
        'email': 'south@megamart.com',
        'phone': '+91 98000 11111',
        'address': 'Avenue 9, South Retail Hub',
        'outstanding_receivable_amount': 1200.00,
        'credit_limit': 4000.00,
        'route_id': 'route_south',
        'sequence': 1
      },
      {
        'contact_id': 'cust_202',
        'contact_name': 'Green Apple Organic',
        'company_name': 'Green Apple Retail',
        'email': 'hello@greenapple.com',
        'phone': '+91 98000 22222',
        'address': '22 High Street, South Hub',
        'outstanding_receivable_amount': 0.00,
        'credit_limit': 1000.00,
        'route_id': 'route_south',
        'sequence': 2
      }
    ];

    return allCustomers.where((c) => c['route_id'] == routeId).toList();
  }

  // 3. Fetch Items in Van Warehouse (Zoho Books Warehouse Inventory API)
  Future<List<Map<String, dynamic>>> fetchItems(String warehouseId) async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get(
          '/items',
          queryParameters: {
            'warehouse_id': warehouseId,
            'per_page': 200,
          },
        );
        if (response.statusCode == 200) {
          final list = (response.data['items'] as List? ?? []);
          return list.map((i) => Map<String, dynamic>.from(i)).toList();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Zoho fetchItems error: $e');
      }
      return const [];
    }

    await Future.delayed(const Duration(milliseconds: 650));

    // Realistic Stock allotted to this specific van's warehouse
    return [
      {
        'item_id': 'item_501',
        'name': 'Premium Fresh Milk (1L)',
        'sku': 'MILK-PREM-1L',
        'rate': 60.00,
        'stock_on_hand': 120, // Assigned stock for this van warehouse
        'description': 'Homogenized Pasteurised Whole Milk',
        'tax_name': 'GST 5%',
        'tax_percentage': 5.0
      },
      {
        'item_id': 'item_502',
        'name': 'Double Choc Cookies (250g)',
        'sku': 'COOK-DCHOC-250G',
        'rate': 120.00,
        'stock_on_hand': 45,
        'description': 'Baked chocolate cookies with premium chips',
        'tax_name': 'GST 12%',
        'tax_percentage': 12.0
      },
      {
        'item_id': 'item_503',
        'name': 'Mineral Spring Water (500ml)',
        'sku': 'WATR-SPR-500ML',
        'rate': 20.00,
        'stock_on_hand': 200,
        'description': 'Naturally filtered pure spring water',
        'tax_name': 'GST 18%',
        'tax_percentage': 18.0
      },
      {
        'item_id': 'item_504',
        'name': 'Organic Cheddar Cheese (200g)',
        'sku': 'CHSE-CHED-200G',
        'rate': 240.00,
        'stock_on_hand': 30,
        'description': 'Aged sharp premium cheddar block',
        'tax_name': 'GST 5%',
        'tax_percentage': 5.0
      },
      {
        'item_id': 'item_505',
        'name': 'Whole Wheat Sourdough Bread',
        'sku': 'BRED-WHEAT-SOUR',
        'rate': 90.00,
        'stock_on_hand': 15,
        'description': 'Artisanal high-fiber wheat sourdough loaf',
        'tax_name': 'GST 5%',
        'tax_percentage': 5.0
      }
    ];
  }

  // 4. Zoho Books Contacts API: Sync New Customer
  Future<String> syncCustomer(Map<String, dynamic> customerJson) async {
    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.post('/contacts', data: customerJson);
        if (response.statusCode == 201 || response.statusCode == 200) {
          return response.data['contact']['contact_id'];
        }
      } catch (e) {
        throw Exception('Zoho Books Customer Sync Failed: $e');
      }
    }

    // Mock response
    await Future.delayed(const Duration(seconds: 1));
    return 'zoho_cust_${DateTime.now().millisecondsSinceEpoch}';
  }

  // 5. Zoho Books Invoices API: Sync Sales Invoice
  Future<String> syncInvoice(Map<String, dynamic> invoiceJson) async {
    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.post('/invoices', data: invoiceJson);
        if (response.statusCode == 201 || response.statusCode == 200) {
          return response.data['invoice']['invoice_id'];
        }
      } catch (e) {
        throw Exception('Zoho Books Invoice Sync Failed: $e');
      }
    }

    // Mock response
    await Future.delayed(const Duration(seconds: 1));
    return 'zoho_inv_${DateTime.now().millisecondsSinceEpoch}';
  }

  // 6. Zoho Books Customer Payments API: Sync Receipt Voucher
  Future<String> syncReceiptVoucher(Map<String, dynamic> paymentJson) async {
    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.post('/customerpayments', data: paymentJson);
        if (response.statusCode == 201 || response.statusCode == 200) {
          return response.data['payment']['payment_id'];
        }
      } catch (e) {
        throw Exception('Zoho Books Payment Sync Failed: $e');
      }
    }

    // Mock response
    await Future.delayed(const Duration(seconds: 1));
    return 'zoho_pay_${DateTime.now().millisecondsSinceEpoch}';
  }

  // 7. Zoho Books Credit Notes API: Sync Sales Return
  Future<String> syncSalesReturn(Map<String, dynamic> creditNoteJson) async {
    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.post('/creditnotes', data: creditNoteJson);
        if (response.statusCode == 201 || response.statusCode == 200) {
          return response.data['creditnote']['creditnote_id'];
        }
      } catch (e) {
        throw Exception('Zoho Books Credit Note Sync Failed: $e');
      }
    }

    // Mock response
    await Future.delayed(const Duration(seconds: 1));
    return 'zoho_cred_${DateTime.now().millisecondsSinceEpoch}';
  }

  // 8. Zoho Books Expenses API: Sync Expense Entry
  Future<String> syncExpense(Map<String, dynamic> expenseJson) async {
    if (!_isMockMode() && !_mockTransactions) {
      try {
        // Multi-part formatting in case a receipt image exists
        final receiptPath = expenseJson['receiptImagePath'];
        dynamic dataPayload;
        
        if (receiptPath != null && receiptPath.isNotEmpty) {
          dataPayload = FormData.fromMap({
            'JSONString': jsonEncode(expenseJson),
            'attachment': await MultipartFile.fromFile(receiptPath, filename: 'receipt.jpg'),
          });
        } else {
          dataPayload = expenseJson;
        }

        final response = await _dio.post('/expenses', data: dataPayload);
        if (response.statusCode == 201 || response.statusCode == 200) {
          return response.data['expense']['expense_id'];
        }
      } catch (e) {
        throw Exception('Zoho Books Expense Sync Failed: $e');
      }
    }

    // Mock response
    await Future.delayed(const Duration(seconds: 1));
    return 'zoho_exp_${DateTime.now().millisecondsSinceEpoch}';
  }

  // --- Master Data Fetchers ---

  // 9. Warehouses (GET /settings/warehouses)
  Future<List<Map<String, dynamic>>> fetchWarehouses() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get('/settings/warehouses');
        if (response.statusCode == 200) {
          final list = (response.data['warehouses'] as List? ?? []);
          return list.map((w) => Map<String, dynamic>.from(w)).toList();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Zoho fetchWarehouses error: $e');
      }
      return const [];
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {
        'warehouse_id': 'van_wh_01',
        'warehouse_name': 'Van Warehouse 01',
        'address': 'Mobile / On-route',
        'is_primary': true,
      },
    ];
  }

  // 10. Payment Accounts (GET /bankaccounts — bank + cash accounts for receipts)
  Future<List<Map<String, dynamic>>> fetchPaymentAccounts() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get('/bankaccounts');
        if (response.statusCode == 200) {
          final list = (response.data['bankaccounts'] as List? ?? []);
          return list.map((a) => Map<String, dynamic>.from(a)).toList();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Zoho fetchPaymentAccounts error: $e');
      }
      return const [];
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {
        'account_id': 'acc_cash',
        'account_name': 'Petty Cash',
        'account_type': 'cash',
        'currency_code': 'INR',
        'payment_mode': 'Cash',
      },
      {
        'account_id': 'acc_bank',
        'account_name': 'HDFC Current',
        'account_type': 'bank',
        'currency_code': 'INR',
        'payment_mode': 'Bank Transfer',
      },
    ];
  }

  // 11. Taxes (GET /settings/taxes)
  Future<List<Map<String, dynamic>>> fetchTaxes() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get('/settings/taxes');
        if (response.statusCode == 200) {
          final list = (response.data['taxes'] as List? ?? []);
          return list.map((t) => Map<String, dynamic>.from(t)).toList();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Zoho fetchTaxes error: $e');
      }
      return const [];
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {'tax_id': 'tax_5',  'tax_name': 'GST 5%',  'tax_percentage': 5.0,  'tax_type': 'tax', 'is_default_tax': true},
      {'tax_id': 'tax_12', 'tax_name': 'GST 12%', 'tax_percentage': 12.0, 'tax_type': 'tax'},
      {'tax_id': 'tax_18', 'tax_name': 'GST 18%', 'tax_percentage': 18.0, 'tax_type': 'tax'},
    ];
  }

  // 12. Expense Accounts (GET /chartofaccounts?filter_by=AccountType.Expense)
  Future<List<Map<String, dynamic>>> fetchExpenseAccounts() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get(
          '/chartofaccounts',
          queryParameters: {'filter_by': 'AccountType.Expense'},
        );
        if (response.statusCode == 200) {
          final list = (response.data['chartofaccounts'] as List? ?? []);
          return list.map((a) => Map<String, dynamic>.from(a)).toList();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Zoho fetchExpenseAccounts error: $e');
      }
      return const [];
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {'account_id': 'exp_fuel',  'account_name': 'Fuel Expense',        'account_code': 'EXP-FUEL',  'category': 'Fuel'},
      {'account_id': 'exp_toll',  'account_name': 'Tolls & Parking',     'account_code': 'EXP-TOLL',  'category': 'Tolls'},
      {'account_id': 'exp_meal',  'account_name': 'Meals & Refreshments','account_code': 'EXP-MEAL',  'category': 'Meals'},
      {'account_id': 'exp_maint', 'account_name': 'Vehicle Maintenance', 'account_code': 'EXP-MAINT', 'category': 'Maintenance'},
      {'account_id': 'exp_misc',  'account_name': 'Miscellaneous',       'account_code': 'EXP-MISC',  'category': 'Miscellaneous'},
    ];
  }

  // 13. Organization (GET /organizations/{org_id})
  Future<Map<String, dynamic>?> fetchOrganization() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get('/organizations/$_organizationId');
        if (response.statusCode == 200) {
          final org = response.data['organization'];
          if (org != null) return Map<String, dynamic>.from(org);
        }
      } catch (e) {
        // ignore: avoid_print
        print('Zoho fetchOrganization error: $e');
      }
      return null;
    }

    await Future.delayed(const Duration(milliseconds: 250));
    return {
      'organization_id': _organizationId,
      'name': 'Mock Org',
      'currency_code': 'INR',
      'currency_symbol': '₹',
      'fiscal_year_start_month': 'april',
      'time_zone': 'Asia/Kolkata',
    };
  }

  // 14. Open Invoices (GET /invoices?status=unpaid) — for receipt allocation
  Future<List<Map<String, dynamic>>> fetchOpenInvoices() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get(
          '/invoices',
          queryParameters: {
            'status': 'unpaid',
            'per_page': 200,
          },
        );
        if (response.statusCode == 200) {
          final list = (response.data['invoices'] as List? ?? []);
          return list.map((i) => Map<String, dynamic>.from(i)).toList();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Zoho fetchOpenInvoices error: $e');
      }
      return const [];
    }

    await Future.delayed(const Duration(milliseconds: 300));
    final now = DateTime.now();
    return [
      {
        'invoice_id': 'inv_001',
        'invoice_number': 'INV-001',
        'customer_id': 'cust_101',
        'date': now.subtract(const Duration(days: 20)).toIso8601String(),
        'due_date': now.add(const Duration(days: 10)).toIso8601String(),
        'total': 2850.00,
        'balance': 2850.00,
        'status': 'unpaid',
      },
    ];
  }
}
