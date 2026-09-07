import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/models/sales_invoice.dart';
import '../../domain/models/sales_order.dart';
import '../../domain/models/sales_return.dart';
import '../../domain/models/receipt_voucher.dart';
import '../../domain/models/expense_entry.dart';
import '../../domain/models/stock_transfer.dart';
import '../../domain/models/organization.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/salesperson.dart';
import '../../domain/repositories/voucher_pdf_repository.dart';

import '../../ui/features/voucher_pdf/templates/invoice_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/sales_order_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/sales_return_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/receipt_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/expense_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/stock_transfer_pdf_template.dart';
import '../../ui/features/voucher_pdf/templates/shared_pdf_template.dart';

/// A comprehensive service responsible for compiling PDFs, writing them to disk as temp files,
/// and invoking native Android/iOS Print and Share handlers.
class VoucherPdfService implements VoucherPdfRepository {
  /// Default supervisor contact for voucher PDFs.
  static const String defaultSupervisorPhone = SharedPdfTemplate.supervisorContact;

  /// Asset path for the brand logo rendered on voucher PDFs.
  static const String defaultLogoAssetPath =
      'assets/images/nellon-logo-cropped.png';

  Uint8List? _cachedLogoBytes;

  /// Loads and caches the brand logo bytes for PDF letterheads.
  Future<Uint8List?> getLogoBytes([
    String assetPath = defaultLogoAssetPath,
  ]) async {
    if (_cachedLogoBytes != null) return _cachedLogoBytes;
    try {
      final byteData = await rootBundle.load(assetPath);
      _cachedLogoBytes = byteData.buffer.asUint8List();
    } catch (_) {
      // In headless unit tests or missing asset environments, return null gracefully.
    }
    return _cachedLogoBytes;
  }

  /// Filename prefixes used by [getSafeFilename], reused by [clearStaleTempFiles]
  /// to recognize voucher PDFs left behind by a previous app session.
  static const List<String> _filenamePrefixes = [
    'sales_invoice_',
    'sales_order_',
    'sales_return_',
    'payment_receipt_',
    'expense_voucher_',
    'stock_transfer_',
  ];

  @override
  Future<Uint8List> generateVoucherPdf({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    Salesperson? salesperson,
    String? supervisorPhone = defaultSupervisorPhone,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    Uint8List? logoBytes,
  }) async {
    final effectiveLogoBytes = logoBytes ?? await getLogoBytes();
    final logoImage = effectiveLogoBytes != null
        ? pw.MemoryImage(effectiveLogoBytes)
        : null;

    final doc = switch (type) {
      VoucherType.salesInvoice => InvoicePdfTemplate.generate(
        voucher as SalesInvoice,
        org,
        customer,
        salesperson: salesperson,
        supervisorPhone: supervisorPhone,
        pageFormat: pageFormat,
        logoImage: logoImage,
      ),
      VoucherType.salesOrder => SalesOrderPdfTemplate.generate(
        voucher as SalesOrder,
        org,
        customer,
        salesperson: salesperson,
        supervisorPhone: supervisorPhone,
        pageFormat: pageFormat,
        logoImage: logoImage,
      ),
      VoucherType.salesReturn => SalesReturnPdfTemplate.generate(
        voucher as SalesReturn,
        org,
        customer,
        salesperson: salesperson,
        supervisorPhone: supervisorPhone,
        pageFormat: pageFormat,
        logoImage: logoImage,
      ),
      VoucherType.paymentReceipt => ReceiptPdfTemplate.generate(
        voucher as ReceiptVoucher,
        org,
        customer,
        salesperson: salesperson,
        supervisorPhone: supervisorPhone,
        pageFormat: pageFormat,
        logoImage: logoImage,
      ),
      VoucherType.expenseVoucher => ExpensePdfTemplate.generate(
        voucher as ExpenseEntry,
        org,
        salesperson: salesperson,
        supervisorPhone: supervisorPhone,
        pageFormat: pageFormat,
        logoImage: logoImage,
      ),
      VoucherType.stockTransfer => StockTransferPdfTemplate.generate(
        voucher as StockTransfer,
        org,
        salesperson: salesperson,
        supervisorPhone: supervisorPhone,
        pageFormat: pageFormat,
        logoImage: logoImage,
      ),
    };

    return doc.save();
  }

  @override
  String getSafeFilename({
    required VoucherType type,
    required dynamic voucher,
  }) {
    final rawName = switch (type) {
      VoucherType.salesInvoice =>
        'sales_invoice_${(voucher as SalesInvoice).invoiceNumber}',
      VoucherType.salesOrder =>
        'sales_order_${(voucher as SalesOrder).orderNumber}',
      VoucherType.salesReturn =>
        'sales_return_${(voucher as SalesReturn).creditNoteNumber}',
      VoucherType.paymentReceipt =>
        'payment_receipt_${(voucher as ReceiptVoucher).paymentNumber}',
      VoucherType.expenseVoucher =>
        'expense_voucher_${(voucher as ExpenseEntry).id}',
      VoucherType.stockTransfer => () {
          final st = voucher as StockTransfer;
          return 'stock_transfer_${st.transferNumber.isNotEmpty ? st.transferNumber : st.id}';
        }(),
    };

    // Keep safe characters only
    final sanitized = rawName.replaceAll(RegExp(r'[^\w\-\.]'), '_');
    return '$sanitized.pdf';
  }

  @override
  Future<File> savePdfToTempFile(Uint8List bytes, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  @override
  Future<bool> printPdf(
    Future<Uint8List> Function(PdfPageFormat format) buildBytes,
    String jobName,
  ) async {
    return Printing.layoutPdf(onLayout: buildBytes, name: jobName);
  }

  @override
  Future<bool> sharePdfFile(File file, String subject) async {
    final bytes = await file.readAsBytes();
    return Printing.sharePdf(
      bytes: bytes,
      filename: _basename(file.path),
      subject: subject,
    );
  }

  @override
  Future<bool> shareViaEmail(File file, String subject, String body) async {
    final bytes = await file.readAsBytes();
    return Printing.sharePdf(
      bytes: bytes,
      filename: _basename(file.path),
      subject: subject,
      body: body,
    );
  }

  @override
  Future<bool> shareViaWhatsApp(File file, String message) async {
    final bytes = await file.readAsBytes();
    return Printing.sharePdf(
      bytes: bytes,
      filename: _basename(file.path),
      body: message,
    );
  }

  /// Removes any voucher PDF files left behind in the OS temp directory by a
  /// previous session (e.g. if the app was killed before per-share cleanup ran).
  Future<void> clearStaleTempFiles() async {
    final tempDir = await getTemporaryDirectory();
    if (!await tempDir.exists()) return;
    await for (final entity in tempDir.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      if (name.endsWith('.pdf') &&
          _filenamePrefixes.any((prefix) => name.startsWith(prefix))) {
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort cleanup; ignore files that are locked/already gone.
        }
      }
    }
  }

  String _basename(String path) {
    final idx = path.lastIndexOf(RegExp(r'[\\/]'));
    return idx >= 0 ? path.substring(idx + 1) : path;
  }
}
