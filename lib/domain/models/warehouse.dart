import 'package:equatable/equatable.dart';

class Warehouse extends Equatable {
  final String id;
  final String name;
  final String address;
  final bool isPrimary;

  const Warehouse({
    required this.id,
    required this.name,
    required this.address,
    this.isPrimary = false,
  });

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
