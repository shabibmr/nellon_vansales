import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../../domain/models/customer.dart';
import '../../../domain/models/expense_entry.dart';
import '../../../domain/models/organization.dart';
import '../../../domain/models/receipt_voucher.dart';
import '../../../domain/models/sales_invoice.dart';
import '../../../domain/models/sales_order.dart';
import '../../../domain/models/sales_return.dart';
import '../../../domain/models/stock_transfer.dart';
import '../../../domain/models/thermal_paper_size.dart';
import '../../../domain/models/thermal_ticket_preview.dart';
import '../../../domain/repositories/voucher_pdf_repository.dart';
import 'esc_pos_ticket_builder.dart';

/// Builds ESC/POS command bytes for all supported voucher types.
class VoucherTicketBuilder {
  /// Creates a ticket for [type] using the active [paperSize].
  static Future<List<int>> build({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    required ThermalPaperSize paperSize,
    String? salespersonName,
    String? salespersonPhone,
  }) async {
    final composed = await _compose(
      type: type,
      voucher: voucher,
      org: org,
      customer: customer,
      paperSize: paperSize,
      salespersonName: salespersonName,
      salespersonPhone: salespersonPhone,
    );
    return composed.bytes;
  }

  /// Same layout as [build], as styled lines for an on-screen print preview.
  static Future<ThermalTicketPreview> buildPreview({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    required ThermalPaperSize paperSize,
    String? salespersonName,
    String? salespersonPhone,
  }) async {
    final composed = await _compose(
      type: type,
      voucher: voucher,
      org: org,
      customer: customer,
      paperSize: paperSize,
      salespersonName: salespersonName,
      salespersonPhone: salespersonPhone,
    );
    return composed.preview;
  }

  static Future<({List<int> bytes, ThermalTicketPreview preview})> _compose({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    required ThermalPaperSize paperSize,
    String? salespersonName,
    String? salespersonPhone,
  }) async {
    final profile = await CapabilityProfile.load();
    final escPaper = EscPosTicketBuilder.toEscPosPaperSize(paperSize);
    final generator = Generator(escPaper, profile);
    final b = EscPosTicketBuilder(generator: generator, paperSize: paperSize);

    final bytes = <int>[];
    bytes.addAll(b.reset());

    switch (type) {
      case VoucherType.salesInvoice:
        bytes.addAll(
          _invoice(
            b,
            voucher as SalesInvoice,
            org,
            customer,
            salespersonName,
            salespersonPhone,
          ),
        );
      case VoucherType.salesOrder:
        bytes.addAll(
          _order(
            b,
            voucher as SalesOrder,
            org,
            customer,
            salespersonName,
            salespersonPhone,
          ),
        );
      case VoucherType.salesReturn:
        bytes.addAll(
          _return(
            b,
            voucher as SalesReturn,
            org,
            customer,
            salespersonName,
            salespersonPhone,
          ),
        );
      case VoucherType.paymentReceipt:
        bytes.addAll(
          _receipt(
            b,
            voucher as ReceiptVoucher,
            org,
            customer,
            salespersonName,
            salespersonPhone,
          ),
        );
      case VoucherType.expenseVoucher:
        bytes.addAll(
          _expense(
            b,
            voucher as ExpenseEntry,
            org,
            salespersonName,
            salespersonPhone,
          ),
        );
      case VoucherType.stockTransfer:
        bytes.addAll(
          _stockTransfer(
            b,
            voucher as StockTransfer,
            org,
            salespersonName,
            salespersonPhone,
          ),
        );
    }

    return (bytes: bytes, preview: b.toPreview());
  }

