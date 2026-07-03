import 'package:equatable/equatable.dart';

/// Represents an application license record stored in Firestore.
class LicenseDocument extends Equatable {
  final String id;
  final String userId;
  final String userEmail;
  final String userName;
  final String deviceId;
  final String deviceModel;
  final String deviceOs;
  final String deviceOsVersion;
  final String appVersion;
  final DateTime firstLoginAt;
  final DateTime lastLoginAt;
  final bool enabled;
  final DateTime expiryAt;

  const LicenseDocument({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.deviceId,
    required this.deviceModel,
    required this.deviceOs,
    required this.deviceOsVersion,
    required this.appVersion,
    required this.firstLoginAt,
    required this.lastLoginAt,
    required this.enabled,
    required this.expiryAt,
  });

  /// Factory constructor to create a [LicenseDocument] from a Firestore map.
  factory LicenseDocument.fromMap(Map<String, dynamic> map) {
    DateTime parseDateTime(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      // Handle Firestore Timestamp
      try {
        return value.toDate();
      } catch (_) {
        // Fallback for string or milliseconds
        if (value is String) {
          return DateTime.parse(value);
        } else if (value is int) {
          return DateTime.fromMillisecondsSinceEpoch(value);
        }
      }
      return DateTime.now();
    }

    return LicenseDocument(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      userEmail: map['user_email'] as String? ?? '',
      userName: map['user_name'] as String? ?? '',
      deviceId: map['device_id'] as String? ?? '',
      deviceModel: map['device_model'] as String? ?? '',
      deviceOs: map['device_os'] as String? ?? 'Android',
      deviceOsVersion: map['device_os_version'] as String? ?? '',
      appVersion: map['app_version'] as String? ?? '',
      firstLoginAt: parseDateTime(map['first_login_at']),
      lastLoginAt: parseDateTime(map['last_login_at']),
      enabled: map['enabled'] as bool? ?? true,
      expiryAt: parseDateTime(map['expiry_at']),
    );
  }

  /// Converts the [LicenseDocument] to a map structure for Firestore storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'user_email': userEmail,
      'user_name': userName,
      'device_id': deviceId,
      'device_model': deviceModel,
      'device_os': deviceOs,
      'device_os_version': deviceOsVersion,
      'app_version': appVersion,
      'first_login_at': firstLoginAt,
      'last_login_at': lastLoginAt,
      'enabled': enabled,
      'expiry_at': expiryAt,
    };
  }

  /// Creates a copy of this [LicenseDocument] with updated fields.
  LicenseDocument copyWith({
    String? id,
    String? userId,
    String? userEmail,
    String? userName,
    String? deviceId,
    String? deviceModel,
    String? deviceOs,
    String? deviceOsVersion,
    String? appVersion,
    DateTime? firstLoginAt,
    DateTime? lastLoginAt,
    bool? enabled,
    DateTime? expiryAt,
  }) {
    return LicenseDocument(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      userName: userName ?? this.userName,
      deviceId: deviceId ?? this.deviceId,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceOs: deviceOs ?? this.deviceOs,
      deviceOsVersion: deviceOsVersion ?? this.deviceOsVersion,
      appVersion: appVersion ?? this.appVersion,
      firstLoginAt: firstLoginAt ?? this.firstLoginAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      enabled: enabled ?? this.enabled,
      expiryAt: expiryAt ?? this.expiryAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    userEmail,
    userName,
    deviceId,
    deviceModel,
    deviceOs,
    deviceOsVersion,
    appVersion,
    firstLoginAt,
    lastLoginAt,
    enabled,
    expiryAt,
  ];
}
