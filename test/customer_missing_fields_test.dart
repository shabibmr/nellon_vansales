import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/customer.dart';

Customer _customer({
  String phone = '',
  String trn = '',
  double? latitude,
  double? longitude,
}) {
  return Customer(
    id: 'c1',
    name: 'Shop A',
    companyName: 'Co A',
    email: '',
    phone: phone,
    address: '',
    trn: trn,
    outstandingBalance: 0,
    creditLimit: 0,
    routeId: 'r1',
    sequence: 1,
    latitude: latitude,
    longitude: longitude,
  );
}

void main() {
  group('CustomerMissingFields', () {
    test('reports nothing missing when GPS, phone and TRN are present', () {
      final missing = CustomerMissingFields.of(
        _customer(
          phone: '+971501234567',
          trn: '100533986400003',
          latitude: 25.1,
          longitude: 55.2,
        ),
      );
      expect(missing.any, isFalse);
      expect(missing.gps, isFalse);
      expect(missing.phone, isFalse);
      expect(missing.trn, isFalse);
    });

    test('treats blank phone and TRN as missing', () {
      final missing = CustomerMissingFields.of(
        _customer(phone: '   ', trn: '  '),
      );
      expect(missing.phone, isTrue);
      expect(missing.trn, isTrue);
      expect(missing.gps, isTrue);
    });

    test('treats partial GPS as missing', () {
      expect(
        CustomerMissingFields.of(_customer(latitude: 25.1)).gps,
        isTrue,
      );
      expect(
        CustomerMissingFields.of(_customer(longitude: 55.2)).gps,
        isTrue,
      );
    });

    test('dialog title names only the missing field', () {
      expect(
        CustomerMissingFields.of(
          _customer(phone: '0501234567', trn: '100533986400003'),
        ).dialogTitle,
        'Add GPS Location',
      );
      expect(
        CustomerMissingFields.of(
          _customer(
            trn: '100533986400003',
            latitude: 1,
            longitude: 2,
          ),
        ).dialogTitle,
        'Add Phone Number',
      );
      expect(
        CustomerMissingFields.of(
          _customer(
            phone: '0501234567',
            latitude: 1,
            longitude: 2,
          ),
        ).dialogTitle,
        'Add TRN Number',
      );
      expect(
        CustomerMissingFields.of(_customer()).dialogTitle,
        'Complete Customer Details',
      );
    });
  });
}
