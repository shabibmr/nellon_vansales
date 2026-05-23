import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String name;
  final String email;
  final String role; // e.g. "agent", "admin"
  final String? activeRouteId;
  final String? assignedVanWarehouseId; // Zoho warehouse ID specific to this van

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.activeRouteId,
    this.assignedVanWarehouseId,
  });

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    String? activeRouteId,
    String? assignedVanWarehouseId,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      activeRouteId: activeRouteId ?? this.activeRouteId,
      assignedVanWarehouseId: assignedVanWarehouseId ?? this.assignedVanWarehouseId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        role,
        activeRouteId,
        assignedVanWarehouseId,
      ];
}
