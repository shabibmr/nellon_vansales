/// Static Zoho-shaped fixture datasets used by [ZohoMockCatalog] when the
/// Dio mock transport short-circuits network calls.
///
/// Shapes match what live Zoho parsers in [ZohoApiClient] already consume
/// (list envelopes with plural keys + `page_context`, detail envelopes with
/// singular resource keys). Extra app-only fields (e.g. `route_id`) are kept
/// where the offline UI depends on them; Zoho would ignore them on write.
class ZohoMockFixtures {
  ZohoMockFixtures._();

  static Map<String, dynamic> pageContext({bool hasMore = false}) => {
        'page': 1,
        'per_page': 200,
        'has_more_page': hasMore,
      };

  static List<Map<String, dynamic>> get customers => [
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
          'cf_latitude': 12.9716,
          'cf_longitude': 77.5946,
          'opening_balance_amount': 0.0,
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
          'opening_balance_amount': 0.0,
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
          'opening_balance_amount': 0.0,
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
          'opening_balance_amount': 0.0,
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
          'opening_balance_amount': 0.0,
        },
      ];

  static List<Map<String, dynamic>> get items => [
        {
          'item_id': 'item_501',
          'name': 'Premium Fresh Milk (1L)',
          'sku': 'MILK-PREM-1L',
          'rate': 60.00,
          'stock_on_hand': 120,
          'description': 'Homogenized Pasteurised Whole Milk',
          'tax_name': 'VAT 5%',
          'tax_percentage': 5.0,
          'unit': 'pcs',
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
          'unit': 'pack',
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
          'unit': 'pcs',
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
          'unit': 'pcs',
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
          'unit': 'loaf',
        },
      ];

  /// Demo `unit_conversions` keyed by `item_id`, so mock/demo mode can exercise
  /// the multi-UOM dropdown. Only a couple of items carry alternates; the rest
  /// resolve to base-unit-only. Keys mirror the Zoho item-detail response.
  static const Map<String, List<Map<String, dynamic>>> _itemUnitConversions = {
    'item_501': [
      {
        'unit_conversion_id': 'uc_501_case',
        'target_unit_id': 'tu_case12',
        'target_unit': 'Case (12)',
        'conversion_rate': 12,
        'quantity_decimal_place': 0,
      },
    ],
    'item_504': [
      {
        'unit_conversion_id': 'uc_504_block',
        'target_unit_id': 'tu_5kg',
        'target_unit': '5 Kg Block',
        'conversion_rate': 25,
        'quantity_decimal_place': 2,
      },
    ],
  };

  /// Single item detail (`GET /items/{id}`) — the list endpoint omits
  /// `unit_conversions`, so multi-UOM data is only served here (mirrors live).
  static Map<String, dynamic> itemDetail(String id) {
    final base = items.firstWhere(
      (i) => i['item_id'] == id,
      orElse: () => {'item_id': id, 'name': id, 'unit': 'pcs'},
    );
    return {
      ...base,
      'unit_conversions': _itemUnitConversions[id] ?? const [],
    };
  }

  static List<Map<String, dynamic>> salesOrders() {
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

  static List<Map<String, dynamic>> get locations => [
        {
          'location_id': 'van_wh_01',
          'location_name': 'Van Warehouse 01',
          'address': 'Mobile / On-route',
          'is_primary_location': true,
        },
      ];

  static List<Map<String, dynamic>> get salespersons => [
        {
          'salesperson_id': 'sp_mock_01',
          'salesperson_name': 'Mock Sales Agent',
          'salesperson_email': 'agent@example.com',
          'status': 'active',
        },
      ];

  // Phone-login profile module (`cm_salesperson_profile`). Records list as
  // `status: draft` in real Zoho — the app must never filter by record
  // status, only `cf_active` (see ZOHO_PHONE_LOGIN_DESIGN.md B2).
  static List<Map<String, dynamic>> get salespersonProfiles => [
        {
          'record_name': '+971500000001',
          'cf_salesperson': 'sp_mock_01',
          'cf_salesperson_formatted': 'Mock Sales Agent',
          'cf_van_location': 'van_wh_01',
          'cf_van_location_formatted': 'Van Warehouse 01',
          'cf_cash_account': 'acc_cash',
          'cf_cash_account_formatted': 'Petty Cash',
          'cf_series_prefix': 'MOCK-',
          'cf_active': true,
          'status': 'draft',
        },
        {
          // No cf_van_location -> exercises orders-only login mode.
          'record_name': '+971500000002',
          'cf_salesperson': 'sp_mock_01',
          'cf_salesperson_formatted': 'Mock Sales Agent',
          'cf_cash_account': 'acc_cash',
          'cf_cash_account_formatted': 'Petty Cash',
          'cf_series_prefix': 'ORD-',
          'cf_active': true,
          'status': 'draft',
        },
      ];

  static List<Map<String, dynamic>> get bankAccounts => [
        {
          'account_id': 'acc_cash',
          'account_name': 'Petty Cash',
          'account_type': 'cash',
          'currency_code': 'AED',
          'payment_mode': 'Cash',
        },
        {
          'account_id': 'acc_bank',
          'account_name': 'HDFC Current',
          'account_type': 'bank',
          'currency_code': 'AED',
          'payment_mode': 'Bank Transfer',
        },
      ];

  static List<Map<String, dynamic>> get taxes => [
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

  static List<Map<String, dynamic>> get expenseAccounts => [
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
          'account_id': 'exp_maint',
          'account_name': 'Vehicle Maintenance',
          'account_code': 'EXP-MAINT',
          'category': 'Maintenance',
        },
        {
          'account_id': 'exp_parking',
          'account_name': 'Parking fee',
          'account_code': 'EXP-PARK',
          'category': 'Parking fee',
        },
      ];

  static Map<String, dynamic> organization(String organizationId) => {
        'organization_id': organizationId,
        'name': 'Mock Org',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
        'fiscal_year_start_month': 'april',
        'time_zone': 'Asia/Kolkata',
      };

  static List<Map<String, dynamic>> openInvoices() {
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
      // Overdue and partially-paid invoices exercise the fix for the bug
      // where `status=unpaid`-only fetches silently dropped these.
      {
        'invoice_id': 'inv_002',
        'invoice_number': 'INV-002',
        'customer_id': 'cust_101',
        'date': now.subtract(const Duration(days: 60)).toIso8601String(),
        'due_date': now.subtract(const Duration(days: 30)).toIso8601String(),
        'total': 1200.00,
        'balance': 1200.00,
        'status': 'overdue',
      },
      {
        'invoice_id': 'inv_003',
        'invoice_number': 'INV-003',
        'customer_id': 'cust_101',
        'date': now.subtract(const Duration(days: 15)).toIso8601String(),
        'due_date': now.add(const Duration(days: 15)).toIso8601String(),
        'total': 900.00,
        'balance': 400.00,
        'status': 'partially_paid',
      },
    ];
  }

  static List<Map<String, dynamic>> invoicesWithLines() {
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
        'due_date':
            now.add(const Duration(days: 27)).toIso8601String().split('T')[0],
        'notes': '',
        'total': 2400.0,
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
        'due_date':
            now.add(const Duration(days: 29)).toIso8601String().split('T')[0],
        'notes': '',
        'total': 2880.0,
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

  static List<Map<String, dynamic>> expensesWithLines() {
    final now = DateTime.now();
    return [
      {
        'expense_id': 'exp_9001',
        'date': now
            .subtract(const Duration(days: 2))
            .toIso8601String()
            .split('T')[0],
        'total': 850.0,
        // Session mock cash ledger (`cf_cash_account` → acc_cash).
        'paid_through_account_id': 'acc_cash',
        'line_items': [
          {'account_name': 'Fuel', 'amount': 600.0, 'description': 'Diesel'},
          {
            'account_name': 'Tolls',
            'amount': 250.0,
            'description': 'Highway toll',
          },
        ],
      },
      {
        'expense_id': 'exp_9002',
        'date': now
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .split('T')[0],
        'total': 300.0,
        'paid_through_account_id': 'acc_cash',
        'line_items': [
          {
            'account_name': 'Parking fee',
            'amount': 300.0,
            'description': 'Mall parking',
          },
        ],
      },
    ];
  }

  static List<Map<String, dynamic>> receipts() {
    final now = DateTime.now();
    return [
      {
        'payment_id': 'pay_9001',
        'payment_number': 'PAY-00001',
        'customer_id': 'cust_101',
        'customer_name': 'Metro Hypermarket',
        'date':
            now.subtract(const Duration(days: 1)).toIso8601String().split('T')[0],
        'amount': 2850.00,
        'payment_mode': 'Cash',
        // App series number (B4) — list filter uses reference_number_startswith.
        'reference_number': 'MOCK-RCT-00001',
        'invoices': [
          {
            'invoice_id': 'inv_9001',
            'invoice_number': 'INV-00001',
            'amount_applied': 2850.00,
          },
        ],
      },
    ];
  }

  static List<Map<String, dynamic>> creditNotes() {
    final now = DateTime.now();
    return [
      {
        'creditnote_id': 'cn_9001',
        'creditnote_number': 'CN-00001',
        'customer_id': 'cust_101',
        'customer_name': 'Metro Hypermarket',
        'date': now
            .subtract(const Duration(days: 2))
            .toIso8601String()
            .split('T')[0],
        'total': 120.0,
        'reason': 'Damaged goods',
        'line_items': [
          {
            'item_id': 'item_501',
            'name': 'Premium Fresh Milk (1L)',
            'sku': 'MLK-1L',
            'quantity': 2,
            'returned_quantity': 2,
            'rate': 60.00,
            'tax_percentage': 5.0,
            'discount': 0.0,
          },
        ],
      },
    ];
  }

  static Map<String, dynamic> invoiceDetail(String invoiceId) {
    final fromList = invoicesWithLines().where(
      (i) => i['invoice_id'] == invoiceId,
    );
    if (fromList.isNotEmpty) return Map<String, dynamic>.from(fromList.first);

    final now = DateTime.now();
    return {
      'invoice_id': invoiceId,
      'invoice_number':
          invoiceId.startsWith('tx_') ? 'INV-2024-001' : 'INV-00001',
      'customer_id': 'cust_101',
      'customer_name': 'Demo Customer',
      'date':
          now.subtract(const Duration(days: 3)).toIso8601String().split('T')[0],
      'due_date':
          now.add(const Duration(days: 27)).toIso8601String().split('T')[0],
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
      ],
    };
  }

  static Map<String, dynamic> expenseDetail(String expenseId) {
    final fromList = expensesWithLines().where(
      (e) => e['expense_id'] == expenseId,
    );
    if (fromList.isNotEmpty) return Map<String, dynamic>.from(fromList.first);
    return {
      'expense_id': expenseId,
      'date': DateTime.now().toIso8601String().split('T')[0],
      'total': 0.0,
      'line_items': <Map<String, dynamic>>[],
    };
  }

  static Map<String, dynamic> paymentDetail(String paymentId) {
    final fromList = receipts().where((p) => p['payment_id'] == paymentId);
    if (fromList.isNotEmpty) return Map<String, dynamic>.from(fromList.first);

    final now = DateTime.now();
    return {
      'payment_id': paymentId,
      'payment_number':
          paymentId.startsWith('tx_') ? 'PAY-2024-001' : 'PAY-00001',
      'customer_id': 'cust_101',
      'customer_name': 'Demo Customer',
      'date':
          now.subtract(const Duration(days: 1)).toIso8601String().split('T')[0],
      'amount': 2000.00,
      'payment_mode': 'Cash',
      'reference_number': 'MOCK-RCT-00099',
      'invoices': [
        {
          'invoice_id': 'inv_001',
          'invoice_number': 'INV-2024-001',
          'amount_applied': 2000.00,
        },
      ],
    };
  }

  static Map<String, dynamic> creditNoteDetail(String creditNoteId) {
    final fromList = creditNotes().where(
      (c) => c['creditnote_id'] == creditNoteId,
    );
    if (fromList.isNotEmpty) return Map<String, dynamic>.from(fromList.first);

    final now = DateTime.now();
    return {
      'creditnote_id': creditNoteId,
      'creditnote_number':
          creditNoteId.startsWith('tx_') ? 'CN-2024-001' : 'CN-00001',
      'customer_id': 'cust_101',
      'customer_name': 'Demo Customer',
      'date':
          now.subtract(const Duration(days: 2)).toIso8601String().split('T')[0],
      'reason': 'Sales Return',
      'total': 120.0,
      'line_items': [
        {
          'item_id': 'item_501',
          'name': 'Premium Fresh Milk (1L)',
          'sku': 'MLK-1L',
          'quantity': 2,
          'returned_quantity': 2,
          'rate': 60.00,
          'tax_percentage': 5.0,
          'discount': 0.0,
        },
      ],
    };
  }

  static Map<String, dynamic> salesOrderDetail(String salesOrderId) {
    final fromList = salesOrders().where(
      (o) => o['salesorder_id'] == salesOrderId,
    );
    if (fromList.isNotEmpty) return Map<String, dynamic>.from(fromList.first);
    return Map<String, dynamic>.from(salesOrders().first)
      ..['salesorder_id'] = salesOrderId;
  }

  static Map<String, dynamic> contactDetail(String contactId) {
    final fromList = customers.where((c) => c['contact_id'] == contactId);
    if (fromList.isNotEmpty) return Map<String, dynamic>.from(fromList.first);
    return {
      'contact_id': contactId,
      'contact_name': 'Demo Customer',
      'company_name': 'Demo Customer',
      'opening_balance_amount': 5000.0,
    };
  }
}
