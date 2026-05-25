import 'package:equatable/equatable.dart';

/// Represents a Zoho Books Warehouse inventory location.
///
/// Mapped to specific delivery vans in order to scope stock queries and stock transfers.
class Warehouse extends Equatable {
  /// Unique warehouse identifier from Zoho (warehouse_id).
  final String id;

  /// Display name of the warehouse or delivery van inventory chamber.
  final String name;

  /// Address/description of the physical location.
  final String address;

  /// Flag indicating if this is the primary organization distribution warehouse.
  final bool isPrimary;

  /// Creates a new [Warehouse] record.
  const Warehouse({
    required this.id,
    required this.name,
    required this.address,
    this.isPrimary = false,
  });

  /// Creates a copy of this [Warehouse] with replaced values for specific fields.
  Warehouse copyWith({
    String? id,
    String? name,
    String? address,
    bool? isPrimary,
  }) {
    return Warehouse(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  @override
  List<Object?> get props => [id, name, address, isPrimary];
}

