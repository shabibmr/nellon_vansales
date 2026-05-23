import 'package:equatable/equatable.dart';

class Customer extends Equatable {
  final String id;
  final String name;
  final String companyName;
  final String email;
  final String phone;
  final String address;
  final double outstandingBalance;
  final double creditLimit;
  final String routeId;
  final int sequence;
  final bool isPendingSync;

  const Customer({
    required this.id,
    required this.name,
    required this.companyName,
    required this.email,
    required this.phone,
    required this.address,
    required this.outstandingBalance,
    required this.creditLimit,
    required this.routeId,
    required this.sequence,
    this.isPendingSync = false,
  });

  Customer copyWith({
    String? id,
    String? name,
    String? companyName,
    String? email,
    String? phone,
    String? address,
    double? outstandingBalance,
    double? creditLimit,
    String? routeId,
    int? sequence,
    bool? isPendingSync,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      companyName: companyName ?? this.companyName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      creditLimit: creditLimit ?? this.creditLimit,
      routeId: routeId ?? this.routeId,
      sequence: sequence ?? this.sequence,
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
        outstandingBalance,
        creditLimit,
        routeId,
        sequence,
        isPendingSync,
      ];
}
