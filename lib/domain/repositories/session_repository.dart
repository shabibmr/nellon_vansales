import '../models/route.dart';
import '../models/organization.dart';

/// Abstract contract for route selection and cached organization details.
abstract class SessionRepository {
  /// Retrieves list of routes available for sales agents.
  List<RouteModel> getRoutes();

  /// Gets the currently selected active route ID.
  String? get activeRouteId;

  /// Selects and locks an active route for the delivery day.
  Future<void> setActiveRouteId(String? routeId);

  /// Cached organization details for PDF / currency context.
  Organization? getOrganization();
}
