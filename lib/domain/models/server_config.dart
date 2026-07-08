import 'package:equatable/equatable.dart';

/// Represents Zoho API credentials and configuration loaded from Firestore.
class ServerConfig extends Equatable {
  final String clientId;
  final String clientSecret;
  final String code; // Represents the Zoho authorization code or refresh token

  /// Runtime toggle for simulating invoice/receipt/return/expense uploads
  /// against a sandbox instead of pushing them live to Zoho. Replaces the
  /// old compile-time `_mockTransactions` flag in `ZohoApiClient`.
  final bool mockTransactions;

  /// Runtime toggle for simulating sales order uploads specifically,
  /// independent of [mockTransactions]. Replaces the old compile-time
  /// `_mockSalesOrderTransactions` flag in `ZohoApiClient`.
  final bool mockSalesOrderTransactions;

  /// Runtime toggle for simulating stock transfer uploads (Issue to Van /
  /// Stock Unloading) specifically, independent of [mockTransactions].
  /// Mirrors [mockSalesOrderTransactions] in `ZohoApiClient`.
  final bool mockStockTransfers;

  const ServerConfig({
    required this.clientId,
    required this.clientSecret,
    required this.code,
    this.mockTransactions = true,
    this.mockSalesOrderTransactions = false,
    this.mockStockTransfers = true,
  });

  /// Factory constructor to create a [ServerConfig] from a Firestore map.
  ///
  /// Defaults mirror the old compile-time flags (`mockTransactions` true,
  /// `mockSalesOrderTransactions` false, `mockStockTransfers` true) so an org
  /// whose Firestore document predates these fields keeps its current
  /// safe/simulated behavior rather than silently starting to push real
  /// transactions to Zoho.
  factory ServerConfig.fromMap(Map<String, dynamic> map) {
    return ServerConfig(
      clientId: map['client_id'] as String? ?? '',
      clientSecret: map['client_secret'] as String? ?? '',
      code: map['code'] as String? ?? '',
      mockTransactions: map['mock_transactions'] as bool? ?? true,
      mockSalesOrderTransactions:
          map['mock_sales_order_transactions'] as bool? ?? false,
      mockStockTransfers: map['mock_stock_transfers'] as bool? ?? true,
    );
  }

  /// Converts the [ServerConfig] to a map.
  Map<String, dynamic> toMap() {
    return {
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
      'mock_transactions': mockTransactions,
      'mock_sales_order_transactions': mockSalesOrderTransactions,
      'mock_stock_transfers': mockStockTransfers,
    };
  }

  @override
  List<Object?> get props => [
    clientId,
    clientSecret,
    code,
    mockTransactions,
    mockSalesOrderTransactions,
    mockStockTransfers,
  ];
}
