import 'package:dio/dio.dart';

import 'zoho_mock_catalog.dart';
import 'zoho_mock_path.dart';

/// Runtime flags consulted by [ZohoMockInterceptor] for each request.
class ZohoMockFlags {
  final bool Function() isCredentialMockMode;
  final bool Function() mockTransactions;
  final bool Function() mockSalesOrderTransactions;
  final bool Function() mockStockTransfers;

  const ZohoMockFlags({
    required this.isCredentialMockMode,
    required this.mockTransactions,
    required this.mockSalesOrderTransactions,
    required this.mockStockTransfers,
  });
}

/// Dio interceptor that short-circuits selected requests with Zoho-shaped
/// mock responses. Registered **before** the auth interceptor so mocked calls
/// never hit the network or OAuth.
///
/// Live and mock API methods share the same payload-mapping + `_dio.*` path;
/// only this transport layer diverges.
class ZohoMockInterceptor extends Interceptor {
  final ZohoMockCatalog catalog;
  final ZohoMockFlags flags;
  final Duration latency;

  /// Last request that was mocked (for tests).
  RequestOptions? lastMockedRequest;

  ZohoMockInterceptor({
    required this.catalog,
    required this.flags,
    this.latency = const Duration(milliseconds: 300),
  });

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!shouldMockRequest(options)) {
      return handler.next(options);
    }

    lastMockedRequest = options;
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }

    final response = catalog.buildResponse(options);
    // Surface 4xx/5xx as DioException so callers' try/catch paths match live.
    if ((response.statusCode ?? 500) >= 400) {
      return handler.reject(
        DioException(
          requestOptions: options,
          response: response,
          type: DioExceptionType.badResponse,
          message: 'Mock HTTP ${response.statusCode}',
        ),
      );
    }
    return handler.resolve(response);
  }

  /// Exposed for unit tests — pure routing decision.
  bool shouldMockRequest(RequestOptions options) {
    if (flags.isCredentialMockMode()) {
      return true;
    }

    final method = options.method.toUpperCase();
    final path = ZohoMockPath.normalize(options);

    // With real credentials, only transaction *writes* may be mocked.
    if (method == 'GET') return false;

    if (_isSalesOrderWrite(method, path)) {
      return flags.mockSalesOrderTransactions();
    }
    if (_isStockTransferWrite(method, path)) {
      return flags.mockStockTransfers();
    }
    if (_isGeneralTransactionWrite(method, path)) {
      return flags.mockTransactions();
    }

    // Unknown write with real credentials → live network.
    return false;
  }

  static bool _isSalesOrderWrite(String method, String path) {
    if (method == 'POST' && path == '/salesorders') return true;
    if (method == 'PUT' && RegExp(r'^/salesorders/[^/]+$').hasMatch(path)) {
      return true;
    }
    if (method == 'POST' &&
        RegExp(r'^/salesorders/[^/]+/converttoinvoice$').hasMatch(path)) {
      return true;
    }
    return false;
  }

  static bool _isStockTransferWrite(String method, String path) {
    return method == 'POST' && path.endsWith('/transferorders');
  }

  static bool _isGeneralTransactionWrite(String method, String path) {
    if (method == 'POST' && path == '/contacts') return true;
    if (method == 'PUT' && RegExp(r'^/contacts/[^/]+$').hasMatch(path)) {
      return true;
    }
    if (method == 'POST' && path == '/invoices') return true;
    if (method == 'POST' && path == '/customerpayments') return true;
    if (method == 'POST' && path == '/creditnotes') return true;
    if (method == 'POST' && path == '/expenses') return true;
    return false;
  }
}
