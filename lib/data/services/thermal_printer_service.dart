import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../domain/models/customer.dart';
import '../../domain/models/organization.dart';
import '../../domain/models/paired_printer.dart';
import '../../domain/models/thermal_paper_size.dart';
import '../../domain/repositories/thermal_printer_repository.dart';
import '../../domain/repositories/voucher_pdf_repository.dart';
import '../models/customer_model.dart';
import 'esc_pos/voucher_ticket_builder.dart';
import 'hive_database_service.dart';
import 'zoho_api_client.dart';

/// Bluetooth ESC/POS printer implementation for Android van devices.
///
/// Persists preferred printer and paper size in Hive master box.
class ThermalPrinterService implements ThermalPrinterRepository {
  ThermalPrinterService({
    required HiveDatabaseService dbService,
    required ZohoApiClient apiClient,
  })  : _db = dbService,
        _api = apiClient;

  final HiveDatabaseService _db;
  final ZohoApiClient _api;

  @override
  Future<bool> isBluetoothOn() => PrintBluetoothThermal.bluetoothEnabled;

  @override
  Future<bool> isBluetoothPermissionGranted() =>
      PrintBluetoothThermal.isPermissionBluetoothGranted;

  @override
  Future<List<PairedPrinter>> getBondedDevices() async {
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices
        .map(
          (d) => PairedPrinter(name: d.name, macAddress: d.macAdress),
        )
        .where((p) => p.macAddress.isNotEmpty)
        .toList();
  }

  @override
  Future<bool> connect(PairedPrinter printer) async {
    if (printer.macAddress.isEmpty) return false;
    final ok = await PrintBluetoothThermal.connect(
      macPrinterAddress: printer.macAddress,
    );
    if (ok) {
      await setPreferredPrinter(printer);
    }
    return ok;
  }

  @override
  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }

  @override
  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  @override
  PairedPrinter? get preferredPrinter {
    final map = _db.getPreferredBluetoothPrinter();
    if (map == null) return null;
    try {
      return PairedPrinter.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setPreferredPrinter(PairedPrinter? printer) async {
    await _db.setPreferredBluetoothPrinter(printer?.toJson());
  }

  @override
  ThermalPaperSize get paperSize =>
      ThermalPaperSizeX.fromStorageKey(_db.thermalPaperSizeKey);

  @override
  Future<void> setPaperSize(ThermalPaperSize size) async {
    await _db.setThermalPaperSizeKey(size.storageKey);
  }

  Future<void> _ensureConnected() async {
    if (await isConnected) return;
    final preferred = preferredPrinter;
    if (preferred == null) {
      throw Exception(
        'No printer selected. Open Settings and choose a Bluetooth printer.',
      );
    }
    final btOn = await isBluetoothOn();
    if (!btOn) {
      throw Exception('Bluetooth is off. Turn on Bluetooth and try again.');
    }
    final permitted = await isBluetoothPermissionGranted();
    if (!permitted) {
      throw Exception(
        'Bluetooth permission denied. Allow Bluetooth access in system settings.',
      );
    }
    final ok = await connect(preferred);
    if (!ok) {
      throw Exception(
        'Could not connect to ${preferred.name}. Pair the printer in Android Bluetooth settings, then retry.',
      );
    }
  }

  Future<void> _writeBytes(List<int> bytes) async {
    await _ensureConnected();
    var ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      await disconnect();
      await _ensureConnected();
      ok = await PrintBluetoothThermal.writeBytes(bytes);
    }
    if (!ok) {
      throw Exception('Failed to send data to the printer. Try again.');
    }
  }

  @override
  Future<void> printVoucher({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    String? salespersonName,
  }) async {
    final resolved = await _enrichCustomerForPrint(customer);
    final bytes = await VoucherTicketBuilder.build(
      type: type,
      voucher: voucher,
      org: org,
      customer: resolved,
      paperSize: paperSize,
      salespersonName: salespersonName,
    );
    await _writeBytes(bytes);
  }

  /// List contacts never include tax_reg_no. One detail GET fills Hive when online.
  Future<Customer?> _enrichCustomerForPrint(Customer? customer) async {
    if (customer == null || customer.id.isEmpty) return customer;
    if (customer.trn.trim().isNotEmpty) return customer;

    try {
      final detail = await _api.fetchContactDetail(customer.id);
      if (detail.isEmpty) return customer;
      final parsed = CustomerModel.fromJson(detail);
      final trn = parsed.trn.trim();
      final address = parsed.address.trim();
      if (trn.isEmpty && address.isEmpty) return customer;

      final updated = customer.copyWith(
        trn: trn.isNotEmpty ? trn : customer.trn,
        address: customer.address.trim().isEmpty && address.isNotEmpty
            ? address
            : customer.address,
      );
      await _db.upsertCustomer(updated);
      return updated;
    } catch (_) {
      return customer;
    }
  }

  @override
  Future<void> printTestPage() async {
    final bytes = await VoucherTicketBuilder.buildTestPage(
      paperSize: paperSize,
      printerName: preferredPrinter?.name,
    );
    await _writeBytes(bytes);
  }
}
