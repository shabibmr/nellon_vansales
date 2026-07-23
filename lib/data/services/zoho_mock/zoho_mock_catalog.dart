import 'package:dio/dio.dart';

import 'zoho_mock_fixtures.dart';
import 'zoho_mock_path.dart';

/// Builds Zoho-shaped [Response] bodies for mocked HTTP requests.
///
/// Records the last [RequestOptions] seen for unit tests (payload inspection).
class ZohoMockCatalog {
  RequestOptions? lastRequest;
  final List<RequestOptions> requestLog = [];

  /// Optional organization id used in org detail responses.
  String organizationId;

  ZohoMockCatalog({this.organizationId = 'mock_org'});

  /// Returns a Dio [Response] for [options], or a 404 envelope if unknown.
  Response<dynamic> buildResponse(RequestOptions options) {
    lastRequest = options;
    requestLog.add(options);

    final method = options.method.toUpperCase();
    final path = ZohoMockPath.normalize(options);

    final match = _match(method, path, options);
    if (match != null) {
      return Response<dynamic>(
        requestOptions: options,
        statusCode: match.statusCode,
        data: match.data,
        statusMessage: match.statusCode >= 400 ? 'Error' : 'OK',
      );
    }

    return Response<dynamic>(
      requestOptions: options,
      statusCode: 404,
      data: {
        'code': 404,
        'message': 'Mock catalog has no handler for $method $path',
      },
      statusMessage: 'Not Found',
    );
  }

