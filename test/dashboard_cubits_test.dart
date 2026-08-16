import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/ui/features/dashboard/cubit/dashboard_nav_cubit.dart';
import 'package:van_sales/ui/features/dashboard/cubit/daily_stats_cubit.dart';
import 'package:van_sales/ui/features/dashboard/cubit/list_layout_cubit.dart';

import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/repositories/expense_repository.dart';
import 'package:van_sales/domain/repositories/invoice_repository.dart';
import 'package:van_sales/domain/repositories/receipt_repository.dart';
import 'package:van_sales/domain/repositories/sales_order_repository.dart';
import 'package:van_sales/domain/repositories/sales_return_repository.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';

class FakeSalesRepository
    implements
        ExpenseRepository,
        InvoiceRepository,
        ReceiptRepository,
        SalesOrderRepository,
        SalesReturnRepository {
  List<SalesInvoice> invoices = [];
  List<ReceiptVoucher> receipts = [];
  List<ExpenseEntry> expenses = [];
  List<SalesReturn> returns = [];
  List<SalesOrder> orders = [];
  bool shouldThrow = false;

  @override
  List<SalesInvoice> getLocalInvoices() {
    if (shouldThrow) throw Exception('DB Error');
    return invoices;
  }

  @override
  List<ReceiptVoucher> getLocalReceipts() {
    if (shouldThrow) throw Exception('DB Error');
    return receipts;
  }

  @override
  List<ExpenseEntry> getLocalExpenses() {
    if (shouldThrow) throw Exception('DB Error');
    return expenses;
  }

  @override
  List<SalesReturn> getLocalReturns() {
    if (shouldThrow) throw Exception('DB Error');
    return returns;
  }

  @override
  List<SalesOrder> getLocalOrders() {
    if (shouldThrow) throw Exception('DB Error');
    return orders;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {}
  @override
  Future<void> enqueueSalesOrder(SalesOrder order, {required bool isUpdate}) async {}
  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];
  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async => [];
  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {}
  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}
  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<ExpenseEntry?> fetchExpenseById(String expenseId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<List<SalesOrder>> fetchRemoteOrders({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId, {bool allowOfflineFallback = false}) async => null;
  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {}
  @override
  Future<List<SalesReturn>> fetchRemoteReturns({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {}
  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({DateTime? startDate, DateTime? endDate}) async => [];
}

void main() {
  group('DashboardNavCubit Tests', () {
    late DashboardNavCubit cubit;

    setUp(() {
      cubit = DashboardNavCubit();
    });

    tearDown(() {
      cubit.close();
    });

    test('Initial tab index is Dashboard (1); Customers bar slot is hidden', () {
      expect(cubit.state, 1);
    });

    test('setTab updates the tab index successfully', () {
      cubit.setTab(3);
      expect(cubit.state, 3);
    });
  });

  group('ListLayoutCubit Tests', () {
    late ListLayoutCubit cubit;

    setUp(() {
      cubit = ListLayoutCubit();
    });

    tearDown(() {
      cubit.close();
    });

    test('defaults to list mode (false)', () {
      expect(cubit.state, isFalse);
    });

    test('setGrid(true) enables grid mode', () {
      cubit.setGrid(true);
      expect(cubit.state, isTrue);
    });

    test('toggle flips list and grid modes', () {
      cubit.toggle();
      expect(cubit.state, isTrue);
      cubit.toggle();
      expect(cubit.state, isFalse);
    });
  });

  group('DailyStatsCubit Tests', () {
    late FakeSalesRepository salesRepo;
    late DailyStatsCubit cubit;

    const mockItem = Item(
      id: 'item_1',
      name: 'Milk',
      sku: 'SKU-001',
      rate: 10.0,
      stock: 100,
      description: '',
      taxName: 'No Tax',
      taxPercentage: 0.0,
    );

    setUp(() {
      final now = DateTime.now();
      final mockInvoice = SalesInvoice(
        id: 'inv_1',
        invoiceNumber: 'INV-001',
        customerId: 'cust_1',
        customerName: 'Customer 1',
        date: now,
        dueDate: now,
        items: const [
          InvoiceLineItem(
            item: mockItem,
            quantity: 15,
            rate: 10.0,
            taxPercentage: 0.0,
          ),
        ],
        notes: '',
      );

      final mockReceipt = ReceiptVoucher(
        id: 'rcpt_1',
        paymentNumber: 'PAY-001',
        customerId: 'cust_1',
        customerName: 'Customer 1',
        date: now,
        amount: 100.0,
        paymentMode: 'Cash',
        referenceNumber: 'REF-001',
        allocations: const [],
      );

      final mockExpense = ExpenseEntry(
        id: 'exp_1',
        date: now,
        lines: const [
          ExpenseLineItem(
            category: 'Fuel',
            amount: 50.0,
            description: '',
          ),
        ],
      );

      final mockReturn = SalesReturn(
        id: 'ret_1',
        creditNoteNumber: 'CN-001',
        customerId: 'cust_2',
        customerName: 'Customer 2',
        date: now,
        reason: 'Damaged',
        items: const [
          SalesReturnLineItem(
            invoiceLineItem: InvoiceLineItem(
              item: mockItem,
              quantity: 10,
              rate: 10.0,
              taxPercentage: 0.0,
            ),
            returnedQuantity: 3,
          ),
        ],
      );

      salesRepo = FakeSalesRepository();
      salesRepo.invoices = [
        mockInvoice,
        mockInvoice.copyWith(
          id: 'inv_2',
          customerId: 'cust_2',
          items: const [
            InvoiceLineItem(
              item: mockItem,
              quantity: 20,
              rate: 10.0,
              taxPercentage: 0.0,
            ),
          ],
        )
      ];
      salesRepo.receipts = [mockReceipt];
      salesRepo.expenses = [mockExpense];
      salesRepo.returns = [mockReturn];
      cubit = DailyStatsCubit(
        invoiceRepository: salesRepo,
        expenseRepository: salesRepo,
        receiptRepository: salesRepo,
        salesReturnRepository: salesRepo,
        salesOrderRepository: salesRepo,
      );
    });

    tearDown(() {
      cubit.close();
    });

    test('Initial state correctly aggregates seeded mock data', () {
      expect(cubit.state.todaySales, 350.0);
      expect(cubit.state.todayPayments, 100.0);
      expect(cubit.state.todayExpenses, 50.0);
      expect(cubit.state.todayReturns, 30.0);
      expect(cubit.state.completedDeliveries, 2);
    });

    test('refresh pulls new data and aggregates correctly', () {
      final now = DateTime.now();
      salesRepo.invoices = [
        SalesInvoice(
          id: 'inv_1',
          invoiceNumber: 'INV-001',
          customerId: 'cust_1',
          customerName: 'Customer 1',
          date: now,
          dueDate: now,
          items: const [
            InvoiceLineItem(
              item: mockItem,
              quantity: 15,
              rate: 10.0,
              taxPercentage: 0.0,
            ),
          ],
          notes: '',
        ),
      ];
      cubit.refresh();

      expect(cubit.state.todaySales, 150.0);
      expect(cubit.state.completedDeliveries, 1);
    });

    test('refresh failure is caught and doesn\'t update or crash state', () {
      salesRepo.shouldThrow = true;
      final oldState = cubit.state;
      cubit.refresh();

      expect(cubit.state, oldState);
    });
  });
}
