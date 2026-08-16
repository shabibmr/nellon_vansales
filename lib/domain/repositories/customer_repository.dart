import '../models/customer.dart';
import '../models/customer_ledger.dart';
import '../../data/models/sync_queue_item.dart';

/// Abstract contract for customer master data, contact-field enrichment, and ledger lookups.
abstract class CustomerRepository {
  /// Retrieves the list of master customer entities synced to the van.
  List<Customer> getCustomers();

  /// Saves or refreshes customer entities in local cache.
  Future<void> saveCustomers(List<Customer> customers);

  /// Updates GPS coordinates for a single customer (by id) in local cache.
  /// Used for on-the-fly enrichment when capturing location for existing customers.
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude);

  /// Updates phone and/or TRN for a single customer in local cache.
  ///
  /// Also refreshes the contact-detail TRN cache so a later masters refresh
  /// does not wipe a user-entered tax number.
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  });

  /// Resolves TRN / billing address on demand (`GET /contacts/{id}`).
  ///
  /// The contacts list never includes `tax_reg_no`. First search tap fetches
  /// and caches the detail (even when TRN is empty). Thermal print reads Hive
  /// only. [offlineFallback] is true when a required fetch failed.
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(
    Customer customer,
  );

  /// Indexed customer lookup (local cache).
  Customer? getCustomerById(String id);

  /// Best-effort remote GPS push for an existing Zoho contact. Throws on failure
  /// so callers can fall back to the offline queue.
  Future<void> pushCustomerGpsRemote(
    String customerId,
    double latitude,
    double longitude,
  );

  /// Best-effort remote phone / TRN push for an existing Zoho contact.
  /// Throws on failure so callers can fall back to the offline queue.
  Future<void> pushCustomerContactFieldsRemote(
    String customerId, {
    String? phone,
    String? trn,
  });

  /// Fetches full ledger statement for a customer over an optional date range.
  Future<CustomerLedger> fetchCustomerLedger(
    String customerId, {
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Appends an unsynced transaction item to the local offline synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item);
}
