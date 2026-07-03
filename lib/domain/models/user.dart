import 'package:equatable/equatable.dart';

/// Represents the authenticated Sales Agent or User operating the van sales application.
///
/// Holds basic profile details, system roles, current route assignment,
/// and the specific physical warehouse ID mapped to their delivery van.
class User extends Equatable {
  /// Unique identifier of the user (e.g. Firebase UID).
  final String id;

  /// Full display name of the user.
  final String name;

  /// Primary email address used for login.
  final String email;

  /// Authorization role in the system (e.g., "agent", "admin").
  final String role;

  /// ID of the route currently active for this session, if any.
  final String? activeRouteId;

  /// Zoho warehouse ID representing the physical inventory stocked in this user's van.
  final String? assignedVanWarehouseId;

  /// Creates a new [User] profile session entity.
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.activeRouteId,
    this.assignedVanWarehouseId,
  });

  /// Creates a copy of this [User] with replaced values for specific fields.
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
      assignedVanWarehouseId:
          assignedVanWarehouseId ?? this.assignedVanWarehouseId,
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
