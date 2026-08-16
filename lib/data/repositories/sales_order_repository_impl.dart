import '../../domain/models/sales_order.dart';
import '../../domain/repositories/sales_order_repository.dart';
import '../models/sales_order_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [SalesOrderRepository] backed by a local Hive
/// database cache and the Zoho Books API.
class SalesOrderRepositoryImpl implements SalesOrderRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  SalesOrderRepositoryImpl({
    required this._dbService,
    required this._apiClient,
  });

  @override
  List<SalesOrder> getLocalOrders() => _dbService.getLocalOrders();

  @override
  Future<void> saveLocalOrder(SalesOrder order) =>
      _dbService.saveLocalOrder(order);

  @override
  Future<void> enqueueSalesOrder(
    SalesOrder order, {
    required bool isUpdate,
  }) async {
    final payload = SalesOrderModel.fromDomain(order).toJson();
    if (isUpdate) {
      final zohoId = order.zohoOrderId;
      if (zohoId != null && zohoId.isNotEmpty) {
        payload['salesorder_id'] = zohoId;
      }
    }
    await _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: order.id,
        type: isUpdate ? 'update_sales_order' : 'sales_order',
        payload: payload,
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchSalesOrders(
      startDate: startDate,
      endDate: endDate,
    );
    // Stamp with this session's van warehouse so [getLocalOrders] location
    // filter keeps them. Zoho header location_id is the org primary branch
    // (stripped in [_orderFromZoho]); without a van stamp, rows either stay
    // null (ok) or re-merge an old HQ id from Hive and disappear for every van.
    final vanId = _dbService.assignedWarehouseId;
    final orders = raw.map((json) {
      final order = _orderFromZoho(json);
      if (vanId == null || vanId.isEmpty) return order;
      return order.copyWith(locationId: vanId);
    }).toList();
    // List fetch is authoritative for the requested window: drop Hive rows
    // that fall in-range but are gone from Zoho (deleted remotely).
    await _dbService.saveRemoteOrders(
      orders,
      pruneMissingInRange: true,
      rangeStart: startDate,
      rangeEnd: endDate,
    );
    return _dbService.getLocalOrders();
  }

  @override
  Future<SalesOrder?> fetchRemoteOrder(
    String zohoOrderId, {
    bool allowOfflineFallback = false,
  }) async {
    SalesOrder? local;
    for (final o in _dbService.getLocalOrders()) {
      if (o.id == zohoOrderId || o.zohoOrderId == zohoOrderId) {
        local = o;
        break;
      }
    }
    try {
      final json = await _apiClient.fetchSalesOrder(zohoOrderId);
      if (json.isEmpty) {
        if (allowOfflineFallback) return local;
        return null;
      }
      final order = _orderFromZoho(json);
      await _dbService.saveRemoteOrders([order]);
      // Return the merged/patched cache entry, not the raw Zoho parse — the
      // raw parse never carries `locationId` (Zoho has no such field), while
      // saveRemoteOrders folds in whatever this device previously stamped.
      for (final o in _dbService.getLocalOrders()) {
        if (o.id == order.id) return o;
      }
      return order;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  /// Parses a Zoho `salesorder` envelope, stamping `zoho_order_id` from
  /// `salesorder_id`. Zoho never sends the former, so without this every
  /// downloaded order looks unsynced and an edit would be pushed as a *create*
  /// instead of `PUT /salesorders/{id}` (see SalesOrderEditorBloc save path). The
  /// stamp is done here, not in [SalesOrderModel.fromJson], because that
  /// factory also reads back local records whose `salesorder_id` is a
  /// `temp_so_…` id that Zoho has never seen.
  ///
  /// **location_id is not mapped.** Zoho's header `location_id` is the org
  /// primary / branch location, not the van warehouse id used for on-device
  /// list scoping ([HiveDatabaseService.getLocalOrders]). Mapping it in caused
  /// remote orders (e.g. Test Customer) to save under HQ id and then disappear
  /// from every van session after `getLocalOrders` filtered them out.
  SalesOrder _orderFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map['zoho_order_id'] = json['salesorder_id'];
    map.remove('location_id');
    return SalesOrderModel.fromJson(map);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) =>
      _dbService.enqueueSyncItem(item);
}
