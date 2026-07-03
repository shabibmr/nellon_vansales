import 'package:equatable/equatable.dart';

/// Represents a Zoho Books Salesperson (sales user) entity.
///
/// The master list mirrors all sales users configured in Zoho Books. The single
/// "active" instance additionally carries [locationId], resolved from the
/// `cm_salesperson_location` Zoho custom module (the native Salesperson object
/// has no location field of its own).
class Salesperson extends Equatable {
  /// Unique salesperson identifier from Zoho (salesperson_id).
  final String id;

  /// Full display name of the salesperson.
  final String name;

  /// Login email address of the salesperson.
  final String email;

  /// Zoho Location ID mapped to this salesperson, if resolved.
  final String? locationId;

  /// Zoho lifecycle status (e.g. "active", "inactive").
  final String status;

  /// Creates a new [Salesperson] record.
  const Salesperson({
    required this.id,
    required this.name,
    required this.email,
    this.locationId,
    this.status = 'active',
  });

  /// Creates a copy of this [Salesperson] with replaced values for specific fields.
  ///
  /// Pass [clearLocationId] as `true` to explicitly null out [locationId]
  /// (e.g. when the Zoho mapping was removed); otherwise a null [locationId]
  /// argument keeps the current value.
  Salesperson copyWith({
    String? id,
    String? name,
    String? email,
    String? locationId,
    bool clearLocationId = false,
    String? status,
  }) {
    return Salesperson(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      locationId: clearLocationId ? null : (locationId ?? this.locationId),
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [id, name, email, locationId, status];
}
