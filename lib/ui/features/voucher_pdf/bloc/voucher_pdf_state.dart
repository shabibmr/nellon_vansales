import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Base class for all Voucher PDF states.
abstract class VoucherPdfState extends Equatable {
  const VoucherPdfState();

  @override
  List<Object?> get props => [];
}

/// Starting state before any action is requested.
class VoucherPdfInitial extends VoucherPdfState {}

/// Asynchronous operations are in progress. Shows loading spinners in the UI.
class VoucherPdfLoading extends VoucherPdfState {}

/// Compiled PDF bytes are ready for in-app preview display.
class VoucherPdfReady extends VoucherPdfState {
  final Uint8List pdfBytes;
  final String filename;

  const VoucherPdfReady({
    required this.pdfBytes,
    required this.filename,
  });

  @override
  List<Object?> get props => [pdfBytes, filename];
}

/// Print or sharing actions completed successfully on platform side.
class VoucherPdfActionSuccess extends VoucherPdfState {
  final String message;

  const VoucherPdfActionSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

/// General failure state when compilation, writing to disk, or platform APIs fail.
class VoucherPdfFailure extends VoucherPdfState {
  final String error;

  const VoucherPdfFailure(this.error);

  @override
  List<Object?> get props => [error];
}
