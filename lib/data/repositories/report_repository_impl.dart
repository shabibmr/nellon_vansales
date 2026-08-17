import '../../domain/models/customer.dart';
import '../../domain/models/expense_entry.dart';
import '../../domain/models/item.dart';
import '../../domain/models/open_invoice.dart';
import '../../domain/models/receipt_voucher.dart';
import '../../domain/models/sales_invoice.dart';
import '../../domain/models/sales_order.dart';
import '../../domain/models/sales_return.dart';
import '../../domain/models/stock_transfer.dart';
import '../../domain/repositories/report_repository.dart';
import '../../domain/utils/stock_transfer_direction.dart';
import '../models/customer_model.dart';
import '../models/expense_entry_model.dart';
import '../models/item_model.dart';
import '../models/open_invoice_model.dart';
import '../models/receipt_voucher_model.dart';
import '../models/sales_invoice_model.dart';
import '../models/sales_order_model.dart';
import '../models/sales_return_model.dart';
import '../models/stock_transfer_model.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [ReportRepository].
///
/// Wraps [ZohoApiClient] network calls and [HiveDatabaseService] session context,
/// deserializing backend JSON into domain entities and applying location filters.
class ReportRepositoryImpl implements ReportRepository {
  final ZohoApiClient apiClient;
  final HiveDatabaseService dbService;

  /// Creates a new [ReportRepositoryImpl].
  ReportRepositoryImpl({
    required this.apiClient,
    required this.dbService,
  });

  @override
  Future<List<SalesInvoice>> fetchInvoices() async {
    final raw = await apiClient.fetchInvoices();
    final list = raw.map((json) => SalesInvoiceModel.fromJson(json)).toList();
    final salesperson = dbService.getCurrentSalesperson();
    final locationId = salesperson?.locationId;
    if (locationId != null && locationId.isNotEmpty) {
      return list.where((inv) => inv.locationId == locationId).toList();
    }
    return list;
  }

  @override
  Future<List<SalesOrder>> fetchSalesOrders() async {
    // Reports need line items (itemwise / shipment); list page uses headers only.
    final raw = await apiClient.fetchSalesOrdersWithDetails();
    return raw.map((json) => SalesOrderModel.fromJson(json)).toList();
  }

  @override
  Future<List<ReceiptVoucher>> fetchReceipts() async {
    final raw = await apiClient.fetchReceipts();
    return raw.map((json) => ReceiptVoucherModel.fromJson(json)).toList();
  }

  @override
  Future<List<ExpenseEntry>> fetchExpenses() async {
    final raw = await apiClient.fetchExpenses();
    return raw.map((json) => ExpenseEntryModel.fromZohoJson(json)).toList();
  }

  @override
  Future<List<SalesReturn>> fetchSalesReturns() async {
    final raw = await apiClient.fetchSalesReturns();
    return raw.map((json) => SalesReturnModel.fromJson(json)).toList();
  }

  @override
  Future<List<OpenInvoice>> fetchOpenInvoices() async {
    final raw = await apiClient.fetchOpenInvoices();
    return raw.map((json) => OpenInvoiceModel.fromJson(json)).toList();
  }

  @override
  Future<List<Customer>> fetchCustomers() async {
    final raw = await apiClient.fetchCustomers();
    return raw.map((json) => CustomerModel.fromJson(json)).toList();
  }

  @override
  Future<List<Item>> fetchItems({String? locationId}) async {
    final targetLocationId =
        locationId ?? dbService.assignedWarehouseId ?? '';
    final raw = await apiClient.fetchItems(targetLocationId);
    return raw.map((json) => ItemModel.fromJson(json)).toList();
  }

  @override
  Future<List<StockTransfer>> fetchStockTransfers() async {
    final raw = await apiClient.fetchStockTransfers();
    final vanId =
        dbService.getCurrentSalesperson()?.locationId ??
        dbService.assignedWarehouseId;
    return raw.map((json) {
      final mapped = StockTransferModel.fromJson(json);
      return mapped.copyWith(
        direction: inferStockTransferDirection(
          fromLocationId: mapped.fromLocationId,
          toLocationId: mapped.toLocationId,
          vanLocationId: vanId,
          stored: mapped.direction,
        ),
      );
    }).toList();
  }
}
