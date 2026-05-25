import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/voucher_pdf_service.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/customer.dart';
import 'voucher_pdf_event.dart';
import 'voucher_pdf_state.dart';

/// Central BLoC orchestrating document serialization and platform action integrations.
class VoucherPdfBloc extends Bloc<VoucherPdfEvent, VoucherPdfState> {
  final VoucherPdfService pdfService;
  final HiveDatabaseService dbService;

  VoucherPdfBloc({
    required this.pdfService,
    required this.dbService,
  }) : super(VoucherPdfInitial()) {
    on<GenerateVoucherPdfPreviewRequested>(_onPreviewRequested);
    on<PrintVoucherPdfRequested>(_onPrintRequested);
    on<ShareVoucherPdfRequested>(_onShareRequested);
    on<EmailVoucherPdfRequested>(_onEmailRequested);
    on<WhatsAppVoucherPdfRequested>(_onWhatsAppRequested);
    on<ResetVoucherPdfState>(_onResetState);
  }

  /// Extracts the customer (if applicable) for the given voucher.
  Customer? _getCustomer(VoucherType type, dynamic voucher) {
    String? customerId;
    if (type == VoucherType.salesInvoice) {
      customerId = (voucher as SalesInvoice).customerId;
    } else if (type == VoucherType.salesReturn) {
      customerId = (voucher as SalesReturn).customerId;
    } else if (type == VoucherType.paymentReceipt) {
      customerId = (voucher as ReceiptVoucher).customerId;
    }

    if (customerId == null) return null;

    try {
      final customers = dbService.getCustomers();
      for (final customer in customers) {
        if (customer.id == customerId) {
          return customer;
        }
      }
    } catch (_) {
      // Fallback if loading customers errors
    }
    return null;
  }

  /// Builds PDF bytes asynchronously.
  Future<Uint8List> _buildBytes(VoucherType type, dynamic voucher) async {
    final org = dbService.getOrganization();
    final customer = _getCustomer(type, voucher);

    return pdfService.generateVoucherPdf(
      type: type,
      voucher: voucher,
      org: org,
      customer: customer,
    );
  }

  Future<void> _onPreviewRequested(
    GenerateVoucherPdfPreviewRequested event,
    Emitter<VoucherPdfState> emit,
  ) async {
    emit(VoucherPdfLoading());
    try {
      final bytes = await _buildBytes(event.type, event.voucher);
      final filename = pdfService.getSafeFilename(type: event.type, voucher: event.voucher);
      emit(VoucherPdfReady(pdfBytes: bytes, filename: filename));
    } catch (e) {
      emit(VoucherPdfFailure('Failed to generate PDF preview: ${e.toString()}'));
    }
  }

  Future<void> _onPrintRequested(
    PrintVoucherPdfRequested event,
    Emitter<VoucherPdfState> emit,
  ) async {
    emit(VoucherPdfLoading());
    try {
      final bytes = await _buildBytes(event.type, event.voucher);
      final filename = pdfService.getSafeFilename(type: event.type, voucher: event.voucher);
      final printed = await pdfService.printPdf(bytes, filename);
      if (printed) {
        emit(const VoucherPdfActionSuccess('Document sent to print spooler'));
      } else {
        emit(VoucherPdfInitial()); // Cancelled by user or failed silently
      }
    } catch (e) {
      emit(VoucherPdfFailure('Failed to compile or print document: ${e.toString()}'));
    }
  }

  Future<void> _onShareRequested(
    ShareVoucherPdfRequested event,
    Emitter<VoucherPdfState> emit,
  ) async {
    emit(VoucherPdfLoading());
    try {
      final bytes = await _buildBytes(event.type, event.voucher);
      final filename = pdfService.getSafeFilename(type: event.type, voucher: event.voucher);
      final file = await pdfService.savePdfToTempFile(bytes, filename);
      await pdfService.sharePdfFile(file, 'Share Document: $filename');
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
      final filename = pdfService.getSafeFilename(type: event.type, voucher: event.voucher);
      final file = await pdfService.savePdfToTempFile(bytes, filename);
      await pdfService.shareViaEmail(
        file,
        'Official Document: $filename',
        'Please find attached the official generated document PDF ($filename).\n\nBest regards,\nRoute Fleet Management',
      );
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
      final filename = pdfService.getSafeFilename(type: event.type, voucher: event.voucher);
      final file = await pdfService.savePdfToTempFile(bytes, filename);
      await pdfService.shareViaWhatsApp(
        file,
        'Hi, please find attached the official $filename generated during our route sales delivery.',
      );
      emit(const VoucherPdfActionSuccess('WhatsApp sharing active'));
    } catch (e) {
      emit(VoucherPdfFailure('WhatsApp share failed: ${e.toString()}'));
    }
  }

  void _onResetState(ResetVoucherPdfState event, Emitter<VoucherPdfState> emit) {
    emit(VoucherPdfInitial());
  }
}
