import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../data/services/device_info_service.dart';
import '../../../../data/services/license_service.dart';
import '../../../../data/services/local_storage_service.dart';
import '../../../../domain/models/license_document.dart';
import '../../../../domain/models/server_config.dart';
import '../../../../domain/models/user.dart';
import 'license_state.dart';

/// Cubit managing the App Licensing flow, checking licenses, registering first-time users,
/// and executing fail-open behaviors.
class LicenseCubit extends Cubit<LicenseState> {
  final LicenseService _licenseService;
  final LocalStorageService _localStorageService;
  final DeviceInfoService _deviceInfoService;
  final Uuid _uuidGenerator;

  LicenseCubit({
    required this._licenseService,
    required this._localStorageService,
    required this._deviceInfoService,
    Uuid? uuidGenerator,
  }) : _uuidGenerator = uuidGenerator ?? const Uuid(),
       super(LicenseInitial());

  /// Triggers standard license check workflow.
  ///
  /// Evaluates local secure storage for cached licensing UUID.
  /// Falls back to first login state if UUID is absent, or fetches license details.
  Future<void> checkLicense(User user) async {
    emit(LicenseChecking());
    try {
      final storedUuid = await _localStorageService.getLicenseUuid();

      if (storedUuid == null || storedUuid.trim().isEmpty) {
        emit(LicensePendingFirstLogin());
        return;
      }

      // Fetch license document from remote Firestore
      final licenseDoc = await _licenseService.fetchLicense(storedUuid);

      if (licenseDoc == null) {
        // Stored locally but removed from server, trigger re-registration
        emit(LicensePendingFirstLogin());
        return;
      }

      // Check validation flags (enabled + expiration checks)
      final now = DateTime.now();
      if (!licenseDoc.enabled) {
        emit(
          const LicenseBlocked(
            reason:
                'Your application license has been disabled by the administrator.',
          ),
        );
        return;
      }

      if (licenseDoc.expiryAt.isBefore(now)) {
        emit(
          const LicenseBlocked(
            reason:
                'Your application license has expired. Please contact support.',
          ),
        );
        return;
      }

      // Update last login timestamp in Firestore background
      _licenseService.updateLastLogin(storedUuid).catchError((_) {});

      // Retrieve Server configuration credentials
      ServerConfig? serverConfig;
      try {
        serverConfig = await _licenseService.fetchServerConfig();
      } catch (e) {
        // Fail-open strategy allows proceeding even if remote credentials fail to load
        // ignore: avoid_print
        print('Licensing fail-open warning: Failed to fetch Server Config: $e');
      }

      emit(LicenseValid(serverConfig: serverConfig));
    } catch (e) {
      // Fail-open strategy on Firestore network/access errors.
      // ignore: avoid_print
      print('Licensing fail-open: Firestore fetch failed. Allowing access: $e');
      emit(const LicenseValid(serverConfig: null));
    }
  }

  /// Registers a new license document in Firestore on the first login of a device.
  Future<void> registerFirstLogin(User user) async {
    emit(LicenseChecking());
    try {
      final newUuid = _uuidGenerator.v4();
      final deviceDetails = await _deviceInfoService.getDeviceDetails();

      final now = DateTime.now();
      final expiry = now.add(
        const Duration(days: 15),
      ); // Default 15 days trial license

      final licenseDoc = LicenseDocument(
        id: newUuid,
        userId: user.id,
        userEmail: user.email,
        userName: user.name,
        deviceId: deviceDetails.id,
        deviceModel: deviceDetails.model,
        deviceOs: deviceDetails.os,
        deviceOsVersion: deviceDetails.osVersion,
        appVersion: deviceDetails.appVersion,
        firstLoginAt: now,
        lastLoginAt: now,
        enabled: true,
        expiryAt: expiry,
      );

      // Save document to Firestore
      await _licenseService.createLicense(licenseDoc);

      // Persist UUID securely on device
      await _localStorageService.saveLicenseUuid(newUuid);

      // Attempt to load server configurations
      ServerConfig? serverConfig;
      try {
        serverConfig = await _licenseService.fetchServerConfig();
      } catch (e) {
        // ignore: avoid_print
        print('Licensing registration warning: Failed to load Zoho Config: $e');
      }

      emit(LicenseValid(serverConfig: serverConfig));
    } catch (e) {
      emit(
        LicenseError(
          'Failed to register application license: ${e.toString().replaceAll('Exception: ', '')}',
        ),
      );
    }
  }

  /// Reset licensing cubit to initial state (useful on user logout).
  void reset() {
    emit(LicenseInitial());
  }
}
