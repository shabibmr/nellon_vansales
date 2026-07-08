import 'dart:convert';
import 'package:dio/dio.dart';
import 'app_logger.dart';
import 'hive_database_service.dart';
import 'zoho_payload_mapper.dart';

/// REST API Client that coordinates direct HTTPS calls to Zoho Books v3 APIs.
///
/// Implements standard JSON mappings, handles Zoho OAuth 2.0 access token self-refreshing retries,
/// and includes simulated sandbox datasets when running in mock credential modes.
class ZohoApiClient {
  final Dio _dio = Dio();
  final HiveDatabaseService _dbService;

  // Zoho OAuth 2.0 credentials (read from secure build configurations or environments in production)
  final String _accountsUrl = 'https://accounts.zoho.com/oauth/v2/token';
  final String _apiUrl = 'https://www.zohoapis.com/books/v3';

  /// Zoho **Inventory** API base. Transfer Orders (stock transfers between
  /// locations) live here, NOT under Books v3 — posting to an absolute URL off
  /// this base overrides Dio's `baseUrl` while still running the auth/org-id
  /// request interceptor. Requires the OAuth refresh token to carry the
  /// `ZohoInventory.transferorders.CREATE` scope and Inventory to be enabled on
  /// the organization.
  final String _inventoryApiUrl = 'https://www.zohoapis.com/inventory/v1';

  String _clientId = '1000.45EI6FPO004OW9W6BTB7TUJ9L0C0YP';
  String _clientSecret = '1d829f7ee3e1eb7debe6ed370ccc87ab45e7b36103';
  String _refreshToken =
      '1000.ccb7c895a473ba5569c55565c0aed87d.c2f3a5530356193d39a19c511efed856';
  final String _organizationId = '783019958';

  /// Updates Zoho OAuth integration credentials on the fly (called upon loading server config).
  void updateCredentials({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) {
    _clientId = clientId;
    _clientSecret = clientSecret;
    _refreshToken = refreshToken;
  }

  /// Runtime toggle for mocking transaction uploads (invoices, receipts, returns,
  /// expenses) against a sandbox, preserving live connections for master downloads.
  /// Set via [updateMockFlags], sourced from the remote `ServerConfig` — this used
  /// to be a compile-time `static const` requiring a rebuild to flip.
  bool _mockTransactions = true;

  /// Sales Order uploads (create / update / convert) use this flag instead of
  /// [_mockTransactions], so they can be pushed live to Zoho independently of all
  /// other transaction types. Still requires real credentials (`!_isMockMode()`).
  bool _mockSalesOrderTransactions = false;

  /// Stock Transfer uploads (Issue to Van / Stock Unloading) use this flag
  /// instead of [_mockTransactions], mirroring [_mockSalesOrderTransactions].
  /// Still requires real credentials (`!_isMockMode()`).
  bool _mockStockTransfers = true;

  /// Updates the runtime mock-mode flags for transactions, sales orders, and
  /// stock transfers (called upon loading server config, alongside [updateCredentials]).
  void updateMockFlags({
    required bool mockTransactions,
    required bool mockSalesOrderTransactions,
    required bool mockStockTransfers,
  }) {
    _mockTransactions = mockTransactions;
    _mockSalesOrderTransactions = mockSalesOrderTransactions;
    _mockStockTransfers = mockStockTransfers;
  }

  /// True when every transaction type is being simulated rather than pushed live.
  bool get isMockModeEnabled =>
      _mockTransactions &&
      _mockSalesOrderTransactions &&
      _mockStockTransfers;

  /// Flips all transaction mock flags together (mock on = all true, live = all false).
  void setAllMockFlags(bool enabled) {
    updateMockFlags(
      mockTransactions: enabled,
      mockSalesOrderTransactions: enabled,
      mockStockTransfers: enabled,
    );
  }

  /// True when OAuth credentials are still placeholder templates.
  bool get usesPlaceholderCredentials => _isMockMode();

  /// Instantiates a new [ZohoApiClient].
  ///
  /// Configures connect/receive timeouts and sets up a robust interceptor to:
  /// - Automatically inject active Zoho OAuth header strings (`Zoho-oauthtoken <token>`).
  /// - Intercept `401 Unauthorized` responses and trigger transparent token-refresh workflows.
  /// - Re-execute the original request with the fresh token without user interruption.
  ZohoApiClient({required this._dbService}) {
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
              requestOptions.headers['Authorization'] =
                  'Zoho-oauthtoken $newAccessToken';

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

  /// Returns true if the client credentials remain the placeholder templates (forcing mock behavior).
  bool _isMockMode() {
    // Falls back to mock mode if credentials are still placeholder templates
    return _clientId.contains('YOUR_CLIENT_ID');
  }

  /// True if any transaction type (invoices, receipts, returns, expenses, or
  /// sales orders) is currently being simulated against a sandbox rather than
  /// pushed live to Zoho — whether due to placeholder credentials or a mock flag.
  bool get isAnyMockModeActive =>
      _isMockMode() ||
      _mockTransactions ||
      _mockSalesOrderTransactions ||
      _mockStockTransfers;

  // --- OAuth 2.0 Handlers ---

  /// Fetches the cached OAuth access token or triggers a refresh workflow if expired.
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

  /// Standard OAuth refresh execution block that obtains a fresh access token from Zoho Accounts.
  Future<String?> _refreshAccessToken({bool force = false}) async {
    if (_isMockMode()) return 'mock_access_token';

    final refreshToken = _refreshToken;
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
        final expiryMillis =
            DateTime.now().millisecondsSinceEpoch + (expiresInSeconds * 1000);

        // Save newAccessToken and expire_in to local database
        await _dbService.setOauthAccessToken(newAccessToken);
        await _dbService.setOauthTokenExpiry(expiryMillis);

        return newAccessToken;
      }
    } catch (e) {
      AppLogger.error('ZohoApi', 'OAuth Refresh Error: $e');
    }
    return null;
  }

