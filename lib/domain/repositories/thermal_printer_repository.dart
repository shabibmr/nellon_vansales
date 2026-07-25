import '../models/customer.dart';
import '../models/organization.dart';
import '../models/paired_printer.dart';
import '../models/thermal_paper_size.dart';
import 'voucher_pdf_repository.dart';

/// Contract for Bluetooth ESC/POS thermal printing (scan / pair prefs / print).
abstract class ThermalPrinterRepository {
  /// Whether OS Bluetooth radio is powered on.
  Future<bool> isBluetoothOn();

  /// Whether Bluetooth connect permission is granted (Android 12+).
  Future<bool> isBluetoothPermissionGranted();

  /// Bonded (Android) or nearby (iOS) Bluetooth devices.
  Future<List<PairedPrinter>> getBondedDevices();

  /// Connects to [printer] by MAC. Returns true on success.
  Future<bool> connect(PairedPrinter printer);

  /// Disconnects the current session if any.
  Future<void> disconnect();

  /// True when a live Bluetooth session is open.
  Future<bool> get isConnected;

  /// Last preferred printer (may be null).
  PairedPrinter? get preferredPrinter;

  /// Persists or clears the preferred printer.
  Future<void> setPreferredPrinter(PairedPrinter? printer);

  /// Active paper size (default [ThermalPaperSize.inch4]).
  ThermalPaperSize get paperSize;

  /// Persists paper size used by all ticket builds.
  Future<void> setPaperSize(ThermalPaperSize size);

  /// Builds an ESC/POS ticket for [voucher] and writes it to the connected printer.
  ///
  /// Connects to [preferredPrinter] automatically when not already connected.
  Future<void> printVoucher({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    String? salespersonName,
  });

  /// Prints a short calibration ticket showing paper size and connection info.
  Future<void> printTestPage();
}
