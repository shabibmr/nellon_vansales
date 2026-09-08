import '../models/license_document.dart';

/// Result of [buildLoginMetadataUpdate]: the primitive field values to patch onto
/// an `app_licenses` document plus whether the running build changed since the
/// last login (so the caller can stamp `app_version_updated_at`).
class LoginMetadataUpdate {
  const LoginMetadataUpdate({
    required this.fields,
    required this.appVersionChanged,
  });

  /// Firestore field/value pairs, primitives only — never `FieldValue` sentinels.
  final Map<String, dynamic> fields;

  /// True when [appVersion] differs from the stored document's `appVersion`.
  final bool appVersionChanged;
}

/// Builds the descriptive fields refreshed on every successful login.
///
/// Pure: takes the previously stored [current] document plus the live device and
/// session values, returns primitives only. `previous_app_version` is included
/// only when the build actually changed, so unchanged logins don't churn it.
LoginMetadataUpdate buildLoginMetadataUpdate({
  required LicenseDocument current,
  required String appVersion,
  required String deviceId,
  required String deviceModel,
  required String deviceOsVersion,
  required String userName,
  required String userEmail,
  required String userPhone,
}) {
  final appVersionChanged =
      appVersion.isNotEmpty && appVersion != current.appVersion;

  final fields = <String, dynamic>{
    'app_version': appVersion,
    'device_id': deviceId,
    'device_model': deviceModel,
    'device_os_version': deviceOsVersion,
    'user_name': userName,
    'user_email': userEmail,
    'user_phone': userPhone,
  };

  if (appVersionChanged) {
    fields['previous_app_version'] = current.appVersion;
  }

  return LoginMetadataUpdate(
    fields: fields,
    appVersionChanged: appVersionChanged,
  );
}
