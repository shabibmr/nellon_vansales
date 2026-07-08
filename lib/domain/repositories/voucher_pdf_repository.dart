import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import '../models/organization.dart';
import '../models/customer.dart';

/// Enum representing the supported voucher/document formats in the billing system.
enum VoucherType {
  salesInvoice,
  salesOrder,
  salesReturn,
  paymentReceipt,
  expenseVoucher,
}

/// Abstract contract for compiling voucher PDFs and invoking native
/// print/share/email/WhatsApp platform handlers.
abstract class VoucherPdfRepository {
  /// Compiles a professional PDF document into memory bytes based on Voucher Type.
  Future<Uint8List> generateVoucherPdf({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    PdfPageFormat pageFormat,
  });

  /// Formats a safe, standard filename for the PDF document depending on its unique numbers.
  String getSafeFilename({required VoucherType type, required dynamic voucher});

  /// Writes generated PDF bytes into a secure temporary file in the local device filesystem.
  Future<File> savePdfToTempFile(Uint8List bytes, String filename);

  /// Launches the native OS printing dialog overlay, rebuilding bytes for
  /// whichever [PdfPageFormat] the dialog negotiates.
  Future<bool> printPdf(
    Future<Uint8List> Function(PdfPageFormat format) buildBytes,
    String jobName,
  );

  /// Triggers generic system-wide share sheet with the PDF attachment.
  Future<bool> sharePdfFile(File file, String subject);

  /// Launches platform share sheet configured specifically for Email routing.
  Future<bool> shareViaEmail(File file, String subject, String body);

  /// Launches platform share sheet configured specifically for WhatsApp routing.
  Future<bool> shareViaWhatsApp(File file, String message);
}
