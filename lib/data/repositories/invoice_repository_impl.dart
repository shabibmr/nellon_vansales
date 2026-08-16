import '../../domain/models/sales_invoice.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../models/sales_invoice_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [InvoiceRepository] backed by a local Hive
/// database cache and the Zoho Books API.
class InvoiceRepositoryImpl implements InvoiceRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  InvoiceRepositoryImpl({required this._dbService, required this._apiClient});

  @override
  List<SalesInvoice> getLocalInvoices() => _dbService.getLocalInvoices();

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) =>
      _dbService.saveLocalInvoice(invoice);

  @override
  Future<SalesInvoice?> fetchInvoiceById(
    String invoiceId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    if (invoiceId.isEmpty) return null;
    SalesInvoice? local;
    for (final inv in _dbService.getLocalInvoices()) {
      if (inv.id == invoiceId) {
        local = inv;
        break;
      }
    }
    if (!forceRemote && local != null) return local;

    try {
      final json = await _apiClient.fetchInvoiceDetail(invoiceId);
      if (json.isEmpty) {
        if (allowOfflineFallback && local != null) return local;
        return null;
      }
      final remote = _invoiceFromZoho(json);
      await _dbService.saveRemoteInvoices([remote]);
      return remote;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Header-only list path (no per-invoice detail). Full line items load
    // lazily via [fetchInvoiceById] when the editor opens.
    final raw = await _apiClient.fetchInvoiceHeaders(
      startDate: startDate,
      endDate: endDate,
    );
    final vanId = _dbService.assignedWarehouseId;
    final invoices = raw.map((json) {
      final inv = _invoiceFromZoho(json);
      if (vanId == null || vanId.isEmpty) return inv;
      return inv.copyWith(locationId: vanId);
    }).toList();
    await _dbService.saveRemoteInvoices(invoices);
    return _dbService.getLocalInvoices();
  }

  /// Zoho header `location_id` is org primary, not van warehouse.
  SalesInvoice _invoiceFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map.remove('location_id');
    return SalesInvoiceModel.fromJson(map);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) =>
      _dbService.enqueueSyncItem(item);
}
