import '../../domain/models/salesperson.dart';
import '../../domain/models/session_bind_result.dart';
import '../../domain/models/warehouse.dart';
import '../../domain/repositories/salesperson_repository.dart';
import '../../domain/utils/phone_normalizer.dart';
import '../models/salesperson_model.dart';
import '../models/warehouse_model.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [SalespersonRepository].
///
/// Authorizes login after Firebase Phone OTP: the verified phone must match
/// an active, `cf_active` `cm_salesperson_profile` record whose looked-up
/// salesperson is confirmed active in `/salespersons`. A missing van
/// (`cf_van_location`) does not block login — it falls back to the primary
/// location and the UI allows Sales Orders, Receipts, Expenses, and Cash
/// Closing (orders-only mode; invoices/returns/stock moves stay blocked).
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
  bool get isOrdersOnlyMode => _dbService.ordersOnlyMode;

  @override
  Future<void> clearCurrentSalesperson() =>
      _dbService.clearCurrentSalesperson();

  /// Loads salespersons from Zoho and persists them.
  Future<List<Salesperson>> _fetchAndCacheSalespersons() async {
    final raw = await _apiClient.fetchSalespersons();
    final salespersons = raw.map((s) => SalespersonModel.fromJson(s)).toList();
    await _dbService.saveSalespersons(salespersons);
    return salespersons;
  }

  /// `cf_active` may arrive as a real boolean or a stringified one.
  bool _isActiveFlag(dynamic value) {
    if (value is bool) return value;
    return value?.toString().trim().toLowerCase() == 'true';
  }

  /// Non-empty string field, or null (Zoho omits empty lookups entirely, but
  /// tolerate an explicit empty string too).
  String? _nonEmpty(dynamic value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  @override
  Future<SessionBindResult> verifyAndBindSession(String phone) async {
    final normalizedPhone = normalizePhone(phone.trim());
    if (normalizedPhone.isEmpty) {
      return SessionBindResult.failed(SessionBindFailure.notRegistered);
    }

    List<Map<String, dynamic>> profiles;
    List<Warehouse> warehouses;
    Warehouse? primary;
    try {
      profiles = await _apiClient.fetchSalespersonProfiles();
      await _fetchAndCacheSalespersons();
      final locationRaw = await _apiClient.fetchWarehouses();
      warehouses = locationRaw.map((w) => WarehouseModel.fromJson(w)).toList();
      await _dbService.saveWarehouses(warehouses);
      for (final w in warehouses) {
        if (w.isPrimary) {
          primary = w;
          break;
        }
      }
      primary ??= warehouses.isNotEmpty ? warehouses.first : null;
      await _dbService.setPrimaryWarehouseId(primary?.id);
    } catch (_) {
      return SessionBindResult.failed(SessionBindFailure.network);
    }

    Map<String, dynamic>? matched;
    for (final r in profiles) {
      if (normalizePhone((r['record_name'] ?? '').toString()) ==
          normalizedPhone) {
        matched = r;
        break;
      }
    }
    if (matched == null) {
      return SessionBindResult.failed(SessionBindFailure.notRegistered);
    }

    if (!_isActiveFlag(matched['cf_active'])) {
      return SessionBindResult.failed(SessionBindFailure.disabled);
    }

    final salespersonId = _nonEmpty(matched['cf_salesperson']);
    final salespersonName = _nonEmpty(matched['cf_salesperson_formatted']);
    final cashAccountId = _nonEmpty(matched['cf_cash_account']);
    final cashAccountName = _nonEmpty(matched['cf_cash_account_formatted']);
    final vanLocationId = _nonEmpty(matched['cf_van_location']);
    final vanLocationName = _nonEmpty(matched['cf_van_location_formatted']);
    final seriesPrefix = _nonEmpty(matched['cf_series_prefix']);

    // Prefix is required for offline document numbering — without it
    // DocumentNumberService.nextNumber throws mid-save. Fail at bind instead.
    if (salespersonId == null || cashAccountId == null || seriesPrefix == null) {
      return SessionBindResult.failed(SessionBindFailure.notFullyMapped);
    }

    // Confirm the looked-up salesperson exists & is active in /salespersons
    // (source of truth for name + lifecycle).
    final cachedSalespersons = _dbService.getSalespersons();
    Salesperson? confirmedSalesperson;
    for (final sp in cachedSalespersons) {
      if (sp.id == salespersonId) {
        confirmedSalesperson = sp;
        break;
      }
    }
    if (confirmedSalesperson == null ||
        confirmedSalesperson.status.toLowerCase() == 'inactive') {
      return SessionBindResult.failed(SessionBindFailure.notFullyMapped);
    }

    final ordersOnly = vanLocationId == null;
    if (ordersOnly && primary == null) {
      // No van and no primary location resolved — nothing usable to bind.
      return SessionBindResult.failed(SessionBindFailure.network);
    }

    final assignedLocationId = ordersOnly ? primary!.id : vanLocationId;
    final assignedLocationName = ordersOnly
        ? primary!.name
        : (vanLocationName ??
            () {
              for (final w in warehouses) {
                if (w.id == assignedLocationId) return w.name;
              }
              return null;
            }());

    final resolved = Salesperson(
      id: salespersonId,
      name: confirmedSalesperson.name.isNotEmpty
          ? confirmedSalesperson.name
          : (salespersonName ?? ''),
      email: confirmedSalesperson.email,
      phone: normalizedPhone,
      locationId: assignedLocationId,
      locationName: assignedLocationName,
      voucherPrefix: seriesPrefix,
      cashAccountId: cashAccountId,
      cashAccountName: cashAccountName,
      status: 'active',
    );

    await _dbService.setSessionPhone(normalizedPhone);
    await _dbService.setAssignedWarehouseId(assignedLocationId);
    await _dbService.setOrdersOnlyMode(ordersOnly);
    await _dbService.setCashAccountId(cashAccountId);
    await _dbService.setVoucherPrefix(seriesPrefix);
    await _dbService.saveCurrentSalesperson(resolved);
    return SessionBindResult.success(resolved);
  }

  @override
  Future<Salesperson?> resolveActiveSalesperson(String phone) async {
    final result = await verifyAndBindSession(phone);
    return result.salesperson;
  }
}