  /// Short calibration page for Settings → Test print.
  static Future<List<int>> buildTestPage({
    required ThermalPaperSize paperSize,
    String? printerName,
  }) async {
    final profile = await CapabilityProfile.load();
    final escPaper = EscPosTicketBuilder.toEscPosPaperSize(paperSize);
    final generator = Generator(escPaper, profile);
    final b = EscPosTicketBuilder(generator: generator, paperSize: paperSize);

    final bytes = <int>[];
    bytes.addAll(b.reset());
    bytes.addAll(b.doubleDivider());
    bytes.addAll(b.center('PRINTER TEST', bold: true, underline: true));
    bytes.addAll(b.center('Nigachi NC-MTP500'));
    bytes.addAll(b.divider());
    bytes.addAll(b.leftRight('Paper size:', paperSize.label));
    bytes.addAll(b.leftRight('Columns:', '${paperSize.columns}'));
    if (printerName != null && printerName.isNotEmpty) {
      bytes.addAll(
        b.left('Printer: ${b.truncate(printerName, b.columns - 9)}'),
      );
    }
    bytes.addAll(b.divider());
    // Full-width ruler: exactly [columns] chars to verify edge-to-edge fit.
    final ruler = List.generate(
      paperSize.columns,
      (i) => '${(i + 1) % 10}',
    ).join();
    bytes.addAll(b.left(ruler));
    bytes.addAll(b.center('ABCDEFGHIJKLMNOPQRSTUVWXYZ'));
    bytes.addAll(b.center('0123456789'));
    bytes.addAll(b.leftRight('Left', 'Right'));
    bytes.addAll(b.divider());
    final totalCols = (paperSize.columns / 2).floor().clamp(
      16,
      paperSize.columns,
    );
    bytes.addAll(
      b.leftRight(
        'TOTAL SAMPLE',
        'AED 100.00',
        bold: true,
        width: PosTextSize.size2,
        height: PosTextSize.size2,
        layoutColumns: totalCols,
      ),
    );
    bytes.addAll(b.doubleDivider());
    bytes.addAll(b.center('If readable, setup OK'));
    bytes.addAll(b.cut());
    return bytes;
  }

  static List<int> _orgHeader(
    EscPosTicketBuilder b,
    Organization org, {
    required String voucherTitle,
    required String voucherNumber,
    required DateTime date,
  }) {
    return b.header(
      orgName: org.name,
      orgAddress: org.address,
      orgPhone: org.phone,
      orgTrn: org.trn,
      voucherTitle: voucherTitle,
      voucherNumber: voucherNumber,
      date: date,
    );
  }

  static List<int> _customer(
    EscPosTicketBuilder b, {
    required String name,
    required Customer? customer,
  }) {
    return b.customerBlock(
      name: name,
      phone: customer?.phone,
      address: customer?.address,
      trn: customer?.trn,
    );
  }

  static List<int> _invoice(
    EscPosTicketBuilder b,
    SalesInvoice invoice,
    Organization org,
    Customer? customer,
    String? salespersonName,
    String? salespersonPhone,
  ) {
    final symbol = org.currencySymbol;
    final bytes = <int>[];
    bytes.addAll(
      _orgHeader(
        b,
        org,
        voucherTitle: 'SALES INVOICE',
        voucherNumber: invoice.invoiceNumber,
        date: invoice.date,
      ),
    );
    bytes.addAll(_customer(b, name: invoice.customerName, customer: customer));
    bytes.addAll(b.itemTableHeader());
    for (var i = 0; i < invoice.items.length; i++) {
      final line = invoice.items[i];
      bytes.addAll(
        b.itemRow(
          serial: i + 1,
          name: line.item.name,
          qty: line.quantity,
          amountText: b.amountOnly(line.total),
          uom: line.displayUom,
        ),
      );
    }
    bytes.addAll(
      _padToMinLength(
        b,
        tableStyle: true,
        buildTail: (tail) {
          final after = <int>[];
          after.addAll(
            tail.totalsBlock(
              symbol: symbol,
              currencyCode: org.currencyCode,
              subTotal: invoice.subTotal,
              taxTotal: invoice.taxTotal,
              discountTotal: invoice.discountTotal,
              total: invoice.total,
              roundOff: invoice.roundOff,
              taxLabel: _vatLabel(
                invoice.items.map((line) => line.taxPercentage),
              ),
            ),
          );
          if (invoice.notes.trim().isNotEmpty) {
            after.addAll(
              tail.left(
                'Notes: ${tail.truncate(invoice.notes, tail.columns - 7)}',
              ),
            );
          }
          after.addAll(
            tail.footer(
              salespersonName: salespersonName,
              salespersonPhone: salespersonPhone,
            ),
          );
          return after;
        },
      ),
    );
    return bytes;
  }

