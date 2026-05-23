import '../../domain/models/customer.dart';

class CustomerModel extends Customer {
  const CustomerModel({
    required super.id,
    required super.name,
    required super.companyName,
    required super.email,
    required super.phone,
    required super.address,
    required super.outstandingBalance,
    required super.creditLimit,
    required super.routeId,
    required super.sequence,
    super.isPendingSync,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['contact_id'] ?? json['id'] ?? '',
      name: json['contact_name'] ?? json['name'] ?? '',
      companyName: json['company_name'] ?? json['companyName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'] ?? json['billing_address']?['address'] ?? '',
      outstandingBalance: (json['outstanding_receivable_amount'] ?? json['outstanding_balance'] ?? json['outstandingBalance'] ?? 0.0).toDouble(),
      creditLimit: (json['credit_limit'] ?? json['creditLimit'] ?? 0.0).toDouble(),
      routeId: json['route_id'] ?? json['routeId'] ?? '',
      sequence: json['sequence'] ?? 0,
      isPendingSync: json['isPendingSync'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contact_id': id,
      'name': name,
      'contact_name': name,
      'company_name': companyName,
      'email': email,
      'phone': phone,
      'address': address,
      'outstandingBalance': outstandingBalance,
      'creditLimit': creditLimit,
      'route_id': routeId,
      'sequence': sequence,
      'isPendingSync': isPendingSync,
    };
  }

  factory CustomerModel.fromDomain(Customer customer) {
    return CustomerModel(
      id: customer.id,
      name: customer.name,
      companyName: customer.companyName,
      email: customer.email,
      phone: customer.phone,
      address: customer.address,
      outstandingBalance: customer.outstandingBalance,
      creditLimit: customer.creditLimit,
      routeId: customer.routeId,
      sequence: customer.sequence,
      isPendingSync: customer.isPendingSync,
    );
  }
}
