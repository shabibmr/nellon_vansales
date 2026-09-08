import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/license_document.dart';
import 'package:van_sales/domain/utils/login_metadata_update.dart';

void main() {
  LicenseDocument stored({String appVersion = '1.1.0+22'}) => LicenseDocument(
        id: 'uuid-1',
        userId: 'user-1',
        userEmail: 'old@sales.com',
        userName: 'Old Name',
        deviceId: 'old-device',
        deviceModel: 'Old Model',
        deviceOs: 'Android',
        deviceOsVersion: '12',
        appVersion: appVersion,
        firstLoginAt: DateTime.utc(2026, 1, 1),
        lastLoginAt: DateTime.utc(2026, 8, 1),
        enabled: true,
        expiryAt: DateTime.utc(2026, 12, 31),
      );

  LoginMetadataUpdate build(
    LicenseDocument current, {
    String appVersion = '1.2.0+30',
    String phone = '+971500000009',
  }) =>
      buildLoginMetadataUpdate(
        current: current,
        appVersion: appVersion,
        deviceId: 'new-device',
        deviceModel: 'Pixel 8',
        deviceOsVersion: '14',
        userName: 'New Name',
        userEmail: 'new@sales.com',
        userPhone: phone,
      );

  test('maps device and profile fields', () {
    final upd = build(stored());
    expect(upd.fields['device_id'], 'new-device');
    expect(upd.fields['device_model'], 'Pixel 8');
    expect(upd.fields['device_os_version'], '14');
    expect(upd.fields['user_name'], 'New Name');
    expect(upd.fields['user_email'], 'new@sales.com');
    expect(upd.fields['user_phone'], '+971500000009');
    expect(upd.fields['app_version'], '1.2.0+30');
  });

  test('records previous_app_version only when the build changed', () {
    final changed = build(stored(), appVersion: '1.2.0+30');
    expect(changed.appVersionChanged, isTrue);
    expect(changed.fields['previous_app_version'], '1.1.0+22');

    final same = build(stored(appVersion: '1.2.0+30'), appVersion: '1.2.0+30');
    expect(same.appVersionChanged, isFalse);
    expect(same.fields.containsKey('previous_app_version'), isFalse);
  });

  test('empty appVersion is not treated as a change', () {
    final upd = build(stored(), appVersion: '');
    expect(upd.appVersionChanged, isFalse);
    expect(upd.fields.containsKey('previous_app_version'), isFalse);
  });

  test('empty phone is tolerated', () {
    final upd = build(stored(), phone: '');
    expect(upd.fields['user_phone'], '');
  });

  test('never emits FieldValue-style keys', () {
    final upd = build(stored());
    expect(upd.fields.containsKey('last_login_at'), isFalse);
    expect(upd.fields.containsKey('updated_at'), isFalse);
    expect(upd.fields.containsKey('login_count'), isFalse);
    expect(upd.fields.containsKey('app_version_updated_at'), isFalse);
  });
}
