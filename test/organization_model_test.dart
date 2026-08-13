import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/organization_model.dart';

void main() {
  group('OrganizationModel address', () {
    test('joins Zoho nested address without Map.toString dump', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '783019958',
        'name': 'KOYSON GENERAL TRADING LLC',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
        'fiscal_year_start_month': 'january',
        'time_zone': 'Asia/Dubai',
        'address': {
          'street_address1': 'JEBEL ALI IND-1, DUBAI, UAE',
          'street_address2': '',
          'city': 'DUBAI',
          'state': 'Dubai',
          'state_code': 'DU',
          'country': 'U.A.E',
          'zip': '',
          'latitude': '',
          'longitude': '',
          'attention': 'koysontrading',
          'street_address1_sec_lang': '',
        },
      });

      expect(org.address, 'JEBEL ALI IND-1, DUBAI, UAE');
      expect(org.address.contains('{'), isFalse);
      expect(org.address.contains('street_address1'), isFalse);
    });

    test('keeps a plain string address', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '1',
        'name': 'A',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
        'address': '12 Warehouse Rd, Dubai',
      });
      expect(org.address, '12 Warehouse Rd, Dubai');
    });
  });

  group('OrganizationModel TRN', () {
    test('reads tax_settings.tax_reg_no from live UAE payload', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '783019958',
        'name': 'KOYSON GENERAL TRADING LLC',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
        'tax_id_value': '',
        'tax_settings': {
          'is_tax_registered': true,
          'tax_reg_no': '100577492000003',
          'tax_reg_no_label': 'TRN',
        },
      });
      expect(org.trn, '100577492000003');
    });

    test('falls back to custom_fields TRN when tax_settings missing', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '1',
        'name': 'A',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
        'custom_fields': [
          {'index': 1, 'label': 'TRN: ', 'value': '100577492000003'},
        ],
      });
      expect(org.trn, '100577492000003');
    });

    test('does not treat empty tax_id_value as TRN', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '1',
        'name': 'A',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
        'tax_id_value': '',
        'tax_id': '3331482000000075111',
      });
      expect(org.trn, isEmpty);
    });

    test('Hive-shaped JSON with string address and top-level trn round-trips', () {
      final original = OrganizationModel.fromJson({
        'organization_id': '1',
        'name': 'A',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
        'fiscal_year_start_month': 'january',
        'time_zone': 'Asia/Dubai',
        'address': 'JEBEL ALI IND-1, DUBAI, UAE',
        'phone': '00971545829444',
        'trn': '100577492000003',
      });
      final again = OrganizationModel.fromJson(original.toJson());
      expect(again.address, original.address);
      expect(again.trn, original.trn);
      expect(again.phone, original.phone);
    });
  });
}
