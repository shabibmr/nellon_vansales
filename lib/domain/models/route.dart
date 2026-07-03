import 'package:equatable/equatable.dart';

/// Represents a delivery route or trip assignment.
///
/// Customers are linked to routes to organize territory/service schedules.
class RouteModel extends Equatable {
  /// Unique route identifier.
  final String id;

  /// The name of the route territory.
  final String name;

  /// Brief description detailing regions covered by the route.
  final String description;

  /// Creates a new [RouteModel].
  const RouteModel({
    required this.id,
    required this.name,
    required this.description,
  });

  @override
  List<Object?> get props => [id, name, description];
}
