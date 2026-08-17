import '../../domain/models/customer.dart';
import '../models/customer_model.dart';
import '../../domain/models/customer_ledger.dart';
import '../../domain/models/submit_result.dart';
import '../../domain/repositories/customer_repository.dart';
import '../models/sync_queue_item.dart';
import '../services/app_logger.dart';
import '../services/hive_database_service.dart';
import '../services/sync_worker.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [CustomerRepository] backed by a local Hive database cache.
class CustomerRepositoryImpl implements CustomerRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;
  final SyncWorker? _syncWorker;

  CustomerRepositoryImpl({
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
  List<Customer> getCustomers() => _dbService.getCustomers();

  @override
  Future<void> saveCustomers(List<Customer> customers) =>
      _dbService.saveCustomers(customers);

  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(
    Customer customer,
  ) async {
    final id = customer.id.trim();
    if (id.isEmpty || id.startsWith('temp_')) {
      return (customer: customer, offlineFallback: false);
    }

    Customer merge(
      Customer base, {
      required String trn,
      required String address,
      double? latitude,
      double? longitude,
    }) {
      return base.copyWith(
        trn: base.trn.trim().isNotEmpty ? base.trn : trn,
        address: base.address.trim().isNotEmpty ? base.address : address,
        latitude: base.latitude ?? latitude,
        longitude: base.longitude ?? longitude,
      );
    }

    if (customer.trn.trim().isNotEmpty) {
      return (customer: customer, offlineFallback: false);
    }

    if (_dbService.hasCustomerDetail(id)) {
      final cached = _dbService.getCustomerDetail(id)!;
      return (
        customer: merge(
          customer,
          trn: cached.trn,
          address: cached.address,
          latitude: cached.latitude,
          longitude: cached.longitude,
        ),
        offlineFallback: false,
      );
    }

    try {
      final detail = await _apiClient.fetchContactDetail(id);
      final parsed = CustomerModel.fromJson(detail);
      final trn = parsed.trn.trim();
      final address = parsed.address.trim();
      final lat = parsed.latitude;
      final lng = parsed.longitude;
      await _dbService.saveCustomerDetail(
        id,
        trn: trn,
        address: address,
        latitude: lat,
        longitude: lng,
      );
      final resolved = merge(
        customer,
        trn: trn,
        address: address,
        latitude: lat,
        longitude: lng,
      );
      await _dbService.upsertCustomer(resolved);
      return (customer: resolved, offlineFallback: false);
    } catch (e) {
      AppLogger.error(
        'CustomerRepository',
        'resolveCustomerDetails($id) error: $e',
      );
      return (customer: customer, offlineFallback: true);
    }
  }

  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) =>
      _dbService.updateCustomerGps(customerId, latitude, longitude);

  @override
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) =>
      _dbService.updateCustomerContactFields(
        customerId,
        phone: phone,
        trn: trn,
      );

  @override
  Customer? getCustomerById(String id) => _dbService.getCustomerById(id);

  @override
  Future<void> pushCustomerGpsRemote(
    String customerId,
    double latitude,
    double longitude,
  ) async {
    await _apiClient.updateCustomerGps(customerId, latitude, longitude);
  }

  @override
  Future<void> pushCustomerContactFieldsRemote(
    String customerId, {
    String? phone,
    String? trn,
  }) async {
    await _apiClient.updateCustomerContactFields(
      customerId,
      phone: phone,
      trn: trn,
    );
  }

  @override
  Future<CustomerLedger> fetchCustomerLedger(
    String customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchCustomerStatement(
      customerId,
      startDate: startDate,
      endDate: endDate,
    );

    final rawWithName = Map<String, dynamic>.from(raw);
    if ((rawWithName['contact_name'] as String? ?? '').isEmpty ||
        rawWithName['contact_name'] == 'Demo Customer') {
      final customer = _dbService
          .getCustomers()
          .where((c) => c.id == customerId)
          .firstOrNull;
      if (customer != null) {
        rawWithName['contact_name'] = customer.name;
      }
    }

    return CustomerLedger.fromJson(rawWithName, customerId);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) =>
      _dbService.enqueueSyncItem(item);

  @override
  Future<SubmitResult> submitOrEnqueue(SyncQueueItem item) {
    return _worker.submitOrEnqueue(item);
  }
}
