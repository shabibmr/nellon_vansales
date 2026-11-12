import 'dart:convert';
import 'dart:io';

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
      expect(again.currencyDecimalPlaces, 2);
    });
  });

  group('Organization decimal places defaults and parsing', () {
    test('defaults to 2 decimals for AED', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '1',
        'name': 'AED Org',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
      });
      expect(org.currencyDecimalPlaces, 2);
      expect(org.formatCurrency(12.3456), 'AED12.35');
    });

    test('defaults to ISO 3 decimals for KWD when precision is omitted', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '2',
        'name': 'KWD Org',
        'currency_code': 'KWD',
        'currency_symbol': 'KD ',
      });
      expect(org.currencyDecimalPlaces, 3);
      expect(org.formatCurrency(12.3456), 'KD 12.346');
    });

    test('defaults to 0 decimals for JPY when precision is omitted', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '5',
        'name': 'JPY Org',
        'currency_code': 'JPY',
        'currency_symbol': r'¥',
      });
      expect(org.currencyDecimalPlaces, 0);
      expect(org.formatCurrency(12.6), r'¥13');
    });

    test('price_precision wins over the ISO table', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '6',
        'name': 'KWD Org',
        'currency_code': 'KWD',
        'currency_symbol': 'KWD ',
        'price_precision': 2,
      });
      expect(org.currencyDecimalPlaces, 2);
    });

    test('parses explicit currency_decimal_places from JSON', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '3',
        'name': 'Custom Org',
        'currency_code': 'USD',
        'currency_symbol': r'$',
        'currency_decimal_places': 4,
      });
      expect(org.currencyDecimalPlaces, 4);
      expect(org.formatCurrency(12.3456), r'$12.3456');
    });

    test('parses the anonymised Kuwait org fixture', () {
      final json = jsonDecode(
        File('test/fixtures/org_kwd.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final org = OrganizationModel.fromJson(json);
      expect(org.currencyCode, 'KWD');
      expect(org.currencyDecimalPlaces, 3);
      expect(org.formatCurrency(3.750), 'KWD3.750');
    });

    test('round-trips total_rounding_step, defaulting to 0', () {
      final fresh = OrganizationModel.fromJson({
        'organization_id': '5',
        'name': 'Org',
        'currency_code': 'AED',
        'currency_symbol': 'AED ',
      });
      expect(fresh.totalRoundingStep, 0);

      final cached = OrganizationModel.fromJson(
        OrganizationModel.fromDomain(fresh.copyWith(totalRoundingStep: 0.5))
            .toJson(),
      );
      expect(cached.totalRoundingStep, 0.5);
    });

    test('parses price_precision from Zoho JSON', () {
      final org = OrganizationModel.fromJson({
        'organization_id': '4',
        'name': 'Zoho Org',
        'currency_code': 'AED',
        'currency_symbol': 'AED ',
        'price_precision': 3,
      });
      expect(org.currencyDecimalPlaces, 3);
      expect(org.formatCurrency(10.5), 'AED 10.500');
    });
  });
}
