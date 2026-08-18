import 'dart:convert';

import '../../domain/models/salesperson.dart';
import '../../domain/models/session_bind_result.dart';
import '../../domain/models/warehouse.dart';
import '../../domain/repositories/salesperson_repository.dart';
import '../../domain/utils/phone_normalizer.dart';
import '../models/salesperson_model.dart';
import '../models/warehouse_model.dart';
import '../services/app_logger.dart';
import '../services/debug_file_logger.dart';
import '../services/error_classification.dart';
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
    AppLogger.info(
      'SalespersonRepo',
      'Cached ${salespersons.length} salesperson(s) from Zoho: ${jsonEncode(raw)}',
    );
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
    DebugFileLogger.log(
      '[SalespersonBind] session phone raw="$phone" normalized="$normalizedPhone"',
    );
    if (normalizedPhone.isEmpty) {
      return SessionBindResult.failed(SessionBindFailure.notRegistered);
    }

    List<Map<String, dynamic>> profiles;
    List<Warehouse> warehouses;
    Warehouse? primary;
    try {
      profiles = await _apiClient.fetchSalespersonProfiles();
      AppLogger.info(
        'SalespersonRepo',
        'Salesperson profiles fetched for verification (${profiles.length} total): ${jsonEncode(profiles)}',
      );
      DebugFileLogger.log(
        '[SalespersonBind] comparing against ${profiles.length} profile(s): '
        '${jsonEncode(profiles.map((r) => {
              'record_name': r['record_name'],
              'normalized': normalizePhone((r['record_name'] ?? '').toString()),
              'cf_active': r['cf_active'],
            }).toList())}',
      );
      await _fetchAndCacheSalespersons();
      final locationRaw = await _apiClient.fetchWarehouses();
      warehouses = locationRaw.map((w) => WarehouseModel.fromJson(w)).toList();
      await _dbService.saveWarehouses(warehouses);
      AppLogger.info(
        'SalespersonRepo',
        'Warehouses/locations fetched for verification (${warehouses.length} total): ${jsonEncode(locationRaw)}',
      );
      for (final w in warehouses) {
        if (w.isPrimary) {
          primary = w;
          break;
        }
      }
      primary ??= warehouses.isNotEmpty ? warehouses.first : null;
      await _dbService.setPrimaryWarehouseId(primary?.id);
    } catch (e) {
      // A missing credential triple is a configuration fault, not a network
      // one — reporting it as "check your connection" sends the driver into
      // an endless retry on something only an admin can fix.
      return SessionBindResult.failed(
        isZohoNotConfigured(e)
            ? SessionBindFailure.serverNotConfigured
            : SessionBindFailure.network,
      );
    }

    Map<String, dynamic>? matched;
    for (final r in profiles) {
      final recordPhoneRaw = (r['record_name'] ?? '').toString();
      final recordPhoneNorm = normalizePhone(recordPhoneRaw);
      final isMatch = recordPhoneNorm == normalizedPhone;
      DebugFileLogger.log(
        '[SalespersonBind] Comparing phone: input="$normalizedPhone" vs '
        'profile record_name="$recordPhoneRaw" (norm="$recordPhoneNorm") => match=$isMatch',
      );
      if (isMatch) {
        matched = r;
        break;
      }
    }
    if (matched == null) {
      AppLogger.warning(
        'SalespersonRepo',
        'No matching salesperson profile found for phone: $normalizedPhone',
      );
      DebugFileLogger.log(
        '[SalespersonBind] NO MATCH for normalized="$normalizedPhone" '
        'against the ${profiles.length} profile(s) logged above.',
      );
      return SessionBindResult.failed(SessionBindFailure.notRegistered);
    }

    DebugFileLogger.log(
      '[SalespersonBind] MATCHED normalized="$normalizedPhone" '
      'to record_name="${matched['record_name']}"',
    );

    AppLogger.info(
      'SalespersonRepo',
      'Matched salesperson profile for phone $normalizedPhone: ${jsonEncode(matched)}',
    );

    final rawActive = matched['cf_active'];
    final isActive = _isActiveFlag(rawActive);
    DebugFileLogger.log(
      '[SalespersonBind] Checking cf_active: raw="$rawActive" (${rawActive.runtimeType}) => isActive=$isActive',
    );

    if (!isActive) {
      DebugFileLogger.log(
        '[SalespersonBind] REJECTED: cf_active is false/disabled for phone $normalizedPhone',
      );
      return SessionBindResult.failed(SessionBindFailure.disabled);
    }

    final salespersonId = _nonEmpty(matched['cf_salesperson']);
    final salespersonName = _nonEmpty(matched['cf_salesperson_formatted']);
    final cashAccountId = _nonEmpty(matched['cf_cash_account']);
    final cashAccountName = _nonEmpty(matched['cf_cash_account_formatted']);
    final vanLocationId = _nonEmpty(matched['cf_van_location']);
    final vanLocationName = _nonEmpty(matched['cf_van_location_formatted']);
    final seriesPrefix = _nonEmpty(matched['cf_series_prefix']);

    DebugFileLogger.log(
      '[SalespersonBind] Extracted profile fields: '
      'cf_salesperson="$salespersonId" (formatted: "$salespersonName"), '
      'cf_cash_account="$cashAccountId" (formatted: "$cashAccountName"), '
      'cf_series_prefix="$seriesPrefix", '
      'cf_van_location="$vanLocationId" (formatted: "$vanLocationName")',
    );

    // Prefix is required for offline document numbering — without it
    // DocumentNumberService.nextNumber throws mid-save. Fail at bind instead.
    if (salespersonId == null || cashAccountId == null || seriesPrefix == null) {
      DebugFileLogger.log(
        '[SalespersonBind] REJECTED: Missing required fields: '
        'salespersonId=${salespersonId != null} ($salespersonId), '
        'cashAccountId=${cashAccountId != null} ($cashAccountId), '
        'seriesPrefix=${seriesPrefix != null} ($seriesPrefix)',
      );
      return SessionBindResult.failed(SessionBindFailure.notFullyMapped);
    }

    // Confirm the looked-up salesperson exists & is active in /salespersons
    // (source of truth for name + lifecycle).
    final cachedSalespersons = _dbService.getSalespersons();
    DebugFileLogger.log(
      '[SalespersonBind] Checking cf_salesperson="$salespersonId" against '
      '${cachedSalespersons.length} cached Zoho salesperson(s): '
      '${jsonEncode(cachedSalespersons.map((s) => {'id': s.id, 'name': s.name, 'status': s.status}).toList())}',
    );

    Salesperson? confirmedSalesperson;
    for (final sp in cachedSalespersons) {
      final idMatch = sp.id == salespersonId;
      DebugFileLogger.log(
        '[SalespersonBind] Comparing salesperson ID: target cf_salesperson="$salespersonId" '
        'vs Zoho salesperson id="${sp.id}" (name="${sp.name}", status="${sp.status}") => match=$idMatch',
      );
      if (idMatch) {
        confirmedSalesperson = sp;
        break;
      }
    }
    if (confirmedSalesperson == null) {
      DebugFileLogger.log(
        '[SalespersonBind] REJECTED: cf_salesperson "$salespersonId" NOT FOUND in Zoho /salespersons list.',
      );
      return SessionBindResult.failed(SessionBindFailure.notFullyMapped);
    }

    final isConfirmedActive = confirmedSalesperson.status.toLowerCase() != 'inactive';
    DebugFileLogger.log(
      '[SalespersonBind] Checking confirmed salesperson status: '
      'name="${confirmedSalesperson.name}", status="${confirmedSalesperson.status}" => isActive=$isConfirmedActive',
    );

    if (!isConfirmedActive) {
      DebugFileLogger.log(
        '[SalespersonBind] REJECTED: Confirmed salesperson "${confirmedSalesperson.name}" is inactive in Zoho.',
      );
      return SessionBindResult.failed(SessionBindFailure.notFullyMapped);
    }

    final ordersOnly = vanLocationId == null;
    DebugFileLogger.log(
      '[SalespersonBind] Checking van location: cf_van_location="$vanLocationId" '
      '=> ordersOnlyMode=$ordersOnly, primaryWarehouse="${primary?.id}" (${primary?.name})',
    );

    if (ordersOnly && primary == null) {
      // No van and no primary location resolved — nothing usable to bind.
      DebugFileLogger.log(
        '[SalespersonBind] REJECTED: No van location and no primary warehouse resolved.',
      );
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

    AppLogger.info(
      'SalespersonRepo',
      'Bound salesperson session successfully: name="${resolved.name}", '
      'id="${resolved.id}", phone="${resolved.phone}", '
      'location="${resolved.locationName}" (id: "${resolved.locationId}"), '
      'cashAccount="${resolved.cashAccountName}" (id: "${resolved.cashAccountId}"), '
      'prefix="${resolved.voucherPrefix}", ordersOnly=$ordersOnly',
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
