import 'package:equatable/equatable.dart';

import '../../../../domain/models/paired_printer.dart';
import '../../../../domain/models/thermal_paper_size.dart';

/// Snapshot of thermal printer UI state for Settings and Thermal Print actions.
class ThermalPrinterState extends Equatable {
  final bool isLoading;
  final bool isPrinting;
  final bool isConnected;
  final bool bluetoothOn;
  final bool permissionGranted;
  /// One-shot: UI should show "Open Settings" dialog for Bluetooth permission.
  final bool needsAppSettings;
  final ThermalPaperSize paperSize;
  final PairedPrinter? preferredPrinter;
  final List<PairedPrinter> bondedDevices;
  final String? statusMessage;
  final String? errorMessage;

  const ThermalPrinterState({
    this.isLoading = false,
    this.isPrinting = false,
    this.isConnected = false,
    this.bluetoothOn = false,
    this.permissionGranted = false,
    this.needsAppSettings = false,
    this.paperSize = ThermalPaperSize.inch4,
    this.preferredPrinter,
    this.bondedDevices = const [],
    this.statusMessage,
    this.errorMessage,
  });

  ThermalPrinterState copyWith({
    bool? isLoading,
    bool? isPrinting,
    bool? isConnected,
    bool? bluetoothOn,
    bool? permissionGranted,
    bool? needsAppSettings,
    bool clearNeedsAppSettings = false,
    ThermalPaperSize? paperSize,
    PairedPrinter? preferredPrinter,
    bool clearPreferredPrinter = false,
    List<PairedPrinter>? bondedDevices,
    String? statusMessage,
    bool clearStatus = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ThermalPrinterState(
      isLoading: isLoading ?? this.isLoading,
      isPrinting: isPrinting ?? this.isPrinting,
      isConnected: isConnected ?? this.isConnected,
      bluetoothOn: bluetoothOn ?? this.bluetoothOn,
      permissionGranted: permissionGranted ?? this.permissionGranted,
      needsAppSettings: clearNeedsAppSettings
          ? false
          : (needsAppSettings ?? this.needsAppSettings),
      paperSize: paperSize ?? this.paperSize,
      preferredPrinter: clearPreferredPrinter
          ? null
          : (preferredPrinter ?? this.preferredPrinter),
      bondedDevices: bondedDevices ?? this.bondedDevices,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        isPrinting,
        isConnected,
        bluetoothOn,
        permissionGranted,
        needsAppSettings,
        paperSize,
        preferredPrinter,
        bondedDevices,
        statusMessage,
        errorMessage,
      ];
}