  static List<int> _order(
    EscPosTicketBuilder b,
    SalesOrder order,
    Organization org,
    Customer? customer,
    String? salespersonName,
    String? salespersonPhone,
  ) {
    final symbol = org.currencySymbol;
    final bytes = <int>[];
    bytes.addAll(
      _orgHeader(
        b,
        org,
        voucherTitle: 'SALES ORDER',
        voucherNumber: order.orderNumber,
        date: order.date,
      ),
    );
    bytes.addAll(_customer(b, name: order.customerName, customer: customer));
    bytes.addAll(
      b.leftRight(
        'Ship:',
        EscPosTicketBuilder.dateOnlyFormat.format(order.shipmentDate),
      ),
    );
    bytes.addAll(b.itemTableHeader());
    for (var i = 0; i < order.items.length; i++) {
      final line = order.items[i];
      bytes.addAll(
        b.itemRow(
          serial: i + 1,
          name: line.item.name,
          qty: line.quantity,
          amountText: b.amountOnly(line.total),
          uom: line.displayUom,
        ),
      );
    }
    bytes.addAll(
      _padToMinLength(
        b,
        tableStyle: true,
        buildTail: (tail) {
          final after = <int>[];
          after.addAll(
            tail.totalsBlock(
              symbol: symbol,
              currencyCode: org.currencyCode,
              subTotal: order.subTotal,
              taxTotal: order.taxTotal,
              discountTotal: order.discountTotal,
              total: order.total,
              roundOff: order.roundOff,
              taxLabel: _vatLabel(
                order.items.map((line) => line.taxPercentage),
              ),
            ),
          );
          if (order.notes.trim().isNotEmpty) {
            after.addAll(
              tail.left(
                'Notes: ${tail.truncate(order.notes, tail.columns - 7)}',
              ),
            );
          }
          after.addAll(
            tail.footer(
              salespersonName: salespersonName,
              salespersonPhone: salespersonPhone,
            ),
          );
          return after;
        },
      ),
    );
    return bytes;
  }

  static List<int> _return(
    EscPosTicketBuilder b,
    SalesReturn salesReturn,
    Organization org,
    Customer? customer,
    String? salespersonName,
    String? salespersonPhone,
  ) {
    final symbol = org.currencySymbol;
    final bytes = <int>[];
    bytes.addAll(
      _orgHeader(
        b,
        org,
        voucherTitle: 'SALES RETURN',
        voucherNumber: salesReturn.creditNoteNumber,
        date: salesReturn.date,
      ),
    );
    bytes.addAll(
      _customer(b, name: salesReturn.customerName, customer: customer),
    );
    bytes.addAll(b.itemTableHeader());
    for (var i = 0; i < salesReturn.items.length; i++) {
      final line = salesReturn.items[i];
      bytes.addAll(
        b.itemRow(
          serial: i + 1,
          name: line.invoiceLineItem.item.name,
          qty: line.returnedQuantity,
          amountText: b.amountOnly(line.total),
          uom: line.displayUom,
        ),
      );
    }
    bytes.addAll(
      _padToMinLength(
        b,
        tableStyle: true,
        buildTail: (tail) {
          final after = <int>[];
          after.addAll(
            tail.totalsBlock(
              symbol: symbol,
              currencyCode: org.currencyCode,
              total: salesReturn.total,
              taxLabel: _vatLabel(
                salesReturn.items.map(
                  (line) => line.invoiceLineItem.taxPercentage,
                ),
              ),
            ),
          );
          if (salesReturn.reason.trim().isNotEmpty) {
            after.addAll(
              tail.left(
                'Reason: ${tail.truncate(salesReturn.reason, tail.columns - 8)}',
              ),
            );
          }
          after.addAll(
            tail.footer(
              salespersonName: salespersonName,
              salespersonPhone: salespersonPhone,
            ),
          );
          return after;
        },
      ),
    );
    return bytes;
  }

