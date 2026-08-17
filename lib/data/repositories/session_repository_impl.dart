import '../../domain/models/route.dart';
import '../../domain/models/organization.dart';
import '../../domain/repositories/session_repository.dart';
import '../services/hive_database_service.dart';

/// Concrete implementation of [SessionRepository] backed by a local Hive database cache.
class SessionRepositoryImpl implements SessionRepository {
  final HiveDatabaseService _dbService;

  SessionRepositoryImpl({required this._dbService});

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
