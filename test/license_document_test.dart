import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/license_document.dart';

void main() {
  LicenseDocument sample() => LicenseDocument(
        id: 'uuid-1',
        userId: 'user-1',
        userEmail: 'agent@sales.com',
        userName: 'Agent One',
        deviceId: 'device-1',
        deviceModel: 'Pixel 7',
        deviceOs: 'Android',
        deviceOsVersion: '14',
        appVersion: '1.2.0+30',
        firstLoginAt: DateTime.utc(2026, 1, 1),
        lastLoginAt: DateTime.utc(2026, 9, 1),
        enabled: true,
        expiryAt: DateTime.utc(2026, 12, 31),
        phone: '+971500000001',
        loginCount: 5,
        previousAppVersion: '1.1.0+22',
      );

  test('toMap / fromMap round-trips the new fields', () {
    final restored = LicenseDocument.fromMap(sample().toMap());
    expect(restored, sample());
    expect(restored.phone, '+971500000001');
    expect(restored.loginCount, 5);
    expect(restored.previousAppVersion, '1.1.0+22');
  });

  test('fromMap defaults new fields for legacy documents', () {
    final legacy = LicenseDocument.fromMap({
      'id': 'uuid-1',
      'user_id': 'user-1',
      'user_email': 'agent@sales.com',
      'user_name': 'Agent One',
      'device_id': 'device-1',
      'device_model': 'Pixel 7',
      'device_os': 'Android',
      'device_os_version': '14',
      'app_version': '1.2.0+30',
      'first_login_at': DateTime.utc(2026, 1, 1),
      'last_login_at': DateTime.utc(2026, 9, 1),
      'enabled': true,
      'expiry_at': DateTime.utc(2026, 12, 31),
    });

    expect(legacy.phone, '');
    expect(legacy.loginCount, 0);
    expect(legacy.previousAppVersion, '');
  });

  test('fromMap tolerates a numeric (double) login_count', () {
    final doc = LicenseDocument.fromMap(sample().toMap()..['login_count'] = 7.0);
    expect(doc.loginCount, 7);
  });
}
