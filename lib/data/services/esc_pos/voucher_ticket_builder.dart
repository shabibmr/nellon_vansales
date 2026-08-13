import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../../domain/models/customer.dart';
import '../../../domain/models/expense_entry.dart';
import '../../../domain/models/organization.dart';
import '../../../domain/models/receipt_voucher.dart';
import '../../../domain/models/sales_invoice.dart';
import '../../../domain/models/sales_order.dart';
import '../../../domain/models/sales_return.dart';
import '../../../domain/models/thermal_paper_size.dart';
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
          _invoice(b, voucher as SalesInvoice, org, customer, salespersonName),
        );
      case VoucherType.salesOrder:
        bytes.addAll(
          _order(b, voucher as SalesOrder, org, customer, salespersonName),
        );
      case VoucherType.salesReturn:
        bytes.addAll(
          _return(b, voucher as SalesReturn, org, customer, salespersonName),
        );
      case VoucherType.paymentReceipt:
        bytes.addAll(
          _receipt(b, voucher as ReceiptVoucher, org, customer, salespersonName),
        );
      case VoucherType.expenseVoucher:
        bytes.addAll(
          _expense(b, voucher as ExpenseEntry, org, salespersonName),
        );
    }

    return bytes;
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
    final totalCols = (paperSize.columns / 2).floor().clamp(16, paperSize.columns);
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
          after.addAll(tail.footer(salespersonName: salespersonName));
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
          after.addAll(tail.footer(salespersonName: salespersonName));
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
                salesReturn.items
                    .map((line) => line.invoiceLineItem.taxPercentage),
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
          after.addAll(tail.footer(salespersonName: salespersonName));
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
        buildTail: (tail) => tail.footer(salespersonName: salespersonName),
      ),
    );
    return bytes;
  }

  static List<int> _expense(
    EscPosTicketBuilder b,
    ExpenseEntry expense,
    Organization org,
    String? salespersonName,
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
          after.addAll(tail.footer(salespersonName: salespersonName));
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
      bytes.addAll(tableStyle ? b.emptyItemRow() : b.blankLine());
    }
    bytes.addAll(tailBytes);
    return bytes;
  }
}