  // --- Generic helpers ---

  /// Fetches all pages from a Zoho list endpoint. Returns a single flat list of records.
  /// The records are read from the first list-valued key in the response payload
  /// (e.g. `invoices`, `customerpayments`, `creditnotes`).
  Future<List<Map<String, dynamic>>> _fetchAllPages(
    String path,
    Map<String, dynamic> baseParams,
  ) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final params = <String, dynamic>{
        ...baseParams,
        'per_page': 200,
        'page': page,
      };
      final response = await _dio.get(path, queryParameters: params);
      if (response.statusCode != 200) {
        throw Exception('GET $path failed: ${response.statusCode}');
      }
      final data = response.data as Map<String, dynamic>;
      List<dynamic>? listVal;
      for (final v in data.values) {
        if (v is List) {
          listVal = v;
          break;
        }
      }
      if (listVal != null) {
        all.addAll(listVal.map((e) => Map<String, dynamic>.from(e as Map)));
      }
      final pageContext = data['page_context'] as Map?;
      final hasMore = pageContext?['has_more_page'] == true;
      if (!hasMore) break;
      page += 1;
    }
    return all;
  }

  /// Fetches a single contact detail record (needed for opening_balance_amount).
  Future<Map<String, dynamic>> _fetchContactDetail(String contactId) async {
    final response = await _dio.get('/contacts/$contactId');
    if (response.statusCode != 200) {
      throw Exception(
        'GET /contacts/$contactId failed: ${response.statusCode}',
      );
    }
    return Map<String, dynamic>.from(response.data['contact'] ?? {});
  }

  // --- Zoho Books REST APIs ---

  // 1. Fetch Routes (Simulated since Zoho Books doesn't have a native Route entity, we map to custom Contact Fields)
  Future<List<Map<String, dynamic>>> fetchRoutes() async {
    await Future.delayed(
      const Duration(milliseconds: 600),
    ); // Network latency simulator

    return [
      {
        'id': 'route_north',
        'name': 'North Downtown Sequence',
        'description': 'Servicing supermarkets in the Northern metro corridor',
      },
      {
        'id': 'route_south',
        'name': 'South Retail Hub',
        'description': 'Main shopping sequence along Southern high street',
      },
      {
        'id': 'route_east',
        'name': 'East Coastal Markets',
        'description': 'General stores and bakeries in the Eastern bay area',
      },
    ];
  }

  // 2. Fetch All Customers
  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    if (!_isMockMode()) {
      try {
        return await _fetchAllPages('/contacts', {'contact_type': 'customer'});
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchCustomers error: $e');
        throw Exception('Failed to fetch customers from Zoho: $e');
      }
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
        'sequence': 1,
        // Sample GPS (for testing GPS location feature)
        'cf_latitude': 12.9716,
        'cf_longitude': 77.5946,
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
        'sequence': 2,
        'latitude': 12.9720,
        'longitude': 77.5950,
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
        'sequence': 3,
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
        'sequence': 1,
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
        'sequence': 2,
      },
    ];

    return allCustomers;
  }

  // 3. Fetch Items in Van Warehouse (Zoho Books Locations API)
  Future<List<Map<String, dynamic>>> fetchItems(String warehouseId) async {
    if (!_isMockMode()) {
      try {
        final queryParams = <String, dynamic>{};
        // Only query by location_id if it is a real numeric Zoho location ID (not empty or mock prefix)
        if (warehouseId.isNotEmpty &&
            !warehouseId.startsWith('van_wh_') &&
            RegExp(r'^\d+$').hasMatch(warehouseId)) {
          queryParams['location_id'] = warehouseId;
        }

        return await _fetchAllPages('/items', queryParams);
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchItems error: $e');
        throw Exception('Failed to fetch items from Zoho: $e');
      }
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
        'tax_name': 'VAT 5%',
        'tax_percentage': 5.0,
      },
      {
        'item_id': 'item_502',
        'name': 'Double Choc Cookies (250g)',
        'sku': 'COOK-DCHOC-250G',
        'rate': 120.00,
        'stock_on_hand': 45,
        'description': 'Baked chocolate cookies with premium chips',
        'tax_name': 'VAT 12%',
        'tax_percentage': 12.0,
      },
      {
        'item_id': 'item_503',
        'name': 'Mineral Spring Water (500ml)',
        'sku': 'WATR-SPR-500ML',
        'rate': 20.00,
        'stock_on_hand': 200,
        'description': 'Naturally filtered pure spring water',
        'tax_name': 'VAT 18%',
        'tax_percentage': 18.0,
      },
      {
        'item_id': 'item_504',
        'name': 'Organic Cheddar Cheese (200g)',
        'sku': 'CHSE-CHED-200G',
        'rate': 240.00,
        'stock_on_hand': 30,
        'description': 'Aged sharp premium cheddar block',
        'tax_name': 'VAT 5%',
        'tax_percentage': 5.0,
      },
      {
        'item_id': 'item_505',
        'name': 'Whole Wheat Sourdough Bread',
        'sku': 'BRED-WHEAT-SOUR',
        'rate': 90.00,
        'stock_on_hand': 15,
        'description': 'Artisanal high-fiber wheat sourdough loaf',
        'tax_name': 'VAT 5%',
        'tax_percentage': 5.0,
      },
    ];
  }

  Map<String, dynamic> _injectLocationIdIfNeeded(Map<String, dynamic> json) {
    final activeLocationId = _dbService.assignedWarehouseId;
    if (activeLocationId != null &&
        activeLocationId.isNotEmpty &&
        !activeLocationId.startsWith('van_wh_') &&
        RegExp(r'^\d+$').hasMatch(activeLocationId)) {
      final updatedJson = Map<String, dynamic>.from(json);
      if (updatedJson['location_id'] == null) {
        updatedJson['location_id'] = activeLocationId;
      }
      return updatedJson;
    }
    return json;
  }

  // 4. Zoho Books Contacts API: Sync New Customer
  Future<String> syncCustomer(Map<String, dynamic> customerJson) async {
    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.post(
          '/contacts',
          data: ZohoPayloadMapper.zohoContactPayload(customerJson),
        );
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

  /// Update GPS (latitude/longitude) custom fields on an existing Zoho contact.
  ///
  /// Uses PUT /contacts/{contactId} sending only the custom_fields array to minimize
  /// risk of overwriting other fields. Works for both live and (simulated) mock modes.
  /// Returns the contact_id on success.
  Future<String> updateCustomerGps(
    String contactId,
    double latitude,
    double longitude,
  ) async {
    final payload = {
      'custom_fields': [
        {'api_name': 'cf_latitude', 'value': latitude.toString()},
        {'api_name': 'cf_longitude', 'value': longitude.toString()},
      ],
    };

    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.put('/contacts/$contactId', data: payload);
        if (response.statusCode == 200 || response.statusCode == 201) {
          final returnedId =
              response.data['contact']?['contact_id']?.toString() ?? contactId;
          return returnedId;
        }
      } catch (e) {
        throw Exception('Zoho Books Customer GPS Update Failed: $e');
      }
    }

    // Mock response (simulates immediate success for GPS enrichment)
    await Future.delayed(const Duration(milliseconds: 400));
    return contactId;
  }

  // 5. Zoho Books Invoices API: Sync Sales Invoice
  Future<String> syncInvoice(Map<String, dynamic> invoiceJson) async {
    invoiceJson = _injectLocationIdIfNeeded(invoiceJson);
    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.post(
          '/invoices',
          data: ZohoPayloadMapper.zohoInvoicePayload(invoiceJson),
        );
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

  // 5b. Zoho Books Sales Orders API: Sync Sales Order
  Future<String> syncSalesOrder(Map<String, dynamic> salesOrderJson) async {
    salesOrderJson = _injectLocationIdIfNeeded(salesOrderJson);
    if (!_isMockMode() && !_mockSalesOrderTransactions) {
      try {
        final response = await _dio.post(
          '/salesorders',
          data: ZohoPayloadMapper.zohoSalesOrderPayload(salesOrderJson),
        );
        if (response.statusCode == 201 || response.statusCode == 200) {
          return response.data['salesorder']['salesorder_id'];
        }
      } catch (e) {
        throw Exception('Zoho Books Sales Order Sync Failed: $e');
      }
    }

    // Mock response
    await Future.delayed(const Duration(seconds: 1));
    return 'zoho_so_${DateTime.now().millisecondsSinceEpoch}';
  }

  // 5c. Zoho Books Sales Orders API: Convert a Sales Order to an Invoice.
  //
  // Atomically creates the invoice in Zoho AND flips the sales order status to
  // "invoiced". Requires the permanent Zoho [salesOrderId]. An empty body
  // converts the whole order. Returns the new invoice's `invoice_id`.
  Future<String> convertSalesOrderToInvoice(
    String salesOrderId, [
    Map<String, dynamic>? body,
  ]) async {
    if (body != null) {
      body = _injectLocationIdIfNeeded(body);
    }
    if (!_isMockMode() && !_mockSalesOrderTransactions) {
      try {
        final response = await _dio.post(
          '/salesorders/$salesOrderId/converttoinvoice',
          data: body ?? {},
        );
        if (response.statusCode == 201 || response.statusCode == 200) {
          return response.data['invoice']['invoice_id'];
        }
      } catch (e) {
        throw Exception('Zoho Books Sales Order Conversion Failed: $e');
      }
    }

    // Mock response
    await Future.delayed(const Duration(seconds: 1));
    return 'zoho_inv_${DateTime.now().millisecondsSinceEpoch}';
  }

  // 5d. Zoho Books Sales Orders API: List all sales orders (paginated).
  Future<List<Map<String, dynamic>>> fetchSalesOrders() async {
    if (!_isMockMode()) {
      try {
        return await _fetchAllPages('/salesorders', {});
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchSalesOrders error: $e');
        throw Exception('Failed to fetch sales orders from Zoho: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 600));
    final now = DateTime.now();
    return [
      {
        'salesorder_id': 'so_9001',
        'salesorder_number': 'SO-00001',
        'customer_id': 'cust_101',
        'customer_name': 'Metro Hypermarket',
        'date': now
            .subtract(const Duration(days: 3))
            .toIso8601String()
            .split('T')[0],
        'shipment_date': now
            .add(const Duration(days: 4))
            .toIso8601String()
            .split('T')[0],
        'status': 'open',
        'notes': 'Standing weekly order',
        'line_items': [
          {
            'item_id': 'item_501',
            'name': 'Premium Fresh Milk (1L)',
            'quantity': 20,
            'rate': 60.00,
            'tax_percentage': 5.0,
            'discount': 0.0,
          },
          {
            'item_id': 'item_503',
            'name': 'Mineral Spring Water (500ml)',
            'quantity': 50,
            'rate': 20.00,
            'tax_percentage': 18.0,
            'discount': 0.0,
          },
        ],
      },
      {
        'salesorder_id': 'so_9002',
        'salesorder_number': 'SO-00002',
        'customer_id': 'cust_201',
        'customer_name': 'Southside MegaMart',
        'date': now
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .split('T')[0],
        'shipment_date': now
            .add(const Duration(days: 6))
            .toIso8601String()
            .split('T')[0],
        'status': 'invoiced',
        'notes': '',
        'line_items': [
          {
            'item_id': 'item_504',
            'name': 'Organic Cheddar Cheese (200g)',
            'quantity': 10,
            'rate': 240.00,
            'tax_percentage': 5.0,
            'discount': 0.0,
          },
        ],
      },
    ];
  }

  // 5e. Zoho Books Sales Orders API: Read a single sales order by id.
  Future<Map<String, dynamic>> fetchSalesOrder(String salesOrderId) async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get('/salesorders/$salesOrderId');
        if (response.statusCode != 200) {
          throw Exception(
            'GET /salesorders/$salesOrderId failed: ${response.statusCode}',
          );
        }
        return Map<String, dynamic>.from(response.data['salesorder'] ?? {});
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchSalesOrder error: $e');
        throw Exception('Failed to fetch sales order from Zoho: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 400));
    final now = DateTime.now();
    return {
      'salesorder_id': salesOrderId,
      'salesorder_number': 'SO-00001',
      'customer_id': 'cust_101',
      'customer_name': 'Metro Hypermarket',
      'date': now
          .subtract(const Duration(days: 3))
          .toIso8601String()
          .split('T')[0],
      'shipment_date': now
          .add(const Duration(days: 4))
          .toIso8601String()
          .split('T')[0],
      'status': 'open',
      'notes': 'Standing weekly order',
      'line_items': [
        {
          'item_id': 'item_501',
          'name': 'Premium Fresh Milk (1L)',
          'quantity': 20,
          'rate': 60.00,
          'tax_percentage': 5.0,
          'discount': 0.0,
        },
      ],
    };
  }

  // 5f. Zoho Books Sales Orders API: Update an existing sales order.
  Future<String> updateSalesOrder(
    String salesOrderId,
    Map<String, dynamic> payload,
  ) async {
    payload = _injectLocationIdIfNeeded(payload);
    if (!_isMockMode() && !_mockSalesOrderTransactions) {
      try {
        final response = await _dio.put(
          '/salesorders/$salesOrderId',
          data: ZohoPayloadMapper.zohoSalesOrderPayload(payload),
        );
        if (response.statusCode == 200) {
          return response.data['salesorder']['salesorder_id'];
        }
      } catch (e) {
        throw Exception('Zoho Books Sales Order Update Failed: $e');
      }
    }

    // Mock response: echo back the same id.
    await Future.delayed(const Duration(seconds: 1));
    return salesOrderId;
  }

  // 5g. Zoho Books Transfer Orders API: Sync Stock Transfer (Issue to Van / Stock Unloading).
  //
  // Transfers carry explicit from/to location ids in the payload already, so
  // (unlike invoices/orders/receipts) this does NOT run _injectLocationIdIfNeeded.
  Future<String> syncStockTransfer(Map<String, dynamic> transferJson) async {
    if (!_isMockMode() && !_mockStockTransfers) {
      try {
        // Transfer Orders belong to the Zoho Inventory API, not Books v3 — post
        // to the absolute Inventory URL (overrides Dio's Books baseUrl; the
        // interceptor still injects the token + organization_id).
        final response = await _dio.post(
          '$_inventoryApiUrl/transferorders',
          data: ZohoPayloadMapper.zohoStockTransferPayload(transferJson),
        );
        if (response.statusCode == 201 || response.statusCode == 200) {
          return response.data['transfer_order']['transfer_order_id'];
        }
      } catch (e) {
        throw Exception('Zoho Inventory Stock Transfer Sync Failed: $e');
      }
    }

    // Mock response
    await Future.delayed(const Duration(seconds: 1));
    return 'zoho_to_${DateTime.now().millisecondsSinceEpoch}';
  }

  // 6. Zoho Books Customer Payments API: Sync Receipt Voucher
  Future<String> syncReceiptVoucher(Map<String, dynamic> paymentJson) async {
    paymentJson = _injectLocationIdIfNeeded(paymentJson);
    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.post(
          '/customerpayments',
          data: ZohoPayloadMapper.zohoReceiptPayload(paymentJson),
        );
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
    creditNoteJson = _injectLocationIdIfNeeded(creditNoteJson);
    if (!_isMockMode() && !_mockTransactions) {
      try {
        final response = await _dio.post(
          '/creditnotes',
          data: ZohoPayloadMapper.zohoCreditNotePayload(creditNoteJson),
        );
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
    expenseJson = _injectLocationIdIfNeeded(expenseJson);
    if (!_isMockMode() && !_mockTransactions) {
      try {
        // Resolve local category lines into an itemized Zoho expense body with
        // real ledger account IDs and a paid-through (cash) account at the root.
        final zohoExpense = _buildZohoExpensePayload(expenseJson);

        // Multi-part formatting in case a receipt image exists
        final receiptPath = expenseJson['receiptImagePath'];
        dynamic dataPayload;

        if (receiptPath != null && receiptPath.isNotEmpty) {
          dataPayload = FormData.fromMap({
            'JSONString': jsonEncode(zohoExpense),
            'attachment': await MultipartFile.fromFile(
              receiptPath,
              filename: 'receipt.jpg',
            ),
          });
        } else {
          dataPayload = zohoExpense;
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

  /// Resolves a stored expense map (`lines[]` of category/amount/description)
  /// into an itemized Zoho `/expenses` body via [ZohoPayloadMapper].
  ///
  /// Each line's `category` is mapped to a real Zoho expense ledger `account_id`
  /// from the synced expense accounts; `paid_through_account_id` defaults to the
  /// first cash-type payment account (the app has no per-expense payer picker
  /// yet). Throws if the master account lists are empty so the sync-queue item
  /// surfaces as "Needs Attention" rather than sending an invalid payload.
  Map<String, dynamic> _buildZohoExpensePayload(
    Map<String, dynamic> expenseJson,
  ) {
    final expenseAccounts = _dbService.getExpenseAccounts();
    final paymentAccounts = _dbService.getPaymentAccounts();

    if (expenseAccounts.isEmpty) {
      throw Exception(
        'No expense accounts synced — cannot resolve expense ledger account_id.',
      );
    }
    if (paymentAccounts.isEmpty) {
      throw Exception(
        'No payment accounts synced — cannot resolve paid_through_account_id.',
      );
    }

    String accountIdForCategory(String category) {
      final match = expenseAccounts.where((a) => a.category == category);
      return match.isNotEmpty ? match.first.id : expenseAccounts.first.id;
    }

    final cashAccount = paymentAccounts.firstWhere(
      (a) => a.accountType == 'cash',
      orElse: () => paymentAccounts.first,
    );

    final rawLines = (expenseJson['lines'] as List?) ?? const [];
    final resolvedLines = rawLines.whereType<Map>().map((line) {
      final map = Map<String, dynamic>.from(line);
      return <String, dynamic>{
        'account_id': accountIdForCategory(map['category']?.toString() ?? ''),
        'amount': (map['amount'] as num?)?.toDouble() ?? 0.0,
        'description': map['description']?.toString() ?? '',
      };
    }).toList();

    return ZohoPayloadMapper.zohoExpensePayload(
      expenseJson,
      resolvedLines: resolvedLines,
      paidThroughAccountId: cashAccount.id,
    );
  }

  // --- Master Data Fetchers ---

  // 9. Warehouses/Locations (GET /locations)
  Future<List<Map<String, dynamic>>> fetchWarehouses() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get('/locations');
        if (response.statusCode == 200) {
          final list = (response.data['locations'] as List? ?? []);
          return list.map((w) => Map<String, dynamic>.from(w)).toList();
        }
        throw Exception(
          'Failed to fetch locations: Server returned status code ${response.statusCode}',
        );
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchWarehouses (locations) error: $e');
        throw Exception('Failed to fetch locations from Zoho: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {
        'location_id': 'van_wh_01',
        'location_name': 'Van Warehouse 01',
        'address': 'Mobile / On-route',
        'is_primary_location': true,
      },
    ];
  }

  // Salespersons (GET /salespersons)
  Future<List<Map<String, dynamic>>> fetchSalespersons() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get('/salespersons');
        if (response.statusCode == 200) {
          // Zoho returns salespersons under `data` (verified against live API).
          final list =
              (response.data['data'] ?? response.data['salespersons'] ?? [])
                  as List;
          return list.map((s) => Map<String, dynamic>.from(s)).toList();
        }
        throw Exception(
          'Failed to fetch salespersons: Server returned status code ${response.statusCode}',
        );
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchSalespersons error: $e');
        throw Exception('Failed to fetch salespersons from Zoho: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {
        'salesperson_id': 'sp_mock_01',
        'salesperson_name': 'Mock Sales Agent',
        'salesperson_email': 'agent@example.com',
        'status': 'active',
      },
    ];
  }

  // Salesperson-to-Location mapping (GET /cm_salesperson_location — custom module).
  // Zoho auto-generated the module api_name `cm_salesperson_location` and returns
  // records under `module_records`. Each record carries the salesperson email in the
  // module's primary field `record_name` and the mapped location in `cf_location_id`.
  Future<List<Map<String, dynamic>>> fetchSalespersonLocationMappings() async {
    if (!_isMockMode()) {
      try {
        final response = await _dio.get('/cm_salesperson_location');
        if (response.statusCode == 200) {
          final list =
              (response.data['module_records'] ?? response.data['data'] ?? [])
                  as List;
          return list.map((m) => Map<String, dynamic>.from(m)).toList();
        }
        throw Exception(
          'Failed to fetch salesperson location mappings: Server returned status code ${response.statusCode}',
        );
      } catch (e) {
        AppLogger.error(
          'ZohoApi',
          'fetchSalespersonLocationMappings error: $e',
        );
        throw Exception(
          'Failed to fetch salesperson location mappings from Zoho: $e',
        );
      }
    }

    // No sensible mock mapping default; mock-mode logins simply resolve without a location.
    await Future.delayed(const Duration(milliseconds: 300));
    return [];
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
        throw Exception(
          'Failed to fetch payment accounts: Server returned status code ${response.statusCode}',
        );
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchPaymentAccounts error: $e');
        throw Exception('Failed to fetch payment accounts from Zoho: $e');
      }
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
        throw Exception(
          'Failed to fetch taxes: Server returned status code ${response.statusCode}',
        );
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchTaxes error: $e');
        throw Exception('Failed to fetch taxes from Zoho: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {
        'tax_id': 'tax_5',
        'tax_name': 'VAT 5%',
        'tax_percentage': 5.0,
        'tax_type': 'tax',
        'is_default_tax': true,
      },
      {
        'tax_id': 'tax_12',
        'tax_name': 'VAT 12%',
        'tax_percentage': 12.0,
        'tax_type': 'tax',
      },
      {
        'tax_id': 'tax_18',
        'tax_name': 'VAT 18%',
        'tax_percentage': 18.0,
        'tax_type': 'tax',
      },
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
        throw Exception(
          'Failed to fetch expense accounts: Server returned status code ${response.statusCode}',
        );
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchExpenseAccounts error: $e');
        throw Exception('Failed to fetch expense accounts from Zoho: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {
        'account_id': 'exp_fuel',
        'account_name': 'Fuel Expense',
        'account_code': 'EXP-FUEL',
        'category': 'Fuel',
      },
      {
        'account_id': 'exp_toll',
        'account_name': 'Tolls & Parking',
        'account_code': 'EXP-TOLL',
        'category': 'Tolls',
      },
      {
        'account_id': 'exp_meal',
        'account_name': 'Meals & Refreshments',
        'account_code': 'EXP-MEAL',
        'category': 'Meals',
      },
      {
        'account_id': 'exp_maint',
        'account_name': 'Vehicle Maintenance',
        'account_code': 'EXP-MAINT',
        'category': 'Maintenance',
      },
      {
        'account_id': 'exp_misc',
        'account_name': 'Miscellaneous',
        'account_code': 'EXP-MISC',
        'category': 'Miscellaneous',
      },
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
        throw Exception(
          'Failed to fetch organization: Server returned status code ${response.statusCode}',
        );
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchOrganization error: $e');
        throw Exception('Failed to fetch organization from Zoho: $e');
      }
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

  // 14. Customer Statement — composed locally from primary records.
  //
  // Zoho Books does not expose a JSON ledger endpoint. We build it Option-A style:
  //   1) Fetch contact detail (for opening_balance_amount)
  //   2) Fetch all invoices, customer payments, and credit notes for this contact
  //   3) Opening = contact.opening_balance + Σ(invoices before from) − Σ(payments+credit_notes before from)
  //   4) Merge in-period rows, sort by date, compute running balance
  //   5) Return the same JSON shape that CustomerLedger.fromJson consumes
  Future<Map<String, dynamic>> fetchCustomerStatement(
    String contactId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!_isMockMode()) {
      try {
        final from = startDate ?? DateTime(DateTime.now().year, 1, 1);
        final to = endDate ?? DateTime.now();

        final results = await Future.wait([
          _fetchContactDetail(contactId),
          _fetchAllPages('/invoices', {'customer_id': contactId}),
          _fetchAllPages('/customerpayments', {'customer_id': contactId}),
          _fetchAllPages('/creditnotes', {'customer_id': contactId}),
        ]);

        final contact = results[0] as Map<String, dynamic>;
        final invoices = results[1] as List<Map<String, dynamic>>;
        final payments = results[2] as List<Map<String, dynamic>>;
        final creditNotes = results[3] as List<Map<String, dynamic>>;

        final contactName =
            (contact['contact_name'] ?? contact['company_name'] ?? '')
                as String;
        final baseOpening = (contact['opening_balance_amount'] ?? 0).toDouble();

        DateTime parseDate(String? s) =>
            s == null || s.isEmpty ? DateTime(1970) : DateTime.parse(s);

        bool before(DateTime d) =>
            d.isBefore(DateTime(from.year, from.month, from.day));
        bool inRange(DateTime d) {
          final f = DateTime(from.year, from.month, from.day);
          final t = DateTime(to.year, to.month, to.day, 23, 59, 59);
          return !d.isBefore(f) && !d.isAfter(t);
        }

        // Compute opening balance: contact's books-start opening + everything before `from`.
        double opening = baseOpening;
        for (final inv in invoices) {
          final d = parseDate(inv['date'] as String?);
          if (before(d)) opening += (inv['total'] ?? 0).toDouble();
        }
        for (final pay in payments) {
          final d = parseDate(pay['date'] as String?);
          if (before(d)) opening -= (pay['amount'] ?? 0).toDouble();
        }
        for (final cn in creditNotes) {
          final d = parseDate(cn['date'] as String?);
          if (before(d)) opening -= (cn['total'] ?? 0).toDouble();
        }

        // Build in-period rows.
        final rows = <Map<String, dynamic>>[];
        for (final inv in invoices) {
          final d = parseDate(inv['date'] as String?);
          if (!inRange(d)) continue;
          final number = (inv['invoice_number'] ?? '') as String;
          rows.add({
            'transaction_id': inv['invoice_id'] ?? '',
            'transaction_number': number,
            'date': inv['date'],
            'transaction_type': 'invoice',
            'debit': (inv['total'] ?? 0).toDouble(),
            'credit': 0.0,
            'description': 'Sales Invoice $number'.trim(),
            '_sort': d.millisecondsSinceEpoch,
          });
        }
        for (final pay in payments) {
          final d = parseDate(pay['date'] as String?);
          if (!inRange(d)) continue;
          final number = (pay['payment_number'] ?? '') as String;
          final mode = (pay['payment_mode'] ?? '') as String;
          rows.add({
            'transaction_id': pay['payment_id'] ?? '',
            'transaction_number': number,
            'date': pay['date'],
            'transaction_type': 'payment',
            'debit': 0.0,
            'credit': (pay['amount'] ?? 0).toDouble(),
            'description': mode.isEmpty
                ? 'Payment Received'
                : 'Payment Received — $mode',
            '_sort': d.millisecondsSinceEpoch,
          });
        }
        for (final cn in creditNotes) {
          final d = parseDate(cn['date'] as String?);
          if (!inRange(d)) continue;
          final number = (cn['creditnote_number'] ?? '') as String;
          rows.add({
            'transaction_id': cn['creditnote_id'] ?? '',
            'transaction_number': number,
            'date': cn['date'],
            'transaction_type': 'credit_note',
            'debit': 0.0,
            'credit': (cn['total'] ?? 0).toDouble(),
            'description': 'Credit Note $number'.trim(),
            '_sort': d.millisecondsSinceEpoch,
          });
        }

        rows.sort((a, b) => (a['_sort'] as int).compareTo(b['_sort'] as int));

        // Running balance
        double running = opening;
        for (final r in rows) {
          running += (r['debit'] as double) - (r['credit'] as double);
          r['balance'] = running;
          r.remove('_sort');
        }

        return {
          'contact_id': contactId,
          'contact_name': contactName,
          'opening_balance': opening,
          'closing_balance': running,
          'transactions': rows,
        };
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchCustomerStatement error: $e');
        throw Exception('Failed to fetch customer statement from Zoho: $e');
      }
    }

    // Mock data
    await Future.delayed(const Duration(milliseconds: 800));
    final now = DateTime.now();
    final from = startDate ?? now.subtract(const Duration(days: 30));
    return {
      'contact_id': contactId,
      'contact_name': 'Demo Customer',
      'opening_balance': 5000.0,
      'closing_balance': 2350.0,
      'transactions': [
        {
          'transaction_id': 'tx_001',
          'transaction_number': 'INV-2024-001',
          'date': from
              .add(const Duration(days: 2))
              .toIso8601String()
              .split('T')[0],
          'transaction_type': 'invoice',
          'debit': 3500.0,
          'credit': 0.0,
          'balance': 8500.0,
          'description': 'Sales Invoice #INV-2024-001',
        },
        {
          'transaction_id': 'tx_002',
          'transaction_number': 'PAY-2024-001',
          'date': from
              .add(const Duration(days: 5))
              .toIso8601String()
              .split('T')[0],
          'transaction_type': 'payment',
          'debit': 0.0,
          'credit': 2000.0,
          'balance': 6500.0,
          'description': 'Payment Received - Cash',
        },
        {
          'transaction_id': 'tx_003',
          'transaction_number': 'INV-2024-002',
          'date': from
              .add(const Duration(days: 10))
              .toIso8601String()
              .split('T')[0],
          'transaction_type': 'invoice',
          'debit': 1200.0,
          'credit': 0.0,
          'balance': 7700.0,
          'description': 'Sales Invoice #INV-2024-002',
        },
        {
          'transaction_id': 'tx_004',
          'transaction_number': 'PAY-2024-002',
          'date': from
              .add(const Duration(days: 15))
              .toIso8601String()
              .split('T')[0],
          'transaction_type': 'payment',
          'debit': 0.0,
          'credit': 4500.0,
          'balance': 3200.0,
          'description': 'Payment Received - Bank Transfer',
        },
        {
          'transaction_id': 'tx_005',
          'transaction_number': 'CN-2024-001',
          'date': from
              .add(const Duration(days: 20))
              .toIso8601String()
              .split('T')[0],
          'transaction_type': 'credit_note',
          'debit': 0.0,
          'credit': 850.0,
          'balance': 2350.0,
          'description': 'Credit Note - Sales Return',
        },
      ],
    };
  }

  // 15. Open Invoices (GET /invoices?status=unpaid) — for receipt allocation
  Future<List<Map<String, dynamic>>> fetchOpenInvoices() async {
    if (!_isMockMode()) {
      try {
        return await _fetchAllPages('/invoices', {'status': 'unpaid'});
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchOpenInvoices error: $e');
        throw Exception('Failed to fetch open invoices from Zoho: $e');
      }
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

  // 16. Single invoice detail (GET /invoices/{id}) — the list endpoint only
  // returns invoice headers, so line items must be fetched per-invoice.
  Future<Map<String, dynamic>> fetchInvoiceDetail(String invoiceId) async {
    final response = await _dio.get('/invoices/$invoiceId');
    if (response.statusCode != 200) {
      throw Exception(
        'GET /invoices/$invoiceId failed: ${response.statusCode}',
      );
    }
    return Map<String, dynamic>.from(response.data['invoice'] ?? {});
  }

  // 17. Full invoice list with line items — powers the Item Sales Report.
  Future<List<Map<String, dynamic>>> fetchInvoices() async {
    if (!_isMockMode()) {
      try {
        final headers = await _fetchAllPages('/invoices', {});
        final details = <Map<String, dynamic>>[];
        for (final header in headers) {
          final id = header['invoice_id']?.toString();
          if (id == null || id.isEmpty) continue;
          try {
            details.add(await fetchInvoiceDetail(id));
          } catch (e) {
            // Skip invoices whose detail fails to load rather than failing the whole report.
            AppLogger.error('ZohoApi', 'fetchInvoiceDetail($id) error: $e');
          }
        }
        return details;
      } catch (e) {
        AppLogger.error('ZohoApi', 'fetchInvoices error: $e');
        throw Exception('Failed to fetch invoices from Zoho: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 600));
    final now = DateTime.now();
    return [
      {
        'invoice_id': 'inv_9001',
        'invoice_number': 'INV-00001',
        'customer_id': 'cust_101',
        'customer_name': 'Metro Hypermarket',
        'date': now
            .subtract(const Duration(days: 3))
            .toIso8601String()
            .split('T')[0],
        'due_date': now
            .add(const Duration(days: 27))
            .toIso8601String()
            .split('T')[0],
        'notes': '',
        'line_items': [
          {
            'item_id': 'item_501',
            'name': 'Premium Fresh Milk (1L)',
            'sku': 'MLK-1L',
            'quantity': 24,
            'rate': 60.00,
            'tax_percentage': 5.0,
            'discount': 0.0,
          },
          {
            'item_id': 'item_503',
            'name': 'Mineral Spring Water (500ml)',
            'sku': 'WTR-500',
            'quantity': 48,
            'rate': 20.00,
            'tax_percentage': 18.0,
            'discount': 0.0,
          },
        ],
      },
      {
        'invoice_id': 'inv_9002',
        'invoice_number': 'INV-00002',
        'customer_id': 'cust_201',
        'customer_name': 'Southside MegaMart',
        'date': now
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .split('T')[0],
        'due_date': now
            .add(const Duration(days: 29))
            .toIso8601String()
            .split('T')[0],
        'notes': '',
        'line_items': [
          {
            'item_id': 'item_504',
            'name': 'Organic Cheddar Cheese (200g)',
            'sku': 'CHS-200',
            'quantity': 12,
            'rate': 240.00,
            'tax_percentage': 5.0,
            'discount': 0.0,
          },
        ],
      },
    ];
  }
}
