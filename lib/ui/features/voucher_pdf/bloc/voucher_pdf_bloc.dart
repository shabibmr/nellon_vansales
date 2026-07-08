import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdf/pdf.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/customer.dart';
import 'voucher_pdf_event.dart';
import 'voucher_pdf_state.dart';

/// Central BLoC orchestrating document serialization and platform action integrations.
class VoucherPdfBloc extends Bloc<VoucherPdfEvent, VoucherPdfState> {
  final VoucherPdfRepository pdfService;
  final HiveDatabaseService dbService;

  VoucherPdfBloc({required this.pdfService, required this.dbService})
    : super(VoucherPdfInitial()) {
    on<GenerateVoucherPdfPreviewRequested>(_onPreviewRequested);
    on<PrintVoucherPdfRequested>(_onPrintRequested);
    on<ShareVoucherPdfRequested>(_onShareRequested);
    on<EmailVoucherPdfRequested>(_onEmailRequested);
    on<WhatsAppVoucherPdfRequested>(_onWhatsAppRequested);
    on<ResetVoucherPdfState>(_onResetState);
  }

  /// Extracts the customer id (if applicable) for the given voucher.
  String? _customerIdFor(VoucherType type, dynamic voucher) {
    return switch (type) {
      VoucherType.salesInvoice => (voucher as SalesInvoice).customerId,
      VoucherType.salesOrder => (voucher as SalesOrder).customerId,
      VoucherType.salesReturn => (voucher as SalesReturn).customerId,
      VoucherType.paymentReceipt => (voucher as ReceiptVoucher).customerId,
      VoucherType.expenseVoucher => null,
    };
  }

  /// Looks up the customer (if applicable) for the given voucher via an
  /// indexed cache lookup rather than scanning the full customer master list.
  Customer? _getCustomer(VoucherType type, dynamic voucher) {
    final customerId = _customerIdFor(type, voucher);
    if (customerId == null) return null;
    return dbService.getCustomerById(customerId);
  }

  /// Builds PDF bytes asynchronously.
  Future<Uint8List> _buildBytes(
    VoucherType type,
    dynamic voucher, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final org = dbService.getOrganization();
    if (org == null) {
      throw Exception('Organization data not loaded — please sync first');
    }
    final customer = _getCustomer(type, voucher);

    return pdfService.generateVoucherPdf(
      type: type,
      voucher: voucher,
      org: org,
      customer: customer,
      pageFormat: pageFormat,
    );
  }

  Future<void> _onPreviewRequested(
    GenerateVoucherPdfPreviewRequested event,
    Emitter<VoucherPdfState> emit,
  ) async {
    emit(VoucherPdfLoading());
    try {
      final bytes = await _buildBytes(event.type, event.voucher);
      final filename = pdfService.getSafeFilename(
        type: event.type,
        voucher: event.voucher,
      );
      emit(VoucherPdfReady(pdfBytes: bytes, filename: filename));
    } catch (e) {
      emit(
        VoucherPdfFailure('Failed to generate PDF preview: ${e.toString()}'),
      );
    }
  }

  Future<void> _onPrintRequested(
    PrintVoucherPdfRequested event,
    Emitter<VoucherPdfState> emit,
  ) async {
    emit(VoucherPdfLoading());
    try {
      final filename = pdfService.getSafeFilename(
        type: event.type,
        voucher: event.voucher,
      );
      final printed = await pdfService.printPdf(
        (format) => _buildBytes(event.type, event.voucher, pageFormat: format),
        filename,
      );
      if (printed) {
        emit(const VoucherPdfActionSuccess('Document sent to print spooler'));
      } else {
        emit(const VoucherPdfFailure('Print did not complete'));
      }
    } catch (e) {
      emit(
        VoucherPdfFailure(
          'Failed to compile or print document: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onShareRequested(
    ShareVoucherPdfRequested event,
    Emitter<VoucherPdfState> emit,
  ) async {
    emit(VoucherPdfLoading());
    try {
      final bytes = await _buildBytes(event.type, event.voucher);
      final filename = pdfService.getSafeFilename(
        type: event.type,
        voucher: event.voucher,
      );
      final file = await pdfService.savePdfToTempFile(bytes, filename);
      try {
        await pdfService.sharePdfFile(file, 'Share Document: $filename');
      } finally {
        await file.delete().catchError((_) => file);
      }
      emit(const VoucherPdfActionSuccess('Document shared successfully'));
    } catch (e) {
      emit(VoucherPdfFailure('Sharing failed: ${e.toString()}'));
    }
  }

  Future<void> _onEmailRequested(
    EmailVoucherPdfRequested event,
    Emitter<VoucherPdfState> emit,
  ) async {
    emit(VoucherPdfLoading());
    try {
      final bytes = await _buildBytes(event.type, event.voucher);
      final filename = pdfService.getSafeFilename(
        type: event.type,
        voucher: event.voucher,
      );
      final file = await pdfService.savePdfToTempFile(bytes, filename);
      try {
        await pdfService.shareViaEmail(
          file,
          'Official Document: $filename',
          'Please find attached the official generated document PDF ($filename).\n\nBest regards,\nRoute Fleet Management',
        );
      } finally {
        await file.delete().catchError((_) => file);
      }
      emit(const VoucherPdfActionSuccess('Email composition active'));
    } catch (e) {
      emit(VoucherPdfFailure('Email draft failed: ${e.toString()}'));
    }
  }

  Future<void> _onWhatsAppRequested(
    WhatsAppVoucherPdfRequested event,
    Emitter<VoucherPdfState> emit,
  ) async {
    emit(VoucherPdfLoading());
    try {
      final bytes = await _buildBytes(event.type, event.voucher);
      final filename = pdfService.getSafeFilename(
        type: event.type,
        voucher: event.voucher,
      );
      final file = await pdfService.savePdfToTempFile(bytes, filename);
      try {
        await pdfService.shareViaWhatsApp(
          file,
          'Hi, please find attached the official $filename generated during our route sales delivery.',
        );
      } finally {
        await file.delete().catchError((_) => file);
      }
      emit(const VoucherPdfActionSuccess('WhatsApp sharing active'));
    } catch (e) {
      emit(VoucherPdfFailure('WhatsApp share failed: ${e.toString()}'));
    }
  }

  void _onResetState(
    ResetVoucherPdfState event,
    Emitter<VoucherPdfState> emit,
  ) {
    emit(VoucherPdfInitial());
  }
}
