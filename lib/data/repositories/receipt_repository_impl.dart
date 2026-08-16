import '../../domain/models/open_invoice.dart';
import '../../domain/models/receipt_voucher.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../models/open_invoice_model.dart';
import '../models/receipt_voucher_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [ReceiptRepository] backed by a local Hive
/// database cache and the Zoho Books API.
class ReceiptRepositoryImpl implements ReceiptRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  ReceiptRepositoryImpl({required this._dbService, required this._apiClient});

  @override
  List<ReceiptVoucher> getLocalReceipts() =>
      _sessionScopedReceipts(_dbService.getLocalReceipts());

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) =>
      _dbService.saveLocalReceipt(voucher);

  @override
  Future<ReceiptVoucher?> fetchReceiptById(
    String paymentId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    if (paymentId.isEmpty) return null;
    ReceiptVoucher? local;
    for (final rec in _dbService.getLocalReceipts()) {
      if (rec.id == paymentId) {
        local = rec;
        break;
      }
    }
    if (!forceRemote && local != null) return local;

    try {
      final json = await _apiClient.fetchReceiptDetail(paymentId);
      if (json.isEmpty) {
        if (allowOfflineFallback && local != null) return local;
        return null;
      }
      final remote = _receiptFromZoho(json);
      await _dbService.saveRemoteReceipts([remote]);
      return remote;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchReceipts(
      startDate: startDate,
      endDate: endDate,
    );
    final vanId = _dbService.assignedWarehouseId;
    final receipts = raw.map((json) {
      final rec = _receiptFromZoho(json);
      if (vanId == null || vanId.isEmpty) return rec;
      return rec.copyWith(locationId: vanId);
    }).toList();
    await _dbService.saveRemoteReceipts(receipts);
    // API is already series-scoped; re-apply client-side so a polluted local
    // cache (pre-filter downloads) cannot surface other salesmen's receipts.
    return getLocalReceipts();
  }

  /// Zoho header `location_id` is org primary, not van warehouse.
  ReceiptVoucher _receiptFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map.remove('location_id');
    return ReceiptVoucherModel.fromJson(map);
  }

  /// Keeps receipts whose app series number matches this session's
  /// `{voucherPrefix}RCT-` (stored as [ReceiptVoucher.paymentNumber] offline
  /// and as Zoho `reference_number` after sync). No prefix → unfiltered.
  List<ReceiptVoucher> _sessionScopedReceipts(List<ReceiptVoucher> all) {
    final prefix = _dbService.voucherPrefix?.trim();
    if (prefix == null || prefix.isEmpty) return all;
    final series = '${prefix}RCT-';
    return all
        .where(
          (r) =>
              r.paymentNumber.startsWith(series) ||
              r.referenceNumber.startsWith(series),
        )
        .toList();
  }

  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) =>
      _dbService.getOpenInvoices(customerId: customerId);

  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({
    String? customerId,
  }) async {
    final raw = await _apiClient.fetchOpenInvoices(customerId: customerId);
    final list = raw.map((json) => OpenInvoiceModel.fromJson(json)).toList();

    if (customerId == null || customerId.isEmpty) {
      await _dbService.saveOpenInvoices(list);
      return list;
    }

    // Merge customer-scoped live results into the local cache without
    // wiping open invoices for other customers.
    final others = _dbService
        .getOpenInvoices()
        .where((i) => i.customerId != customerId)
        .toList();
    await _dbService.saveOpenInvoices([...others, ...list]);
    return list;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) =>
      _dbService.enqueueSyncItem(item);
}
