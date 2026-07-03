import '../../domain/models/salesperson.dart';
import '../../domain/repositories/salesperson_repository.dart';
import '../models/salesperson_model.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [SalespersonRepository].
///
/// Matches the Firebase-authenticated user's email against the synced Zoho
/// Salespersons list, then resolves the mapped Zoho Location via the
/// `cm_salesperson_location` custom module. Best-effort and offline-tolerant:
/// failures fall back to whatever is already cached rather than blocking login.
class SalespersonRepositoryImpl implements SalespersonRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  /// Creates a new [SalespersonRepositoryImpl] wrapping Hive cache + Zoho API access.
  SalespersonRepositoryImpl({
    required this._dbService,
    required this._apiClient,
  });

  @override
  List<Salesperson> getCachedSalespersons() => _dbService.getSalespersons();

  @override
  Salesperson? get currentSalesperson => _dbService.getCurrentSalesperson();

  @override
  Future<Salesperson?> resolveActiveSalesperson(String email) async {
    var salespersons = _dbService.getSalespersons();
    if (salespersons.isEmpty) {
      try {
        final raw = await _apiClient.fetchSalespersons();
        salespersons = raw.map((s) => SalespersonModel.fromJson(s)).toList();
        await _dbService.saveSalespersons(salespersons);
      } catch (_) {
        // Offline-first: proceed with whatever (possibly empty) cache is available.
      }
    }

    final normalizedEmail = email.toLowerCase();
    Salesperson? matched;
    for (final sp in salespersons) {
      if (sp.email.toLowerCase() == normalizedEmail) {
        matched = sp;
        break;
      }
    }
    if (matched == null) return null;

    String? locationId;
    var mappingsFetched = false;
    try {
      final mappings = await _apiClient.fetchSalespersonLocationMappings();
      mappingsFetched = true;
      for (final m in mappings) {
        // The custom module stores the email in its primary field `record_name`
        // (fallback to `cf_email` in case the module schema is changed later).
        final mappingEmail = (m['record_name'] ?? m['cf_email'] ?? '')
            .toString()
            .toLowerCase();
        if (mappingEmail == normalizedEmail) {
          locationId = m['cf_location_id']?.toString();
          break;
        }
      }
    } catch (_) {
      // Best-effort: location resolution failing shouldn't block login.
    }

    final Salesperson resolved;
    if (mappingsFetched) {
      // Authoritative answer from Zoho: apply it, including an explicit
      // un-mapping when no record matches this salesperson anymore.
      resolved = matched.copyWith(
        locationId: locationId,
        clearLocationId: locationId == null,
      );
      await _dbService.setAssignedWarehouseId(locationId);
    } else {
      // Offline: keep the previously resolved location rather than wiping it.
      final cached = _dbService.getCurrentSalesperson();
      resolved = matched.copyWith(
        locationId: cached?.locationId ?? _dbService.assignedWarehouseId,
      );
    }
    await _dbService.saveCurrentSalesperson(resolved);
    return resolved;
  }
}
