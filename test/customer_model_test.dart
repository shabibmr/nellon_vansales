import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/customer_model.dart';

void main() {
  group('CustomerModel TRN', () {
    test('reads tax_reg_no from contact detail', () {
      final customer = CustomerModel.fromJson({
        'contact_id': '3331482000046465239',
        'contact_name': 'AL AMANAH SPICES TR FLOUR MILL',
        'company_name': 'AL AMANAH SPICES TR FLOUR MILL',
        'phone': '065260032',
        'tax_treatment': 'vat_registered',
        'tax_reg_no': '100533986400003',
        'vat_reg_no': '100533986400003',
        'billing_address': {
          'address': 'NEAR FIRE STATION ROAD MUWAILAH',
          'country': 'U.A.E',
        },
      });
      expect(customer.trn, '100533986400003');
      expect(customer.address, 'NEAR FIRE STATION ROAD MUWAILAH');
    });

    test('falls back to vat_reg_no when tax_reg_no missing', () {
      final customer = CustomerModel.fromJson({
        'contact_id': 'c1',
        'contact_name': 'A',
        'vat_reg_no': '100533986400003',
      });
      expect(customer.trn, '100533986400003');
    });

    test('AQSA-shaped detail keeps empty TRN', () {
      final customer = CustomerModel.fromJson({
        'contact_id': '3331482000122714550',
        'contact_name': 'AQSA AL MADEENA HYPERMARKET',
        'tax_treatment': 'vat_not_registered',
        'tax_reg_no': '',
        'vat_reg_no': '',
        'billing_address': {'address': ''},
      });
      expect(customer.trn, isEmpty);
    });

    test('falls back to mobile when phone is empty', () {
      final customer = CustomerModel.fromJson({
        'contact_id': 'c1',
        'contact_name': 'A',
        'phone': '',
        'mobile': '0501234567',
      });
      expect(customer.phone, '0501234567');
    });

    test('list-shaped row without tax_reg_no has empty TRN', () {
      final customer = CustomerModel.fromJson({
        'contact_id': 'cust_01',
        'contact_name': 'Supermarket Alfa',
        'company_name': 'Alfa Corp',
        'phone': '1234567890',
        'outstanding_receivable_amount': 450.0,
      });
      expect(customer.trn, isEmpty);
    });

    test('toJson keeps trn and tax_reg_no', () {
      const customer = CustomerModel(
        id: 'c1',
        name: 'A',
        companyName: 'A',
        email: '',
        phone: '',
        address: '',
        trn: '100533986400003',
        outstandingBalance: 0,
        creditLimit: 0,
        routeId: 'r1',
        sequence: 1,
      );
      final json = customer.toJson();
      expect(json['trn'], '100533986400003');
      expect(json['tax_reg_no'], '100533986400003');
      expect(CustomerModel.fromJson(json).trn, '100533986400003');
    });
  });
}
