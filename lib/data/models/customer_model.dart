import '../../domain/models/customer.dart';

/// Data transfer object for the [Customer] domain entity.
///
/// Implements robust JSON parsing to support both offline database hydration and
/// remote Zoho CRM Contact API maps, resolving differences in naming conventions (snake_case vs camelCase).
class CustomerModel extends Customer {
  /// Creates a new [CustomerModel] instance matching fields of the parent.
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

  /// Factory constructor to parse local/remote JSON payload into a [CustomerModel].
  ///
  /// Maps server keys (`contact_id`, `contact_name`, `outstanding_receivable_amount`) 
  /// and local database representations fallback keys.
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

  /// Converts this [CustomerModel] instance into a JSON compatible map.
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

  /// Facilitates converting a base domain [Customer] entity into a serializable [CustomerModel].
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

