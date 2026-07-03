import 'package:equatable/equatable.dart';
import '../../../../data/services/voucher_pdf_service.dart';

/// Base class for all Voucher PDF events.
abstract class VoucherPdfEvent extends Equatable {
  const VoucherPdfEvent();

  @override
  List<Object?> get props => [];
}

/// Event triggered when the user wants to preview the PDF within the app.
class GenerateVoucherPdfPreviewRequested extends VoucherPdfEvent {
  final VoucherType type;
  final dynamic voucher;

  const GenerateVoucherPdfPreviewRequested({
    required this.type,
    required this.voucher,
  });

  @override
  List<Object?> get props => [type, voucher];
}

/// Event triggered when the user wants to print the PDF.
class PrintVoucherPdfRequested extends VoucherPdfEvent {
  final VoucherType type;
  final dynamic voucher;

  const PrintVoucherPdfRequested({required this.type, required this.voucher});

  @override
  List<Object?> get props => [type, voucher];
}

/// Event triggered when the user wants to open the generic system share sheet for the PDF.
class ShareVoucherPdfRequested extends VoucherPdfEvent {
  final VoucherType type;
  final dynamic voucher;

  const ShareVoucherPdfRequested({required this.type, required this.voucher});

  @override
  List<Object?> get props => [type, voucher];
}

/// Event triggered when the user wants to share the PDF directly via Email.
class EmailVoucherPdfRequested extends VoucherPdfEvent {
  final VoucherType type;
  final dynamic voucher;

  const EmailVoucherPdfRequested({required this.type, required this.voucher});

  @override
  List<Object?> get props => [type, voucher];
}

/// Event triggered when the user wants to share the PDF directly via WhatsApp.
class WhatsAppVoucherPdfRequested extends VoucherPdfEvent {
  final VoucherType type;
  final dynamic voucher;

  const WhatsAppVoucherPdfRequested({
    required this.type,
    required this.voucher,
  });

  @override
  List<Object?> get props => [type, voucher];
}

/// Resets the PDF bloc state back to Initial.
class ResetVoucherPdfState extends VoucherPdfEvent {}
