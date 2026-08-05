import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/organization.dart';
import '../../../../domain/models/paired_printer.dart';
import '../../../../domain/models/thermal_paper_size.dart';
import '../../../../domain/repositories/thermal_printer_repository.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../../core/utils/error_mapper.dart';
import 'thermal_printer_state.dart';

/// App-level cubit for Bluetooth ESC/POS printer settings and printing.
class ThermalPrinterCubit extends Cubit<ThermalPrinterState> {
  ThermalPrinterCubit({required ThermalPrinterRepository repository})
      : _repo = repository,
        super(
          ThermalPrinterState(
            paperSize: repository.paperSize,
            preferredPrinter: repository.preferredPrinter,
          ),
        );

  final ThermalPrinterRepository _repo;

  static const _bluetoothPermissions = [
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
  ];

  /// Refreshes Bluetooth status, permission, bonded list, and connection.
  Future<void> refresh() async {
    emit(
      state.copyWith(
        isLoading: true,
        clearError: true,
        clearStatus: true,
        clearNeedsAppSettings: true,
      ),
    );
    try {
      final permission = await _repo
          .isBluetoothPermissionGranted()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);

      bool btOn = false;
      bool connected = false;
      List<PairedPrinter> bonded = const [];

      if (permission) {
        btOn = await _repo
            .isBluetoothOn()
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
        if (btOn) {
          connected = await _repo
              .isConnected
              .timeout(const Duration(seconds: 3), onTimeout: () => false);
          bonded = await _repo
              .getBondedDevices()
              .timeout(const Duration(seconds: 3), onTimeout: () => const []);
        }
      }

      emit(
        state.copyWith(
          isLoading: false,
          permissionGranted: permission,
          bluetoothOn: btOn,
          isConnected: connected,
          bondedDevices: bonded,
          paperSize: _repo.paperSize,
          preferredPrinter: _repo.preferredPrinter,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: userFacingMessage(e),
        ),
      );
    }
  }

  /// Requests Bluetooth runtime permission (Android 12+).
  ///
  /// When the user denies (or permanently denies), sets [ThermalPrinterState.needsAppSettings]
  /// so the UI can show an Open Settings dialog.
  Future<bool> requestPermission() async {
    emit(
      state.copyWith(
        isLoading: true,
        clearError: true,
        clearNeedsAppSettings: true,
      ),
    );
    try {
      final granted = await _requestBluetoothPermission()
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      emit(
        state.copyWith(
          isLoading: false,
          permissionGranted: granted,
          needsAppSettings: !granted,
          errorMessage: granted
              ? null
              : 'Bluetooth permission is required to use the thermal printer.',
          clearError: granted,
        ),
      );
      if (granted) {
        await refresh();
      }
      return granted;
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          needsAppSettings: true,
          errorMessage: userFacingMessage(e),
        ),
      );
      return false;
    }
  }

  Future<bool> _requestBluetoothPermission() async {
    final statuses = await _bluetoothPermissions.request();
    final anyGranted = statuses.values.any((s) => s.isGranted);
    if (anyGranted) return true;
    // Fallback: plugin-level check (handles older Android mappings).
    return _repo.isBluetoothPermissionGranted();
  }

  /// Ensures Bluetooth permission before connect/print. Sets [needsAppSettings] on failure.
  Future<bool> _ensurePermissionOrPrompt() async {
    var permitted = await _repo.isBluetoothPermissionGranted();
    if (permitted) {
      if (!state.permissionGranted) {
        emit(state.copyWith(permissionGranted: true, clearNeedsAppSettings: true));
      }
      return true;
    }
    permitted = await _requestBluetoothPermission();
    if (permitted) {
      emit(state.copyWith(permissionGranted: true, clearNeedsAppSettings: true));
      return true;
    }
    emit(
      state.copyWith(
        permissionGranted: false,
        needsAppSettings: true,
        errorMessage:
            'Bluetooth permission is required to use the thermal printer.',
      ),
    );
    return false;
  }

  Future<void> setPaperSize(ThermalPaperSize size) async {
    await _repo.setPaperSize(size);
    emit(
      state.copyWith(
        paperSize: size,
        statusMessage: 'Paper size set to ${size.label}',
        clearError: true,
      ),
    );
  }

  Future<void> selectPrinter(PairedPrinter printer) async {
    emit(state.copyWith(isLoading: true, clearError: true, clearStatus: true));
    try {
      if (!await _ensurePermissionOrPrompt()) {
        emit(state.copyWith(isLoading: false));
        return;
      }
      final ok = await _repo.connect(printer);
      if (!ok) {
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage:
                'Could not connect to ${printer.name}. Ensure it is paired and powered on.',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          isLoading: false,
          isConnected: true,
          preferredPrinter: printer,
          statusMessage: 'Connected to ${printer.name}',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: userFacingMessage(e),
        ),
      );
    }
  }

  Future<void> forgetPrinter() async {
    await _repo.disconnect();
    await _repo.setPreferredPrinter(null);
    emit(
      state.copyWith(
        isConnected: false,
        clearPreferredPrinter: true,
        statusMessage: 'Printer cleared',
        clearError: true,
      ),
    );
  }

  Future<void> disconnect() async {
    await _repo.disconnect();
    emit(
      state.copyWith(
        isConnected: false,
        statusMessage: 'Disconnected',
        clearError: true,
      ),
    );
  }

  Future<void> printTestPage() async {
    emit(
      state.copyWith(
        isPrinting: true,
        clearError: true,
        clearStatus: true,
        clearNeedsAppSettings: true,
      ),
    );
    try {
      if (!await _ensurePermissionOrPrompt()) {
        emit(state.copyWith(isPrinting: false));
        return;
      }
      await _repo.printTestPage();
      emit(
        state.copyWith(
          isPrinting: false,
          isConnected: true,
          statusMessage: 'Test page sent to printer',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isPrinting: false,
          errorMessage: userFacingMessage(e),
          needsAppSettings: _isPermissionError(e),
        ),
      );
    }
  }

  Future<void> printVoucher({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    String? salespersonName,
  }) async {
    emit(
      state.copyWith(
        isPrinting: true,
        clearError: true,
        clearStatus: true,
        clearNeedsAppSettings: true,
      ),
    );
    try {
      if (!await _ensurePermissionOrPrompt()) {
        emit(state.copyWith(isPrinting: false));
        return;
      }
      await _repo.printVoucher(
        type: type,
        voucher: voucher,
        org: org,
        customer: customer,
        salespersonName: salespersonName,
      );
      emit(
        state.copyWith(
          isPrinting: false,
          isConnected: true,
          statusMessage: 'Sent to thermal printer',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isPrinting: false,
          errorMessage: userFacingMessage(e),
          needsAppSettings: _isPermissionError(e),
        ),
      );
    }
  }

  bool _isPermissionError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('permission') || msg.contains('bluetooth permission');
  }

  void clearMessages() {
    emit(
      state.copyWith(
        clearError: true,
        clearStatus: true,
        clearNeedsAppSettings: true,
      ),
    );
  }

  void clearNeedsAppSettings() {
    emit(state.copyWith(clearNeedsAppSettings: true));
  }
}
