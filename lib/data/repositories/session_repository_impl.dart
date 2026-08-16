import '../../domain/models/route.dart';
import '../../domain/models/organization.dart';
import '../../domain/repositories/session_repository.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [SessionRepository] backed by a local Hive database cache.
class SessionRepositoryImpl implements SessionRepository {
  final HiveDatabaseService _dbService;
  // ignore: unused_field
  final ZohoApiClient _apiClient;

  SessionRepositoryImpl({required this._dbService, required this._apiClient});

  @override
  List<RouteModel> getRoutes() => _dbService.getRoutes();

  @override
  String? get activeRouteId => _dbService.activeRouteId;

  @override
  Future<void> setActiveRouteId(String? routeId) =>
      _dbService.setActiveRouteId(routeId);

  @override
  Organization? getOrganization() => _dbService.getOrganization();
}
