import '../../domain/models/sales_invoice.dart';
import '../../domain/models/sales_order.dart';
import '../../domain/models/submit_result.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../models/sales_invoice_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/sync_worker.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [InvoiceRepository] backed by a local Hive
/// database cache and the Zoho Books API.
class InvoiceRepositoryImpl implements InvoiceRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;
  final SyncWorker? _syncWorker;

  InvoiceRepositoryImpl({
    required HiveDatabaseService dbService,
    required ZohoApiClient apiClient,
    SyncWorker? syncWorker,
  }) : _dbService = dbService,
       _apiClient = apiClient,
       _syncWorker = syncWorker;

  SyncWorker get _worker {
    final worker = _syncWorker;
    if (worker == null) {
      throw StateError('submit* requires SyncWorker');
    }
    return worker;
  }

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

  SyncQueueItem _invoiceItem(SalesInvoice invoice) {
    return SyncQueueItem(
      id: invoice.id,
      type: 'invoice',
      payload: SalesInvoiceModel.fromDomain(invoice).toJson(),
      status: SyncStatus.pending,
      timestamp: DateTime.now(),
    );
  }

  SyncQueueItem _convertSoItem({
    required SalesOrder order,
    required SalesInvoice invoice,
  }) {
    return SyncQueueItem(
      id: invoice.id,
      type: 'convert_so',
      payload: {
        'salesorder_id': order.zohoOrderId ?? order.id,
        'source_order_id': order.id,
        'local_invoice_id': invoice.id,
        'invoice': SalesInvoiceModel.fromDomain(invoice).toJson(),
      },
      status: SyncStatus.pending,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<void> enqueueInvoice(SalesInvoice invoice) {
    return _dbService.enqueueSyncItem(_invoiceItem(invoice));
  }

  @override
  Future<void> enqueueConvertSalesOrder({
    required SalesOrder order,
    required SalesInvoice invoice,
  }) {
    return _dbService.enqueueSyncItem(
      _convertSoItem(order: order, invoice: invoice),
    );
  }

  @override
  Future<SubmitResult> submitInvoice(SalesInvoice invoice) {
    return _worker.submitOrEnqueue(_invoiceItem(invoice));
  }

  @override
  Future<SubmitResult> submitConvertSalesOrder({
    required SalesOrder order,
    required SalesInvoice invoice,
  }) {
    return _worker.submitOrEnqueue(
      _convertSoItem(order: order, invoice: invoice),
    );
  }
}