  static List<int> _receipt(
    EscPosTicketBuilder b,
    ReceiptVoucher receipt,
    Organization org,
    Customer? customer,
    String? salespersonName,
    String? salespersonPhone,
  ) {
    final symbol = org.currencySymbol;
    final bytes = <int>[];
    bytes.addAll(
      _orgHeader(
        b,
        org,
        voucherTitle: 'RECEIPT',
        voucherNumber: receipt.paymentNumber,
        date: receipt.date,
      ),
    );
    bytes.addAll(_customer(b, name: receipt.customerName, customer: customer));
    bytes.addAll(b.divider());
    bytes.addAll(b.leftRight('Mode:', receipt.paymentMode));
    if (receipt.referenceNumber.trim().isNotEmpty) {
      bytes.addAll(b.leftRight('Ref:', receipt.referenceNumber));
    }
    bytes.addAll(
      b.leftRight('Amount:', b.money(receipt.amount, symbol), bold: true),
    );
    bytes.addAll(
      b.amountInWordsBlock(
        total: receipt.amount,
        symbol: symbol,
        currencyCode: org.currencyCode,
      ),
    );
    if (receipt.allocations.isNotEmpty) {
      bytes.addAll(b.divider());
      bytes.addAll(b.left('Allocations:', bold: true));
      for (final a in receipt.allocations) {
        bytes.addAll(
          b.leftRight(
            b.truncate(a.invoiceNumber, b.columns - 12),
            b.money(a.amountApplied, symbol),
          ),
        );
      }
    }
    bytes.addAll(
      _padToMinLength(
        b,
        tableStyle: false,
        buildTail: (tail) => tail.footer(
          salespersonName: salespersonName,
          salespersonPhone: salespersonPhone,
        ),
      ),
    );
    return bytes;
  }

  static List<int> _expense(
    EscPosTicketBuilder b,
    ExpenseEntry expense,
    Organization org,
    String? salespersonName,
    String? salespersonPhone,
  ) {
    final symbol = org.currencySymbol;
    final bytes = <int>[];
    bytes.addAll(
      _orgHeader(
        b,
        org,
        voucherTitle: 'EXPENSE',
        voucherNumber: expense.id,
        date: expense.date,
      ),
    );
    bytes.addAll(b.divider());
    bytes.addAll(b.left('Lines:', bold: true));
    for (final line in expense.lines) {
      final label = line.category.isNotEmpty
          ? line.category
          : (line.description.isNotEmpty ? line.description : 'Expense');
      bytes.addAll(
        b.leftRight(
          b.truncate(label, b.columns - 12),
          b.money(line.amount, symbol),
        ),
      );
      if (line.description.isNotEmpty && line.category.isNotEmpty) {
        bytes.addAll(
          b.left('  ${b.truncate(line.description, b.columns - 2)}'),
        );
      }
    }
    bytes.addAll(
      _padToMinLength(
        b,
        tableStyle: false,
        buildTail: (tail) {
          final after = <int>[];
          after.addAll(
            tail.totalsBlock(
              symbol: symbol,
              currencyCode: org.currencyCode,
              total: expense.amount,
            ),
          );
          after.addAll(
            tail.footer(
              salespersonName: salespersonName,
              salespersonPhone: salespersonPhone,
            ),
          );
          return after;
        },
      ),
    );
    return bytes;
  }

