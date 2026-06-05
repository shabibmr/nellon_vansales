import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../domain/models/sales_invoice.dart';
import '../../domain/models/sales_order.dart';
import '../../domain/models/sales_return.dart';
import '../../domain/models/receipt_voucher.dart';
import '../../domain/models/expense_entry.dart';
import '../../domain/models/organization.dart';
import '../../domain/models/customer.dart';

import '../../ui/features/voucher_pdf/templates/invoice_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/sales_order_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/sales_return_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/receipt_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/expense_pdf_template.dart';

/// Enum representing the supported voucher/document formats in the billing system.
enum VoucherType {
  salesInvoice,
  salesOrder,
  salesReturn,
  paymentReceipt,
  expenseVoucher,
}

/// A comprehensive service responsible for compiling PDFs, writing them to disk as temp files,
/// and invoking native Android/iOS Print and Share handlers.
class VoucherPdfService {
  /// Compiles a professional PDF document into memory bytes based on Voucher Type.
  Future<Uint8List> generateVoucherPdf({
    required VoucherType type,
    required dynamic voucher,
    required Organization? org,
    required Customer? customer,
  }) async {
    final doc = switch (type) {
      VoucherType.salesInvoice => InvoicePdfTemplate.generate(voucher as SalesInvoice, org, customer),
      VoucherType.salesOrder => SalesOrderPdfTemplate.generate(voucher as SalesOrder, org, customer),
      VoucherType.salesReturn => SalesReturnPdfTemplate.generate(voucher as SalesReturn, org, customer),
      VoucherType.paymentReceipt => ReceiptPdfTemplate.generate(voucher as ReceiptVoucher, org, customer),
      VoucherType.expenseVoucher => ExpensePdfTemplate.generate(voucher as ExpenseEntry, org),
    };

    return doc.save();
  }

  /// Formats a safe, standard filename for the PDF document depending on its unique numbers.
  String getSafeFilename({
    required VoucherType type,
    required dynamic voucher,
  }) {
    final rawName = switch (type) {
      VoucherType.salesInvoice => 'sales_invoice_${(voucher as SalesInvoice).invoiceNumber}',
      VoucherType.salesOrder => 'sales_order_${(voucher as SalesOrder).orderNumber}',
      VoucherType.salesReturn => 'sales_return_${(voucher as SalesReturn).creditNoteNumber}',
      VoucherType.paymentReceipt => 'payment_receipt_${(voucher as ReceiptVoucher).paymentNumber}',
      VoucherType.expenseVoucher => 'expense_voucher_${(voucher as ExpenseEntry).id}',
    };

    // Keep safe characters only
    final sanitized = rawName.replaceAll(RegExp(r'[^\w\-\.]'), '_');
    return '$sanitized.pdf';
  }

  /// Writes generated PDF bytes into a secure temporary file in the local device filesystem.
  Future<File> savePdfToTempFile(Uint8List bytes, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Launches the native OS printing dialog overlay.
  Future<bool> printPdf(Uint8List bytes, String jobName) async {
    return Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: jobName,
    );
  }

  /// Triggers generic system-wide share sheet with the PDF attachment.
  Future<bool> sharePdfFile(File file, String subject) async {
    final bytes = await file.readAsBytes();
    return Printing.sharePdf(
      bytes: bytes,
      filename: _basename(file.path),
      subject: subject,
    );
  }

  /// Launches platform share sheet configured specifically for Email routing.
  Future<bool> shareViaEmail(File file, String subject, String body) async {
    final bytes = await file.readAsBytes();
    return Printing.sharePdf(
      bytes: bytes,
      filename: _basename(file.path),
      subject: subject,
      body: body,
    );
  }

  /// Launches platform share sheet configured specifically for WhatsApp routing.
  Future<bool> shareViaWhatsApp(File file, String message) async {
    final bytes = await file.readAsBytes();
    return Printing.sharePdf(
      bytes: bytes,
      filename: _basename(file.path),
      body: message,
    );
  }

  String _basename(String path) {
    final idx = path.lastIndexOf(RegExp(r'[\\/]'));
    return idx >= 0 ? path.substring(idx + 1) : path;
  }
}
