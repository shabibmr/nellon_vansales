import '../models/expense_entry.dart';
import '../models/receipt_voucher.dart';
import '../models/sales_invoice.dart';
import '../models/sales_order.dart';
import '../models/sales_return.dart';

/// Stable content fingerprints for refresh “up to date” messaging.
///
/// Full Equatable equality on domain models is too noisy (stock, tax names,
/// unit conversions rebuilt from Zoho line JSON). These fingerprints cover
/// only fields the user sees on the voucher form.
class VoucherContentFingerprint {
  VoucherContentFingerprint._();

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String salesInvoice(SalesInvoice inv) {
    final lines = inv.items
        .map(
          (l) =>
              '${l.item.id}|${l.quantity}|${l.rate}|${l.discount}|${l.displayUom}|${l.taxPercentage}',
        )
        .join(',');
    return [
      inv.id,
      inv.invoiceNumber,
      inv.customerId,
      _day(inv.date),
      inv.notes.trim(),
      lines,
    ].join('§');
  }

  static String salesInvoiceForm({
    required String id,
    required String invoiceNumber,
    required String customerId,
    required DateTime date,
    required String notes,
    required List<InvoiceLineItem> items,
  }) {
    final lines = items
        .map(
          (l) =>
              '${l.item.id}|${l.quantity}|${l.rate}|${l.discount}|${l.displayUom}|${l.taxPercentage}',
        )
        .join(',');
    return [
      id,
      invoiceNumber,
      customerId,
      _day(date),
      notes.trim(),
      lines,
    ].join('§');
  }

  static String salesOrder(SalesOrder order) {
    final lines = order.items
        .map(
          (l) =>
              '${l.item.id}|${l.quantity}|${l.rate}|${l.discount}|${l.displayUom}|${l.taxPercentage}',
        )
        .join(',');
    return [
      order.id,
      order.orderNumber,
      order.customerId,
      _day(order.date),
      _day(order.shipmentDate),
      order.notes.trim(),
      order.status.name,
      lines,
    ].join('§');
  }

  static String salesOrderForm({
    required String id,
    required String orderNumber,
    required String customerId,
    required DateTime date,
    required DateTime shipmentDate,
    required String notes,
    required String statusName,
    required List<OrderLineItem> items,
  }) {
    final lines = items
        .map(
          (l) =>
              '${l.item.id}|${l.quantity}|${l.rate}|${l.discount}|${l.displayUom}|${l.taxPercentage}',
        )
        .join(',');
    return [
      id,
      orderNumber,
      customerId,
      _day(date),
      _day(shipmentDate),
      notes.trim(),
      statusName,
      lines,
    ].join('§');
  }

  static String receipt(ReceiptVoucher rec) {
    final alloc = rec.allocations
        .map((a) => '${a.invoiceId}|${a.amountApplied}')
        .join(',');
    return [
      rec.id,
      rec.paymentNumber,
      rec.customerId,
      rec.amount,
      rec.paymentMode,
      rec.referenceNumber.trim(),
      _day(rec.date),
      alloc,
    ].join('§');
  }

  static String receiptForm({
    required String id,
    required String paymentNumber,
    required String customerId,
    required double amount,
    required String paymentMode,
    required String referenceNumber,
    required DateTime date,
    required List<PaymentAllocation> allocations,
  }) {
    final alloc = allocations
        .map((a) => '${a.invoiceId}|${a.amountApplied}')
        .join(',');
    return [
      id,
      paymentNumber,
      customerId,
      amount,
      paymentMode,
      referenceNumber.trim(),
      _day(date),
      alloc,
    ].join('§');
  }

  static String salesReturn(SalesReturn ret) {
    final lines = ret.items
        .map(
          (l) =>
              '${l.invoiceLineItem.item.id}|${l.returnedQuantity}|${l.invoiceLineItem.rate}',
        )
        .join(',');
    return [
      ret.id,
      ret.creditNoteNumber,
      ret.customerId,
      _day(ret.date),
      ret.reason.trim(),
      lines,
    ].join('§');
  }

  static String salesReturnForm({
    required String id,
    required String creditNoteNumber,
    required String customerId,
    required DateTime date,
    required String reason,
    required List<SalesReturnLineItem> items,
  }) {
    final lines = items
        .map(
          (l) =>
              '${l.invoiceLineItem.item.id}|${l.returnedQuantity}|${l.invoiceLineItem.rate}',
        )
        .join(',');
    return [
      id,
      creditNoteNumber,
      customerId,
      _day(date),
      reason.trim(),
      lines,
    ].join('§');
  }

  static String expense(ExpenseEntry exp) {
    final lines = exp.lines
        .map((l) => '${l.category}|${l.amount}|${l.description.trim()}')
        .join(',');
    return [exp.id, _day(exp.date), lines].join('§');
  }

  static String expenseForm({
    required String id,
    required DateTime date,
    required double amount,
    required String category,
    required String description,
  }) {
    // Expense editor is single-line UI over the first line / total.
    return [
      id,
      _day(date),
      '$category|$amount|${description.trim()}',
    ].join('§');
  }
}