  static List<int> _stockTransfer(
    EscPosTicketBuilder b,
    StockTransfer transfer,
    Organization org,
    String? salespersonName,
    String? salespersonPhone,
  ) {
    final bytes = <int>[];
    final isLoad = transfer.direction == StockTransferDirection.load;
    final voucherTitle = isLoad ? 'ISSUE TO VAN' : 'STOCK UNLOADING';
    final voucherNumber = transfer.transferNumber.isNotEmpty
        ? transfer.transferNumber
        : transfer.id;

    bytes.addAll(
      _orgHeader(
        b,
        org,
        voucherTitle: voucherTitle,
        voucherNumber: voucherNumber,
        date: transfer.date,
      ),
    );

    bytes.addAll(b.divider());
    bytes.addAll(
      b.leftRight(
        'Type:',
        isLoad ? 'Issue to Van (Load)' : 'Stock Unload (Return)',
        bold: true,
      ),
    );
    if (transfer.status.isNotEmpty) {
      bytes.addAll(
        b.leftRight('Status:', transfer.status.toUpperCase()),
      );
    }

    bytes.addAll(b.stockTransferTableHeader());
    for (var i = 0; i < transfer.lines.length; i++) {
      final line = transfer.lines[i];
      bytes.addAll(
        b.stockTransferItemRow(
          serial: i + 1,
          name: line.item.name,
          quantity: line.quantity,
          baseUom: line.item.uom,
          enteredUom: line.uom,
          conversionRate: line.conversionRate,
        ),
      );
    }

    bytes.addAll(
      _padToMinLength(
        b,
        tableStyle: true,
        customEmptyRow: (builder) => builder.emptyStockTransferItemRow(),
        buildTail: (tail) {
          final after = <int>[];
          after.addAll(tail.divider());
          after.addAll(
            tail.leftRight('Total Items:', '${transfer.lines.length}'),
          );
          final totalQty = transfer.totalQuantity;
          final totalQtyStr = totalQty % 1 == 0
              ? totalQty.toInt().toString()
              : totalQty.toStringAsFixed(2);
          final totalCols = (tail.columns / 2).floor().clamp(16, tail.columns);
          after.addAll(
            tail.leftRight(
              'TOTAL QTY',
              totalQtyStr,
              bold: true,
              width: PosTextSize.size2,
              height: PosTextSize.size2,
              layoutColumns: totalCols,
            ),
          );
          if (transfer.notes.trim().isNotEmpty) {
            after.addAll(
              tail.left(
                'Notes: ${tail.truncate(transfer.notes, tail.columns - 7)}',
              ),
            );
          }
          after.addAll(
            tail.footer(
              salespersonName: salespersonName,
              salespersonPhone: salespersonPhone,
            ),
          );
          return after;
        },
      ),
    );
    return bytes;
  }

  /// UAE VAT line label, e.g. `VAT @ 5%`.
  static String _vatLabel(Iterable<double> percentages) {
    final rates = percentages.where((p) => p != 0).toSet();
    if (rates.length == 1) {
      final rate = rates.first;
      final text = rate % 1 == 0 ? '${rate.toInt()}' : '$rate';
      return 'VAT @ $text%';
    }
    return 'VAT @ 5%';
  }

  /// Inserts empty table (or blank) rows so the ticket is at least 8" long.
  static List<int> _padToMinLength(
    EscPosTicketBuilder b, {
    required List<int> Function(EscPosTicketBuilder tail) buildTail,
    required bool tableStyle,
    List<int> Function(EscPosTicketBuilder b)? customEmptyRow,
  }) {
    final tail = EscPosTicketBuilder(
      generator: b.generator,
      paperSize: b.paperSize,
    );
    final tailBytes = buildTail(tail);
    final pad = EscPosTicketBuilder.emptyRowsForMinLength(
      usedUnits: b.lineUnits,
      remainingUnits: tail.lineUnits,
    );
    final bytes = <int>[];
    for (var i = 0; i < pad; i++) {
      if (customEmptyRow != null) {
        bytes.addAll(customEmptyRow(b));
      } else {
        bytes.addAll(tableStyle ? b.emptyItemRow() : b.blankLine());
      }
    }
    bytes.addAll(tailBytes);
    b.absorbPreviewFrom(tail);
    return bytes;
  }
}
