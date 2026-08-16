import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/models/submit_result.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';

/// Satisfies the voucher enqueue helpers on [SalesRepository] fakes by
/// forwarding to [enqueueSyncItem] (empty payload — tests assert type/id).
mixin SalesRepositoryEnqueueStubs implements SalesRepository {
  @override
  Future<void> enqueueInvoice(SalesInvoice invoice) {
    return enqueueSyncItem(
      SyncQueueItem(
        id: invoice.id,
        type: 'invoice',
        payload: const {},
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueConvertSalesOrder({
    required SalesOrder order,
    required SalesInvoice invoice,
  }) {
    return enqueueSyncItem(
      SyncQueueItem(
        id: invoice.id,
        type: 'convert_so',
        payload: {
          'salesorder_id': order.zohoOrderId ?? order.id,
          'source_order_id': order.id,
          'local_invoice_id': invoice.id,
        },
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueReceipt(ReceiptVoucher voucher) {
    return enqueueSyncItem(
      SyncQueueItem(
        id: voucher.id,
        type: 'receipt',
        payload: const {},
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueSalesReturn(SalesReturn salesReturn) {
    return enqueueSyncItem(
      SyncQueueItem(
        id: salesReturn.id,
        type: 'return',
        payload: const {},
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueExpense(ExpenseEntry expense) {
    return enqueueSyncItem(
      SyncQueueItem(
        id: expense.id,
        type: 'expense',
        payload: const {},
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueStockTransfer(StockTransfer transfer) {
    return enqueueSyncItem(
      SyncQueueItem(
        id: transfer.id,
        type: 'stock_transfer',
        payload: const {},
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<SubmitResult> submitOrEnqueue(SyncQueueItem item) async {
    await enqueueSyncItem(item);
    return SubmitResult.queued;
  }

  @override
  Future<SubmitResult> submitInvoice(SalesInvoice invoice) async {
    await enqueueInvoice(invoice);
    return SubmitResult.queued;
  }

  @override
  Future<SubmitResult> submitSalesOrder(
    SalesOrder order, {
    required bool isUpdate,
  }) async {
    await enqueueSalesOrder(order, isUpdate: isUpdate);
    return SubmitResult.queued;
  }

  @override
  Future<SubmitResult> submitConvertSalesOrder({
    required SalesOrder order,
    required SalesInvoice invoice,
  }) async {
    await enqueueConvertSalesOrder(order: order, invoice: invoice);
    return SubmitResult.queued;
  }

  @override
  Future<SubmitResult> submitReceipt(ReceiptVoucher voucher) async {
    await enqueueReceipt(voucher);
    return SubmitResult.queued;
  }

  @override
  Future<SubmitResult> submitSalesReturn(SalesReturn salesReturn) async {
    await enqueueSalesReturn(salesReturn);
    return SubmitResult.queued;
  }

  @override
  Future<SubmitResult> submitExpense(ExpenseEntry expense) async {
    await enqueueExpense(expense);
    return SubmitResult.queued;
  }

  @override
  Future<SubmitResult> submitStockTransfer(StockTransfer transfer) async {
    await enqueueStockTransfer(transfer);
    return SubmitResult.queued;
  }
}
