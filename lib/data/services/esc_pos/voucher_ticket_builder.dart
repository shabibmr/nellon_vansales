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
    bytes.addAll(b.center('PRINTER TEST', bold: true));
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
    bytes.addAll(b.doubleDivider());
    bytes.addAll(b.center('If readable, setup OK'));
    bytes.addAll(b.cut());
    return bytes;
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
      b.header(
        orgName: org.name,
        voucherTitle: 'INVOICE',
        voucherNumber: invoice.invoiceNumber,
        date: invoice.date,
      ),
    );
    bytes.addAll(
      b.customerBlock(
        name: invoice.customerName,
        phone: customer?.phone,
        address: customer?.address,
      ),
    );
    bytes.addAll(
      b.leftRight('Due:', EscPosTicketBuilder.dateOnlyFormat.format(invoice.dueDate)),
    );
    bytes.addAll(b.itemTableHeader());
    for (final line in invoice.items) {
      bytes.addAll(
        b.itemRow(
          name: line.item.name,
          qty: line.quantity,
          amountText: b.money(line.total, symbol),
          uom: line.displayUom,
        ),
      );
    }
    bytes.addAll(
      b.totalsBlock(
        symbol: symbol,
        subTotal: invoice.subTotal,
        taxTotal: invoice.taxTotal,
        discountTotal: invoice.discountTotal,
        total: invoice.total,
        roundOff: invoice.roundOff,
      ),
    );
    if (invoice.notes.trim().isNotEmpty) {
      bytes.addAll(b.left('Notes: ${b.truncate(invoice.notes, b.columns - 7)}'));
    }
    bytes.addAll(b.footer(salespersonName: salespersonName));
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
      b.header(
        orgName: org.name,
        voucherTitle: 'SALES ORDER',
        voucherNumber: order.orderNumber,
        date: order.date,
      ),
    );
    bytes.addAll(
      b.customerBlock(
        name: order.customerName,
        phone: customer?.phone,
        address: customer?.address,
      ),
    );
    bytes.addAll(
      b.leftRight(
        'Ship:',
        EscPosTicketBuilder.dateOnlyFormat.format(order.shipmentDate),
      ),
    );
    bytes.addAll(b.itemTableHeader());
    for (final line in order.items) {
      bytes.addAll(
        b.itemRow(
          name: line.item.name,
          qty: line.quantity,
          amountText: b.money(line.total, symbol),
          uom: line.displayUom,
        ),
      );
    }
    bytes.addAll(
      b.totalsBlock(
        symbol: symbol,
        subTotal: order.subTotal,
        taxTotal: order.taxTotal,
        discountTotal: order.discountTotal,
        total: order.total,
        roundOff: order.roundOff,
      ),
    );
    if (order.notes.trim().isNotEmpty) {
      bytes.addAll(b.left('Notes: ${b.truncate(order.notes, b.columns - 7)}'));
    }
    bytes.addAll(b.footer(salespersonName: salespersonName));
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
      b.header(
        orgName: org.name,
        voucherTitle: 'SALES RETURN',
        voucherNumber: salesReturn.creditNoteNumber,
        date: salesReturn.date,
      ),
    );
    bytes.addAll(
      b.customerBlock(
        name: salesReturn.customerName,
        phone: customer?.phone,
        address: customer?.address,
      ),
    );
    bytes.addAll(b.itemTableHeader());
    for (final line in salesReturn.items) {
      bytes.addAll(
        b.itemRow(
          name: line.invoiceLineItem.item.name,
          qty: line.returnedQuantity,
          amountText: b.money(line.total, symbol),
          uom: line.displayUom,
        ),
      );
    }
    bytes.addAll(
      b.totalsBlock(symbol: symbol, total: salesReturn.total),
    );
    if (salesReturn.reason.trim().isNotEmpty) {
      bytes.addAll(
        b.left('Reason: ${b.truncate(salesReturn.reason, b.columns - 8)}'),
      );
    }
    bytes.addAll(b.footer(salespersonName: salespersonName));
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
      b.header(
        orgName: org.name,
        voucherTitle: 'RECEIPT',
        voucherNumber: receipt.paymentNumber,
        date: receipt.date,
      ),
    );
    bytes.addAll(
      b.customerBlock(
        name: receipt.customerName,
        phone: customer?.phone,
        address: customer?.address,
      ),
    );
    bytes.addAll(b.divider());
    bytes.addAll(leftRightSafe(b, 'Mode:', receipt.paymentMode));
    if (receipt.referenceNumber.trim().isNotEmpty) {
      bytes.addAll(leftRightSafe(b, 'Ref:', receipt.referenceNumber));
    }
    bytes.addAll(
      b.leftRight('Amount:', b.money(receipt.amount, symbol), bold: true),
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
    bytes.addAll(b.footer(salespersonName: salespersonName));
    return bytes;
  }

  static List<int> leftRightSafe(
    EscPosTicketBuilder b,
    String left,
    String right,
  ) {
    return b.leftRight(left, right);
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
      b.header(
        orgName: org.name,
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
      b.totalsBlock(symbol: symbol, total: expense.amount),
    );
    bytes.addAll(b.footer(salespersonName: salespersonName));
    return bytes;
  }
}
