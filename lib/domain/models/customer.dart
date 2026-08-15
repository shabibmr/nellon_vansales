import 'package:equatable/equatable.dart';

/// Represents a customer/client business entity in the Van Sales system.
///
/// Customers are assigned to specific routes and have sequence values that determine
/// the order they should be visited. They also carry billing properties like credit limits
/// and outstanding balances.
class Customer extends Equatable {
  /// Unique customer identifier.
  final String id;

  /// Full display name of the customer.
  final String name;

  /// Registered company/business name.
  final String companyName;

  /// Primary email address of the customer.
  final String email;

  /// Primary contact phone number.
  final String phone;

  /// Street / textual billing or delivery address of the customer.
  /// GPS coordinates are stored separately in [latitude] / [longitude].
  final String address;

  /// Tax registration number (e.g. UAE TRN), when known.
  final String trn;

  /// The current unpaid balance of this customer.
  final double outstandingBalance;

  /// The maximum credit limit authorized for this customer.
  final double creditLimit;

  /// The ID of the route this customer belongs to.
  final String routeId;

  /// The sequence order of this customer on the route.
  final int sequence;

  /// Optional GPS latitude captured for this customer (decimal degrees).
  final double? latitude;

  /// Optional GPS longitude captured for this customer (decimal degrees).
  final double? longitude;

  /// Flag indicating if any local updates are waiting to sync to the server.
  final bool isPendingSync;

  /// True when both latitude and longitude are present.
  bool get hasGps => latitude != null && longitude != null;

  /// True when a non-blank phone number is on file.
  bool get hasPhone => phone.trim().isNotEmpty;

  /// True when a non-blank tax registration number is on file.
  bool get hasTrn => trn.trim().isNotEmpty;

  /// Creates a [Customer] record.
  const Customer({
    required this.id,
    required this.name,
    required this.companyName,
    required this.email,
    required this.phone,
    required this.address,
    this.trn = '',
    required this.outstandingBalance,
    required this.creditLimit,
    required this.routeId,
    required this.sequence,
    this.latitude,
    this.longitude,
    this.isPendingSync = false,
  });

  /// Returns a new copy of the customer with updated fields.
  Customer copyWith({
    String? id,
    String? name,
    String? companyName,
    String? email,
    String? phone,
    String? address,
    String? trn,
    double? outstandingBalance,
    double? creditLimit,
    String? routeId,
    int? sequence,
    double? latitude,
    double? longitude,
    bool? isPendingSync,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      companyName: companyName ?? this.companyName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      trn: trn ?? this.trn,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      creditLimit: creditLimit ?? this.creditLimit,
      routeId: routeId ?? this.routeId,
      sequence: sequence ?? this.sequence,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isPendingSync: isPendingSync ?? this.isPendingSync,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        companyName,
        email,
        phone,
        address,
        trn,
        outstandingBalance,
        creditLimit,
        routeId,
        sequence,
        latitude,
        longitude,
        isPendingSync,
      ];
}

/// Which of GPS / phone / TRN are still missing on a [Customer].
class CustomerMissingFields {
  final bool gps;
  final bool phone;
  final bool trn;

  const CustomerMissingFields({
    required this.gps,
    required this.phone,
    required this.trn,
  });

  factory CustomerMissingFields.of(Customer customer) {
    return CustomerMissingFields(
      gps: !customer.hasGps,
      phone: !customer.hasPhone,
      trn: !customer.hasTrn,
    );
  }

  bool get any => gps || phone || trn;

  bool get onlyGps => gps && !phone && !trn;

  /// Dialog title that names only what is still required.
  String get dialogTitle {
    if (onlyGps) return 'Add GPS Location';
    if (phone && !gps && !trn) return 'Add Phone Number';
    if (trn && !gps && !phone) return 'Add TRN Number';
    return 'Complete Customer Details';
  }
}
