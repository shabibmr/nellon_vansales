import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/route.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_list_bloc.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_list_event.dart';

class FakeSalesRepository implements SalesRepository {
  List<ExpenseEntry> expenses = [];

  @override
  List<ExpenseEntry> getLocalExpenses() => List.of(expenses);

  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      expenses;

  @override
  Future<void> enqueueSalesOrder(SalesOrder order, {required bool isUpdate}) async {}
  @override
  List<SalesOrder> getLocalOrders() => [];
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<List<SalesOrder>> fetchRemoteOrders({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId) async => null;
  @override
  List<SalesInvoice> getLocalInvoices() => [];
  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}
  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId) async => null;
  @override
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId) async => null;
  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId) async => null;
  @override
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
  @override
  List<SyncQueueItem> getSyncQueue() => [];
  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {}
  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];
  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async => [];
  @override
  List<ReceiptVoucher> getLocalReceipts() => [];
  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {}
  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) async {}
  @override
  List<RouteModel> getRoutes() => [];
  @override
  String? get activeRouteId => null;
  @override
  Future<void> setActiveRouteId(String? routeId) async {}
  @override
  List<Item> getItems() => [];
  @override
  Future<void> saveItems(List<Item> items) async {}
  @override
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(Item item) async =>
      (item: item, offlineFallback: false);
  @override
  List<SalesReturn> getLocalReturns() => [];
  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {}
  @override
  Future<List<SalesReturn>> fetchRemoteReturns({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    expenses.add(expense);
  }
  @override
  CashClosing? getLocalCashClosing() => null;
  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {}
  @override
  List<StockTransfer> getLocalStockTransfers() => [];
  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {}
  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({DateTime? startDate, DateTime? endDate}) async => [];
}

void main() {
  late FakeSalesRepository salesRepo;
  late ExpenseListBloc bloc;

  setUp(() {
    salesRepo = FakeSalesRepository();
    bloc = ExpenseListBloc(salesRepository: salesRepo);
  });

  tearDown(() async => bloc.close());

  test('LoadExpenses fetches remote expenses for active filter', () async {
    salesRepo.expenses = [
      ExpenseEntry(
        id: 'exp_1',
        date: DateTime.now(),
        lines: const [
          ExpenseLineItem(
            category: 'Fuel',
            amount: 75.0,
            description: 'Diesel',
          ),
        ],
      ),
    ];

    bloc.add(const LoadExpenses());
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.expenses, hasLength(1));
    expect(bloc.state.expenses.single.amount, 75.0);
  });
}
