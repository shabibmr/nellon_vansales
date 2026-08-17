import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../data/services/app_logger.dart';
import '../../../../data/services/device_info_service.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../data/services/license_service.dart';
import '../../../../data/services/local_storage_service.dart';
import '../../../../domain/models/license_document.dart';
import '../../../../domain/models/server_config.dart';
import '../../../../domain/models/user.dart';
import '../../../core/utils/error_mapper.dart';
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
    debugPrint('[LicenseCubit] 🔍 Checking license for user: ${user.id} (${user.phone})');
    try {
      final storedUuid = await _localStorageService.getLicenseUuid();

      if (storedUuid == null || storedUuid.trim().isEmpty) {
        debugPrint('[LicenseCubit] 🆕 No cached license UUID found -> First Login registration needed.');
        emit(LicensePendingFirstLogin());
        return;
      }

      debugPrint('[LicenseCubit] 📄 Cached license UUID found: $storedUuid. Fetching from Firestore...');
      // Fetch license document from remote Firestore
      final licenseDoc = await _licenseService.fetchLicense(storedUuid);

      if (licenseDoc == null) {
        debugPrint('[LicenseCubit] ⚠️ License not found in Firestore -> re-registering.');
        // Stored locally but removed from server, trigger re-registration
        emit(LicensePendingFirstLogin());
        return;
      }

      // Check validation flags (enabled + expiration checks)
      final now = DateTime.now();
      if (!licenseDoc.enabled) {
        debugPrint('[LicenseCubit] 🚫 License is DISABLED by administrator.');
        emit(
          const LicenseBlocked(
            reason:
                'Your application license has been disabled by the administrator.',
          ),
        );
        return;
      }

      if (licenseDoc.expiryAt.isBefore(now)) {
        debugPrint('[LicenseCubit] ⌛ License has EXPIRED at: ${licenseDoc.expiryAt}');
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
        debugPrint(
          '[LicenseCubit] 📥 ServerConfig loaded during checkLicense: '
          'isValid=${serverConfig.isValid}, clientId="${serverConfig.clientId}"',
        );
      } catch (e) {
        if (isFirestorePermissionDenied(e)) {
          debugPrint('[LicenseCubit] ❌ Permission-denied reading server_config/zoho: $e');
          AppLogger.error(
            'Licensing',
            'Firestore permission-denied reading server_config/zoho: $e',
          );
          emit(
            const LicenseError(
              'Cannot read Zoho server configuration (permission denied). '
              'Contact admin.',
            ),
          );
          return;
        }
        // Fail-open strategy allows proceeding even if remote credentials fail to load
        debugPrint('[LicenseCubit] ⚠️ Fail-open: Failed to fetch Server Config: $e');
        AppLogger.warning(
          'Licensing',
          'Fail-open warning: Failed to fetch Server Config: $e',
        );
      }

      emit(LicenseValid(serverConfig: serverConfig));
    } catch (e) {
      if (isFirestorePermissionDenied(e)) {
        debugPrint('[LicenseCubit] ❌ Firestore permission-denied during checkLicense: $e');
        AppLogger.error(
          'Licensing',
          'Firestore permission-denied during license check: $e',
        );
        emit(
          const LicenseError(
            'Cannot read license data from the server (permission denied). '
            'Contact admin — the app will not call Zoho until this is fixed.',
          ),
        );
        return;
      }
      // Fail-open strategy on Firestore network/access errors.
      debugPrint('[LicenseCubit] ⚠️ Fail-open: Firestore fetch failed. Allowing access: $e');
      AppLogger.warning(
        'Licensing',
        'Fail-open: Firestore fetch failed. Allowing access: $e',
      );
      emit(const LicenseValid(serverConfig: null));
    }
  }

  /// Registers a new license document in Firestore on the first login of a device.
  Future<void> registerFirstLogin(User user) async {
    emit(LicenseChecking());
    debugPrint('[LicenseCubit] 🚀 Registering first-time login for user: ${user.id} (${user.phone})');
    final newUuid = _uuidGenerator.v4();
    try {
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

      // Best-effort remote write: fail-open if Firestore write fails
      try {
        await _licenseService.createLicense(licenseDoc);
        debugPrint('[LicenseCubit] ☁️ Created initial license document in Firestore.');
      } catch (e) {
        debugPrint('[LicenseCubit] ⚠️ Fail-open: Failed to write initial license to Firestore: $e');
        AppLogger.warning(
          'Licensing',
          'Fail-open: Failed to create license document in Firestore: $e',
        );
      }

      // Persist UUID securely on device
      try {
        await _localStorageService.saveLicenseUuid(newUuid);
        debugPrint('[LicenseCubit] 💾 Saved license UUID locally: $newUuid');
      } catch (e) {
        debugPrint('[LicenseCubit] ⚠️ Failed to persist license UUID locally: $e');
        AppLogger.warning(
          'Licensing',
          'Failed to persist license UUID locally: $e',
        );
      }

      // Attempt to load server configurations
      ServerConfig? serverConfig;
      try {
        serverConfig = await _licenseService.fetchServerConfig();
        debugPrint(
          '[LicenseCubit] 📥 ServerConfig loaded in registerFirstLogin: '
          'isValid=${serverConfig.isValid}, clientId="${serverConfig.clientId}"',
        );
      } catch (e) {
        if (isFirestorePermissionDenied(e)) {
          debugPrint(
            '[LicenseCubit] ❌ Permission-denied reading server_config/zoho '
            'during first login: $e',
          );
          AppLogger.error(
            'Licensing',
            'Firestore permission-denied reading server_config/zoho: $e',
          );
          emit(
            const LicenseError(
              'Cannot read Zoho server configuration (permission denied). '
              'Contact admin.',
            ),
          );
          return;
        }
        debugPrint('[LicenseCubit] ⚠️ Registration warning: Failed to load Zoho Config: $e');
        AppLogger.warning(
          'Licensing',
          'Registration warning: Failed to load Zoho Config: $e',
        );
      }

      emit(LicenseValid(serverConfig: serverConfig));
    } catch (e) {
      if (isFirestorePermissionDenied(e)) {
        debugPrint('[LicenseCubit] ❌ Permission-denied on registerFirstLogin: $e');
        AppLogger.error(
          'Licensing',
          'Firestore permission-denied on first login: $e',
        );
        emit(
          const LicenseError(
            'Cannot register this device (Firestore permission denied). '
            'Contact admin.',
          ),
        );
        return;
      }
      debugPrint('[LicenseCubit] ⚠️ Fail-open on registerFirstLogin unhandled error: $e');
      AppLogger.warning(
        'Licensing',
        'Fail-open on registerFirstLogin error: $e',
      );
      emit(const LicenseValid(serverConfig: null));
    }
  }

  /// Reset licensing cubit to initial state (useful on user logout).
  void reset() {
    emit(LicenseInitial());
  }
}