  _MockResult? _match(String method, String path, RequestOptions options) {
    // --- Writes ---
    if (method == 'POST' && path == '/contacts') {
      return _MockResult(201, {
        'code': 0,
        'contact': {
          'contact_id': 'zoho_cust_${DateTime.now().millisecondsSinceEpoch}',
        },
      });
    }
    if (method == 'PUT' && _matches(path, r'^/contacts/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'code': 0,
        'contact': {'contact_id': id},
      });
    }
    if (method == 'POST' && path == '/invoices') {
      return _MockResult(201, {
        'code': 0,
        'invoice': {
          'invoice_id': 'zoho_inv_${DateTime.now().millisecondsSinceEpoch}',
        },
      });
    }
    if (method == 'POST' && path == '/salesorders') {
      return _MockResult(201, {
        'code': 0,
        'salesorder': {
          'salesorder_id': 'zoho_so_${DateTime.now().millisecondsSinceEpoch}',
        },
      });
    }
    if (method == 'PUT' && _matches(path, r'^/salesorders/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'code': 0,
        'salesorder': {'salesorder_id': id},
      });
    }
    if (method == 'POST' &&
        _matches(path, r'^/salesorders/[^/]+/converttoinvoice$')) {
      return _MockResult(201, {
        'code': 0,
        'invoice': {
          'invoice_id': 'zoho_inv_${DateTime.now().millisecondsSinceEpoch}',
        },
      });
    }
    if (method == 'POST' && path == '/customerpayments') {
      return _MockResult(201, {
        'code': 0,
        'payment': {
          'payment_id': 'zoho_pay_${DateTime.now().millisecondsSinceEpoch}',
        },
      });
    }
    if (method == 'POST' && path == '/creditnotes') {
      return _MockResult(201, {
        'code': 0,
        'creditnote': {
          'creditnote_id':
              'zoho_cred_${DateTime.now().millisecondsSinceEpoch}',
        },
      });
    }
    if (method == 'POST' && path == '/expenses') {
      return _MockResult(201, {
        'code': 0,
        'expense': {
          'expense_id': 'zoho_exp_${DateTime.now().millisecondsSinceEpoch}',
        },
      });
    }
    if (method == 'POST' && path.endsWith('/transferorders')) {
      return _MockResult(201, {
        'code': 0,
        'transfer_order': {
          'transfer_order_id':
              'zoho_to_${DateTime.now().millisecondsSinceEpoch}',
        },
      });
    }

    // --- Reads ---
    if (method == 'GET' && path == '/contacts') {
      return _MockResult(200, {
        'contacts': ZohoMockFixtures.customers,
        'page_context': ZohoMockFixtures.pageContext(),
      });
    }
    if (method == 'GET' && _matches(path, r'^/contacts/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'contact': ZohoMockFixtures.contactDetail(id),
      });
    }
    if (method == 'GET' && path == '/items') {
      return _MockResult(200, {
        'items': ZohoMockFixtures.items,
        'page_context': ZohoMockFixtures.pageContext(),
      });
    }
    if (method == 'GET' && _matches(path, r'^/items/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'item': ZohoMockFixtures.itemDetail(id),
      });
    }
    if (method == 'GET' && path == '/salesorders') {
      return _MockResult(200, {
        'salesorders': ZohoMockFixtures.salesOrders(),
        'page_context': ZohoMockFixtures.pageContext(),
      });
    }
    if (method == 'GET' && _matches(path, r'^/salesorders/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'salesorder': ZohoMockFixtures.salesOrderDetail(id),
      });
    }
    if (method == 'GET' && path == '/invoices') {
      final filterBy = options.queryParameters['filter_by']?.toString();
      final list = filterBy == 'Status.All'
          ? ZohoMockFixtures.openInvoices()
          : ZohoMockFixtures.invoicesWithLines()
              .map((i) => Map<String, dynamic>.from(i)..remove('line_items'))
              .toList();
      return _MockResult(200, {
        'invoices': list,
        'page_context': ZohoMockFixtures.pageContext(),
      });
    }
    if (method == 'GET' && _matches(path, r'^/invoices/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'invoice': ZohoMockFixtures.invoiceDetail(id),
      });
    }
    if (method == 'GET' && path == '/customerpayments') {
      return _MockResult(200, {
        'customerpayments': ZohoMockFixtures.receipts(),
        'page_context': ZohoMockFixtures.pageContext(),
      });
    }
    if (method == 'GET' && _matches(path, r'^/customerpayments/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'payment': ZohoMockFixtures.paymentDetail(id),
      });
    }
    if (method == 'GET' && path == '/creditnotes') {
      return _MockResult(200, {
        'creditnotes': ZohoMockFixtures.creditNotes()
            .map((c) => Map<String, dynamic>.from(c)..remove('line_items'))
            .toList(),
        'page_context': ZohoMockFixtures.pageContext(),
      });
    }
    if (method == 'GET' && _matches(path, r'^/creditnotes/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'creditnote': ZohoMockFixtures.creditNoteDetail(id),
      });
    }
    if (method == 'GET' && path == '/expenses') {
      return _MockResult(200, {
        'expenses': ZohoMockFixtures.expensesWithLines()
            .map((e) => Map<String, dynamic>.from(e)..remove('line_items'))
            .toList(),
        'page_context': ZohoMockFixtures.pageContext(),
      });
    }
    if (method == 'GET' && _matches(path, r'^/expenses/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'expense': ZohoMockFixtures.expenseDetail(id),
      });
    }
    if (method == 'GET' && path == '/locations') {
      return _MockResult(200, {
        'locations': ZohoMockFixtures.locations,
      });
    }
    if (method == 'GET' && path == '/salespersons') {
      return _MockResult(200, {
        'data': ZohoMockFixtures.salespersons,
        'salespersons': ZohoMockFixtures.salespersons,
      });
    }
    if (method == 'GET' && path == '/cm_salesperson_profile') {
      return _MockResult(200, {
        'module_records': ZohoMockFixtures.salespersonProfiles,
      });
    }
    if (method == 'GET' && path == '/bankaccounts') {
      return _MockResult(200, {
        'bankaccounts': ZohoMockFixtures.bankAccounts,
      });
    }
    if (method == 'GET' && path == '/settings/taxes') {
      return _MockResult(200, {
        'taxes': ZohoMockFixtures.taxes,
      });
    }
    if (method == 'GET' && path == '/chartofaccounts') {
      return _MockResult(200, {
        'chartofaccounts': ZohoMockFixtures.expenseAccounts,
      });
    }
    if (method == 'GET' && _matches(path, r'^/organizations/[^/]+$')) {
      final id = path.split('/').last;
      return _MockResult(200, {
        'organization': ZohoMockFixtures.organization(
          id.isNotEmpty ? id : organizationId,
        ),
      });
    }

    return null;
  }

  static bool _matches(String path, String pattern) =>
      RegExp(pattern).hasMatch(path);
}

class _MockResult {
  final int statusCode;
  final Map<String, dynamic> data;
  _MockResult(this.statusCode, this.data);
}
