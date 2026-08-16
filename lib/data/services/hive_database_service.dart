import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/item.dart';
import '../../domain/models/route.dart';
import '../../domain/models/sales_invoice.dart';
import '../../domain/models/receipt_voucher.dart';
import '../../domain/models/sales_return.dart';
import '../../domain/models/expense_entry.dart';
import '../../domain/models/cash_closing.dart';
import '../../domain/models/warehouse.dart';
import '../../domain/models/salesperson.dart';
import '../../domain/models/payment_account.dart';
import '../../domain/models/tax.dart';
import '../../domain/models/expense_account.dart';
import '../../domain/models/organization.dart';
import '../../domain/models/open_invoice.dart';
import '../../domain/models/sales_order.dart';
import '../../domain/models/stock_transfer.dart';
import '../../domain/models/unit_conversion.dart';
import '../../domain/utils/stock_rules.dart';
import '../models/customer_model.dart';
import '../models/item_model.dart';
import '../models/unit_conversion_model.dart';
import '../models/sales_invoice_model.dart';
import '../models/receipt_voucher_model.dart';
import '../models/sales_return_model.dart';
import '../models/expense_entry_model.dart';
import '../models/cash_closing_model.dart';
import '../models/warehouse_model.dart';
import '../models/salesperson_model.dart';
import '../models/payment_account_model.dart';
import '../models/tax_model.dart';
import '../models/expense_account_model.dart';
import '../models/organization_model.dart';
import '../models/open_invoice_model.dart';
import '../models/sales_order_model.dart';
import '../models/stock_transfer_model.dart';
import '../models/sync_queue_item.dart';

/// Database service backing the application's offline-first capabilities using Hive boxes.
///
/// Manages three distinct storage areas:
/// 1. `_masterBox`: Stores cached Zoho Books configurations, settings, items, and customer routes.
/// 2. `_syncQueueBox`: Manages sequential tasks/payloads waiting to sync when online.
/// 3. `_localHistoryBox`: Records locally created transactions instantly so UI displays them with zero latency.
class HiveDatabaseService {
  static const String _masterBoxName = 'master_data_box';
  static const String _syncQueueBoxName = 'sync_queue_box';
  static const String _localHistoryBoxName = 'local_history_box';
  static const String _itemUomBoxName = 'item_uom_box';

  late Box _masterBox;
  late Box _syncQueueBox;
  late Box _localHistoryBox;
  late Box _itemUomBox;

  /// Lazily-built id-indexed cache backing [getCustomerById], invalidated
  /// whenever [saveCustomers] persists a new master list.
  Map<String, Customer>? _customerCache;

  /// Serializes read-modify-write access to the `sales_orders` local-history
  /// key. [saveLocalOrder] (editor save, post-sync id patch) and
  /// [saveRemoteOrders] (list refresh) both read the full list, compute a
  /// merged copy, and write it back — without this, two overlapping calls
  /// (e.g. an editor save's background sync completion racing an immediate
  /// list reload) can interleave and one write silently discards the other.
  Future<void> _ordersLock = Future.value();

  /// Runs [action] only after every previously-queued order write has
  /// finished, guaranteeing each read-modify-write cycle completes atomically
  /// relative to the others.
  Future<T> _withOrdersLock<T>(Future<T> Function() action) {
    final previous = _ordersLock;
    final completer = Completer<void>();
    _ordersLock = completer.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        completer.complete();
      }
    });
  }

  /// Initializes the local database bindings and opens Hive boxes.
  Future<void> init() async {
    await Hive.initFlutter();
    _masterBox = await Hive.openBox(_masterBoxName);
    _syncQueueBox = await Hive.openBox(_syncQueueBoxName);
    _localHistoryBox = await Hive.openBox(_localHistoryBoxName);
    _itemUomBox = await Hive.openBox(_itemUomBoxName);
  }

  /// Clears all local caches, queues, and transaction histories.
  Future<void> clearAll() async {
    await _masterBox.clear();
    await _syncQueueBox.clear();
    await _localHistoryBox.clear();
    await _itemUomBox.clear();
  }

  /// Gets the ID of the selected active delivery route.
  String? get activeRouteId => _masterBox.get('active_route_id');

  /// Saves the active delivery route ID.
  Future<void> setActiveRouteId(String? routeId) async {
    await _masterBox.put('active_route_id', routeId);
  }

  /// Gets the physical warehouse ID mapped to the van.
  String? get assignedWarehouseId => _masterBox.get('assigned_warehouse_id');

  /// Mapps a specific Zoho warehouse ID to this local van sales session.
  Future<void> setAssignedWarehouseId(String? warehouseId) async {
    await _masterBox.put('assigned_warehouse_id', warehouseId);
  }

  /// Org HQ / primary Zoho location id (from `is_primary` on `GET /locations`).
  String? get primaryWarehouseId => _masterBox.get('primary_warehouse_id');

  /// Persists the organization primary location for Issue-to-Van HQ side.
  Future<void> setPrimaryWarehouseId(String? warehouseId) async {
    if (warehouseId == null || warehouseId.isEmpty) {
      await _masterBox.delete('primary_warehouse_id');
    } else {
      await _masterBox.put('primary_warehouse_id', warehouseId);
    }
  }

  /// Local voucher number prefix for the active van/location session.
  String? get voucherPrefix => _masterBox.get('voucher_prefix') as String?;

  /// Persists the session voucher prefix (empty/null clears).
  Future<void> setVoucherPrefix(String? prefix) async {
    final trimmed = prefix?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _masterBox.delete('voucher_prefix');
    } else {
      await _masterBox.put('voucher_prefix', trimmed);
    }
  }

  /// E.164 phone number bound to the current session (`cm_salesperson_profile.record_name`).
  String? get sessionPhone => _masterBox.get('session_phone') as String?;

  /// Persists the session phone (empty/null clears).
  Future<void> setSessionPhone(String? phone) async {
    final trimmed = phone?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _masterBox.delete('session_phone');
    } else {
      await _masterBox.put('session_phone', trimmed);
    }
  }

  /// Zoho Chart of Accounts id for the session salesperson's cash ledger
  /// (`cf_cash_account`); used as the receipt deposit account and expense
  /// paid-through account.
  String? get cashAccountId => _masterBox.get('cash_account_id') as String?;

  /// Persists the session cash account id (empty/null clears).
  Future<void> setCashAccountId(String? accountId) async {
    final trimmed = accountId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _masterBox.delete('cash_account_id');
    } else {
      await _masterBox.put('cash_account_id', trimmed);
    }
  }

  /// Whether the session salesperson has no van mapped (`cf_van_location`
  /// empty) and is therefore restricted to Sales Order creation only.
  bool get ordersOnlyMode =>
      _masterBox.get('orders_only_mode', defaultValue: false) as bool;

  /// Persists the orders-only session flag.
  Future<void> setOrdersOnlyMode(bool enabled) async {
    await _masterBox.put('orders_only_mode', enabled);
  }

  /// Per-document-type offline numbering counter (e.g. tag `'INV'`, `'SO'`,
  /// `'RCT'`, `'CN'`). Null when never seeded.
  int? getDocCounter(String typeTag) =>
      _masterBox.get('doc_counter_$typeTag') as int?;

  /// Persists the next-to-use counter value for [typeTag].
  Future<void> setDocCounter(String typeTag, int value) async {
    await _masterBox.put('doc_counter_$typeTag', value);
  }

  /// Preferred Bluetooth thermal printer (JSON map: name + macAddress).
  Map<String, dynamic>? getPreferredBluetoothPrinter() {
    final raw = _masterBox.get('preferred_bluetooth_printer');
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Persists or clears the preferred Bluetooth thermal printer.
  Future<void> setPreferredBluetoothPrinter(Map<String, dynamic>? json) async {
    if (json == null) {
      await _masterBox.delete('preferred_bluetooth_printer');
    } else {
      await _masterBox.put('preferred_bluetooth_printer', json);
    }
  }

  /// Thermal paper size storage key (`inch4` | `inch2`). Defaults to null → inch4.
  String? get thermalPaperSizeKey =>
      _masterBox.get('thermal_paper_size') as String?;

  /// Persists thermal paper size key.
  Future<void> setThermalPaperSizeKey(String key) async {
    await _masterBox.put('thermal_paper_size', key);
  }

  /// Retrieves the list of synced master customer records.
  ///
  /// Uses `.map<Customer>` so the list is a true [List]<[Customer]> at runtime.
  /// Without the type arg, Dart builds a `List<CustomerModel>`; later
  /// `list[i] = customer.copyWith(...)` throws because [Customer.copyWith]
  /// returns a plain [Customer] (list covariance).
  List<Customer> getCustomers() {
    final rawList = _masterBox.get('customers', defaultValue: []);
    return (rawList as List)
        .map<Customer>(
          (item) => _applyCachedCustomerDetail(
            CustomerModel.fromJson(
              Map<String, dynamic>.from(jsonDecode(item)),
            ),
          ),
        )
        .toList();
  }

  /// Saves or refreshes customer master lists.
  ///
  /// Re-applies any lazily fetched TRN / address from [saveCustomerDetail]
  /// so a full masters replace does not wipe print-ready fields.
  Future<void> saveCustomers(List<Customer> customers) async {
    final merged = customers.map(_applyCachedCustomerDetail).toList();
    final serialized = merged
        .map((c) => jsonEncode(CustomerModel.fromDomain(c).toJson()))
        .toList();
    await _masterBox.put('customers', serialized);
    _customerCache = null;
  }

  /// Looks up a single customer by id via an in-memory index built from
  /// [getCustomers], avoiding a full deserialize-and-scan on every call.
  Customer? getCustomerById(String id) {
    _customerCache ??= {for (final c in getCustomers()) c.id: c};
    return _customerCache![id];
  }

  static const _customerDetailsKey = 'customer_details';

  Map<String, Map<String, String>> _readCustomerDetails() {
    final raw = _masterBox.get(_customerDetailsKey);
    if (raw == null) return {};
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) return {};
    return decoded.map((key, value) {
      final inner = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
      return MapEntry(key.toString(), {
        'trn': (inner['trn'] ?? '').toString(),
        'address': (inner['address'] ?? '').toString(),
      });
    });
  }

  /// Whether [GET /contacts/{id}] has already been fetched for this customer.
  ///
  /// A present-but-empty TRN means "checked, none exists" — skip re-fetch.
  bool hasCustomerDetail(String id) => _readCustomerDetails().containsKey(id);

  /// Cached TRN / address from a prior contact-detail fetch, if any.
  ({String trn, String address})? getCustomerDetail(String id) {
    final entry = _readCustomerDetails()[id];
    if (entry == null) return null;
    return (trn: entry['trn'] ?? '', address: entry['address'] ?? '');
  }

  /// Persists a contact-detail result, including empty TRN.
  Future<void> saveCustomerDetail(
    String id, {
    required String trn,
    required String address,
  }) async {
    final all = _readCustomerDetails();
    all[id] = {'trn': trn, 'address': address};
    await _masterBox.put(_customerDetailsKey, jsonEncode(all));
  }

  Customer _applyCachedCustomerDetail(Customer customer) {
    final cached = getCustomerDetail(customer.id);
    if (cached == null) return customer;
    return customer.copyWith(
      trn: customer.trn.trim().isNotEmpty ? customer.trn : cached.trn,
      address:
          customer.address.trim().isNotEmpty ? customer.address : cached.address,
    );
  }

  /// Replaces a single customer by id. No-op when [customer.id] is not in Hive.
  Future<void> upsertCustomer(Customer customer) async {
    if (customer.id.isEmpty) return;
    final current = getCustomers();
    final index = current.indexWhere((c) => c.id == customer.id);
    if (index < 0) return;
    final newList = List<Customer>.from(current);
    newList[index] = customer;
    await saveCustomers(newList);
  }

  /// Updates latitude/longitude for a specific customer (by id) and persists.
  /// If the customer is not found, this is a no-op.
  Future<void> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {
    final current = getCustomers();
    final index = current.indexWhere((c) => c.id == customerId);
    if (index < 0) return;

    final updated = current[index].copyWith(
      latitude: latitude,
      longitude: longitude,
    );
    final newList = List<Customer>.from(current);
    newList[index] = updated;
    await saveCustomers(newList);
  }

  /// Updates phone and/or TRN for a specific customer and persists.
  /// If the customer is not found, this is a no-op.
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) async {
    final current = getCustomers();
    final index = current.indexWhere((c) => c.id == customerId);
    if (index < 0) return;

    final existing = current[index];
    final updated = existing.copyWith(
      phone: phone ?? existing.phone,
      trn: trn ?? existing.trn,
    );
    final newList = List<Customer>.from(current);
    newList[index] = updated;
    await saveCustomers(newList);

    if (trn != null) {
      final cached = getCustomerDetail(customerId);
      await saveCustomerDetail(
        customerId,
        trn: trn,
        address: cached?.address ?? updated.address,
      );
    }
  }

  /// Retrieves the list of synced master stocked inventory products.
  ///
  /// Uses `.map<Item>` so the list is a true [List]<[Item]> at runtime.
  /// Without the type arg, Dart builds a `List<ItemModel>`; later
  /// `list[i] = item.copyWith(...)` (e.g. stock deduct on invoice save)
  /// throws: type 'Item' is not a subtype of type 'ItemModel' of 'value'.
  List<Item> getItems() {
    final rawList = _masterBox.get('items', defaultValue: []);
    return (rawList as List)
        .map<Item>(
          (item) =>
              ItemModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))),
        )
        .toList();
  }

  /// Saves or refreshes inventory items list.
  Future<void> saveItems(List<Item> items) async {
    final serialized = items
        .map((i) => jsonEncode(ItemModel.fromDomain(i).toJson()))
        .toList();
    await _masterBox.put('items', serialized);
  }

  /// Reads the cached multi-UOM conversions for a single item.
  ///
  /// Multi-UOM data is stored per-item in `item_uom_box` (keyed by item id),
  /// decoupled from the `items` master list so a re-sync never wipes it.
  /// Returns an empty list when the item has never been resolved.
  List<UnitConversion> getItemUnitConversions(String itemId) {
    final raw = _itemUomBox.get(itemId);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw as String) as List;
    return decoded
        .map<UnitConversion>(
          (c) => UnitConversionModel.fromJson(Map<String, dynamic>.from(c)),
        )
        .toList();
  }

  /// Whether an item's conversions have already been fetched from Zoho.
  ///
  /// A present-but-empty entry means "checked, none exist" — this lets the
  /// resolver skip re-fetching items that genuinely have no conversions.
  bool hasItemUnitConversions(String itemId) => _itemUomBox.containsKey(itemId);

  /// Caches the resolved multi-UOM conversions for a single item.
  ///
  /// Persist even when [conversions] is empty so a later selection does not
  /// re-hit `GET /items/{id}` for an item that has no alternate units.
  Future<void> saveItemUnitConversions(
    String itemId,
    List<UnitConversion> conversions,
  ) async {
    final serialized = jsonEncode(
      conversions.map((c) => UnitConversionModel.fromDomain(c).toJson()).toList(),
    );
    await _itemUomBox.put(itemId, serialized);
  }

  /// Drops every cached multi-UOM entry.
  ///
  /// Called when the items master is re-downloaded so the next selection
  /// re-fetches conversions from Zoho (units may have changed).
  Future<void> clearItemUnitConversions() async {
    await _itemUomBox.clear();
  }

  /// Retrieves the list of synced master routes.
  List<RouteModel> getRoutes() {
    final rawList = _masterBox.get('routes', defaultValue: []);
    return (rawList as List).map((item) {
      final decoded = Map<String, dynamic>.from(jsonDecode(item));
      return RouteModel(
        id: decoded['id'] ?? '',
        name: decoded['name'] ?? '',
        description: decoded['description'] ?? '',
      );
    }).toList();
  }

  /// Saves master delivery routes list.
  Future<void> saveRoutes(List<RouteModel> routes) async {
    final serialized = routes
        .map(
          (r) => jsonEncode({
            'id': r.id,
            'name': r.name,
            'description': r.description,
          }),
        )
        .toList();
    await _masterBox.put('routes', serialized);
  }

  /// Retrieves list of synced warehouses.
  ///
  /// Uses `.map<Warehouse>` so the list is a true [List]<[Warehouse]> at
  /// runtime. Without the type arg, Dart builds a `List<WarehouseModel>`;
  /// `firstWhere(orElse: () => Warehouse(...))` then throws
  /// `type 'Warehouse' is not a subtype of type 'WarehouseModel'`.
  List<Warehouse> getWarehouses() {
    final rawList = _masterBox.get('warehouses', defaultValue: []);
    return (rawList as List)
        .map<Warehouse>(
          (w) =>
              WarehouseModel.fromJson(Map<String, dynamic>.from(jsonDecode(w))),
        )
        .toList();
  }

  /// Saves master warehouses list and refreshes [primaryWarehouseId].
  ///
  /// Locations master sync and login bind both write through here. Picks the
  /// first `isPrimary` location, else the first location, else clears the key.
  Future<void> saveWarehouses(List<Warehouse> warehouses) async {
    final serialized = warehouses
        .map((w) => jsonEncode(WarehouseModel.fromDomain(w).toJson()))
        .toList();
    await _masterBox.put('warehouses', serialized);

    Warehouse? primary;
    for (final w in warehouses) {
      if (w.isPrimary) {
        primary = w;
        break;
      }
    }
    primary ??= warehouses.isNotEmpty ? warehouses.first : null;
    await setPrimaryWarehouseId(primary?.id);
  }

  /// Retrieves the master list of all synced Zoho Books salespersons (sales users).
  List<Salesperson> getSalespersons() {
    final rawList = _masterBox.get('salespersons', defaultValue: []);
    return (rawList as List)
        .map(
          (s) => SalespersonModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(s)),
          ),
        )
        .toList();
  }

  /// Saves or refreshes the master salespersons list.
  Future<void> saveSalespersons(List<Salesperson> salespersons) async {
    final serialized = salespersons
        .map((s) => jsonEncode(SalespersonModel.fromDomain(s).toJson()))
        .toList();
    await _masterBox.put('salespersons', serialized);
  }

  /// Retrieves the resolved salesperson record for the currently logged-in session, if any.
  Salesperson? getCurrentSalesperson() {
    final raw = _masterBox.get('current_salesperson');
    if (raw == null) return null;
    return SalespersonModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw)),
    );
  }

  /// Caches the resolved active salesperson for the current session.
  Future<void> saveCurrentSalesperson(Salesperson salesperson) async {
    await _masterBox.put(
      'current_salesperson',
      jsonEncode(SalespersonModel.fromDomain(salesperson).toJson()),
    );
  }

  /// Removes the session's active salesperson (e.g. on logout).
  ///
  /// Also clears van assignment, voucher prefix, session phone, cash account,
  /// orders-only flag, and per-type numbering counters so nothing leaks into
  /// the next salesperson's session. Primary warehouse is kept so Issue-to-Van
  /// still knows HQ after the next login bootstrap.
  Future<void> clearCurrentSalesperson() async {
    await _masterBox.delete('current_salesperson');
    await _masterBox.delete('assigned_warehouse_id');
    await _masterBox.delete('voucher_prefix');
    await _masterBox.delete('session_phone');
    await _masterBox.delete('cash_account_id');
    await _masterBox.delete('orders_only_mode');
    for (final tag in const ['INV', 'SO', 'RCT', 'CN']) {
      await _masterBox.delete('doc_counter_$tag');
    }
  }

  /// Retrieves payment/bank ledgers for receipt mapping.
  List<PaymentAccount> getPaymentAccounts() {
    final rawList = _masterBox.get('payment_accounts', defaultValue: []);
    return (rawList as List)
        .map(
          (a) => PaymentAccountModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(a)),
          ),
        )
        .toList();
  }

  /// Saves synced deposit payment accounts/ledgers.
  Future<void> savePaymentAccounts(List<PaymentAccount> accounts) async {
    final serialized = accounts
        .map((a) => jsonEncode(PaymentAccountModel.fromDomain(a).toJson()))
        .toList();
    await _masterBox.put('payment_accounts', serialized);
  }

  /// Retrieves the list of synced VAT/Tax configurations.
  List<Tax> getTaxes() {
    final rawList = _masterBox.get('taxes', defaultValue: []);
    return (rawList as List)
        .map((t) => TaxModel.fromJson(Map<String, dynamic>.from(jsonDecode(t))))
        .toList();
  }

  /// Saves synced tax brackets.
  Future<void> saveTaxes(List<Tax> taxes) async {
    final serialized = taxes
        .map((t) => jsonEncode(TaxModel.fromDomain(t).toJson()))
        .toList();
    await _masterBox.put('taxes', serialized);
  }

  /// Retrieves list of synced expense account ledgers.
  List<ExpenseAccount> getExpenseAccounts() {
    final rawList = _masterBox.get('expense_accounts', defaultValue: []);
    return (rawList as List)
        .map(
          (a) => ExpenseAccountModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(a)),
          ),
        )
        .toList();
  }

  /// Saves synced expense ledgers.
  Future<void> saveExpenseAccounts(List<ExpenseAccount> accounts) async {
    final serialized = accounts
        .map((a) => jsonEncode(ExpenseAccountModel.fromDomain(a).toJson()))
        .toList();
    await _masterBox.put('expense_accounts', serialized);
  }

  /// Retrieves active Organization configurations.
  Organization? getOrganization() {
    final raw = _masterBox.get('organization');
    if (raw == null) return null;
    return OrganizationModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw)),
    );
  }

  /// Caches active Organization configurations.
  Future<void> saveOrganization(Organization org) async {
    await _masterBox.put(
      'organization',
      jsonEncode(OrganizationModel.fromDomain(org).toJson()),
    );
  }

  /// Number of JSON-encoded records stored under [key] in the master box.
  ///
  /// Reads the raw list only — does not deserialize models. Returns 0 when
  /// the key is missing or is not a list (e.g. the single organization object).
  int countMasterList(String key) {
    final raw = _masterBox.get(key, defaultValue: const []);
    return raw is List ? raw.length : 0;
  }

  /// Whether [key] has any persisted value in the master box.
  bool hasMasterValue(String key) => _masterBox.containsKey(key);

  /// Retrieves synced outstanding customer invoices snapshot.
  ///
  /// Optionally filters outstanding invoices down to a specific [customerId].
  List<OpenInvoice> getOpenInvoices({String? customerId}) {
    final rawList = _masterBox.get('open_invoices', defaultValue: []);
    final all = (rawList as List)
        .map(
          (i) => OpenInvoiceModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(i)),
          ),
        )
        .toList();
    if (customerId == null) return all;
    return all.where((inv) => inv.customerId == customerId).toList();
  }

  /// Overwrites current cached unpaid invoices snapshot.
  Future<void> saveOpenInvoices(List<OpenInvoice> invoices) async {
    final serialized = invoices
        .map((i) => jsonEncode(OpenInvoiceModel.fromDomain(i).toJson()))
        .toList();
    await _masterBox.put('open_invoices', serialized);
  }

  /// Retrieves a list of all sequential tasks awaiting synchronization.
  List<SyncQueueItem> getSyncQueue() {
    final keys = _syncQueueBox.keys.toList();
    return keys.map((key) {
      final raw = _syncQueueBox.get(key);
      return SyncQueueItem.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    }).toList();
  }

  /// Enqueues a new background task to the synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    await _syncQueueBox.put(item.id, jsonEncode(item.toJson()));
  }

  /// Re-saves a task to update its execution status or failure logs.
  Future<void> updateSyncItem(SyncQueueItem item) async {
    await _syncQueueBox.put(item.id, jsonEncode(item.toJson()));
  }

  /// Deletes a task from the queue once it has successfully synchronised.
  Future<void> dequeueSyncItem(String id) async {
    await _syncQueueBox.delete(id);
  }

  /// Permanently removes every queue task currently marked [SyncStatus.failed].
  ///
  /// Pending and syncing items are left untouched so unsynced work is never
  /// silently discarded — only tasks that have already exhausted a sync
  /// attempt and failed are cleared.
  Future<void> clearFailedSyncItems() async {
    for (final item in getSyncQueue()) {
      if (item.status == SyncStatus.failed) {
        await _syncQueueBox.delete(item.id);
      }
    }
  }

  /// Filters a list of location-taggable records down to the active session location.
  ///
  /// Records with no `locationId` (legacy, pre-dating this field) always pass through.
  /// When no location is active for the session, no filtering is applied.
  List<T> _filterByActiveLocation<T>(
    List<T> items,
    String? Function(T) locationIdOf,
  ) {
    final active = assignedWarehouseId;
    // List<T>.of, not `items` — the caller may hand us a list that reified as
    // List<XModel>, and passing it straight through leaks that runtime type to
    // the UI where `firstWhere(orElse: () => X(...))` then fails to type-check.
    if (active == null) return List<T>.of(items);
    return items
        .where((i) => locationIdOf(i) == null || locationIdOf(i) == active)
        .toList();
  }

  /// Retrieves the full, unfiltered list of invoices recorded locally (for internal read-modify-write use).
  List<SalesInvoice> _getAllLocalInvoices() {
    final rawList = _localHistoryBox.get('invoices', defaultValue: []);
    // Explicit type argument: without it the list reifies as
    // List<SalesInvoiceModel> and breaks firstWhere(orElse: () => SalesInvoice(…)).
    return (rawList as List)
        .map<SalesInvoice>(
          (item) => SalesInvoiceModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves list of invoices recorded locally, scoped to the active session location.
  List<SalesInvoice> getLocalInvoices() =>
      _filterByActiveLocation(_getAllLocalInvoices(), (inv) => inv.locationId);

  /// Every locally-cached invoice regardless of session location.
  ///
  /// Used for post-sync bookkeeping (Zoho id / pending flag / doc number)
  /// so a write never silently no-ops when the record's location does not
  /// match the current van session.
  List<SalesInvoice> getAllLocalInvoicesUnfiltered() => _getAllLocalInvoices();

  /// Caches a newly created sales invoice locally and immediately updates corresponding item stock level in the van.
  ///
  /// Validates stock *before* persisting anything: if any line would drive an
  /// item's stock below zero, this throws [InsufficientStockException] and
  /// neither the invoice nor the stock levels are written — the invoice can
  /// never be committed while silently leaving stock inconsistent.
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {
    final stamped = invoice.locationId == null && assignedWarehouseId != null
        ? invoice.copyWith(locationId: assignedWarehouseId)
        : invoice;
    final current = _getAllLocalInvoices();
    final model = SalesInvoiceModel.fromDomain(stamped);

    final index = current.indexWhere((inv) => inv.id == stamped.id);
    final oldInvoice = index >= 0 ? current[index] : null;

    // Compute (and validate) the resulting item stock levels before writing
    // anything: restore the old invoice's quantities (if this is an edit),
    // then deduct the new invoice's quantities, enforcing the single
    // stock invariant via deductStock().
    final localItems = getItems();
    if (oldInvoice != null) {
      for (final line in oldInvoice.items) {
        final itemIndex = localItems.indexWhere((it) => it.id == line.item.id);
        if (itemIndex >= 0) {
          final existingItem = localItems[itemIndex];
          localItems[itemIndex] = existingItem.copyWith(
            stock: existingItem.stock + line.quantityInBase,
          );
        }
      }
    }
    for (final line in stamped.items) {
      final itemIndex = localItems.indexWhere((it) => it.id == line.item.id);
      if (itemIndex >= 0) {
        final existingItem = localItems[itemIndex];
        final updatedStock = deductStock(
          itemId: existingItem.id,
          itemName: existingItem.name,
          available: existingItem.stock,
          requested: line.quantityInBase,
        );
        localItems[itemIndex] = existingItem.copyWith(stock: updatedStock);
      }
    }

    // Stock validation passed — now persist the invoice and the updated stock.
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }
    final serialized = current
        .map((inv) => jsonEncode(SalesInvoiceModel.fromDomain(inv).toJson()))
        .toList();
    await _localHistoryBox.put('invoices', serialized);
    await saveItems(localItems);
  }

  /// Upserts [invoice] into the local invoice cache without touching item
  /// stock — for post-sync bookkeeping only (Zoho id / pending flag / number).
  /// Creating or editing an invoice must go through [saveLocalInvoice].
  Future<void> updateInvoiceRecord(SalesInvoice invoice) async {
    final current = _getAllLocalInvoices();
    final index = current.indexWhere((i) => i.id == invoice.id);
    if (index < 0) return;
    current[index] = SalesInvoiceModel.fromDomain(invoice);

    final serialized = current
        .map((inv) => jsonEncode(SalesInvoiceModel.fromDomain(inv).toJson()))
        .toList();
    await _localHistoryBox.put('invoices', serialized);
  }

  /// Merges a freshly downloaded set of remote invoices into the local cache.
  ///
  /// Upsert, not replace: a local invoice survives unless remote carries the
  /// same `id` **or** confirms a previously-pending local row via
  /// [SalesInvoice.zohoInvoiceId] (the sales-order `zohoOrderId` pattern).
  ///
  /// Header-only remote rows (`items` empty) preserve any existing local line
  /// items so list refreshes do not wipe a previously cached full detail.
  Future<void> saveRemoteInvoices(List<SalesInvoice> remote) async {
    final current = _getAllLocalInvoices();
    final queuedInvoiceIds = getSyncQueue()
        .where((q) => q.type == 'invoice' && q.status != SyncStatus.completed)
        .map((q) => q.id)
        .toSet();

    final merged = mergeRemoteInvoices(
      current: current,
      remote: remote,
      queuedInvoiceIds: queuedInvoiceIds,
    );
    final serialized = merged
        .map((inv) => jsonEncode(SalesInvoiceModel.fromDomain(inv).toJson()))
        .toList();
    await _localHistoryBox.put('invoices', serialized);
  }

  /// Pure merge step behind [saveRemoteInvoices] — same contract as
  /// [mergeRemoteOrders], matching pending locals by `zohoInvoiceId`.
  @visibleForTesting
  static List<SalesInvoice> mergeRemoteInvoices({
    required List<SalesInvoice> current,
    required List<SalesInvoice> remote,
    required Set<String> queuedInvoiceIds,
  }) {
    SalesInvoice? localFor(SalesInvoice remoteInv) {
      for (final local in current) {
        if (local.id == remoteInv.id) return local;
        final zohoId = local.zohoInvoiceId;
        if (zohoId != null &&
            zohoId.isNotEmpty &&
            (zohoId == remoteInv.id || zohoId == remoteInv.zohoInvoiceId)) {
          return local;
        }
      }
      return null;
    }

    final mergedRemote = <SalesInvoice>[];
    for (final remoteInv in remote) {
      final local = localFor(remoteInv);
      if (local != null &&
          local.isPendingSync &&
          queuedInvoiceIds.contains(local.id)) {
        continue;
      }
      if (remoteInv.items.isEmpty &&
          local != null &&
          local.items.isNotEmpty) {
        mergedRemote.add(
          remoteInv.copyWith(
            items: local.items,
            locationId: local.locationId ?? remoteInv.locationId,
            notes: remoteInv.notes.isNotEmpty ? remoteInv.notes : local.notes,
            zohoInvoiceId: remoteInv.zohoInvoiceId ?? local.zohoInvoiceId,
            isPendingSync: false,
          ),
        );
      } else if (local != null &&
          local.locationId != null &&
          remoteInv.locationId == null) {
        mergedRemote.add(
          remoteInv.copyWith(
            locationId: local.locationId,
            zohoInvoiceId: remoteInv.zohoInvoiceId ?? local.zohoInvoiceId,
            isPendingSync: false,
          ),
        );
      } else {
        mergedRemote.add(
          remoteInv.isPendingSync
              ? remoteInv.copyWith(
                  isPendingSync: false,
                  zohoInvoiceId:
                      remoteInv.zohoInvoiceId ?? local?.zohoInvoiceId,
                )
              : remoteInv.copyWith(
                  zohoInvoiceId:
                      remoteInv.zohoInvoiceId ?? local?.zohoInvoiceId,
                ),
        );
      }
    }

    final remoteIds = remote.map((i) => i.id).toSet();
    final keptLocal = current.where((i) {
      if (i.isPendingSync) {
        if (queuedInvoiceIds.contains(i.id)) return true;
        return i.zohoInvoiceId == null || !remoteIds.contains(i.zohoInvoiceId);
      }
      if (remoteIds.contains(i.id)) return false;
      if (i.zohoInvoiceId != null && remoteIds.contains(i.zohoInvoiceId)) {
        return false;
      }
      return true;
    }).toList();

    return [...keptLocal, ...mergedRemote];
  }

  /// Retrieves the full, unfiltered list of sales orders recorded locally (for internal read-modify-write use).
  List<SalesOrder> _getAllLocalOrders() {
    final rawList = _localHistoryBox.get('sales_orders', defaultValue: []);
    // Always reify as List<SalesOrder> of plain domain instances.
    // Returning List<SalesOrderModel> (map().toList() inference) breaks
    // firstWhere(orElse: () => SalesOrder(...)) at runtime.
    return [
      for (final item in rawList as List)
        SalesOrderModel.fromJson(
          Map<String, dynamic>.from(jsonDecode(item)),
        ).copyWith(),
    ];
  }

  /// Retrieves list of sales orders recorded locally, scoped to the active session location.
  List<SalesOrder> getLocalOrders() =>
      _filterByActiveLocation(_getAllLocalOrders(), (ord) => ord.locationId);

  /// Retrieves every locally-cached sales order regardless of the active
  /// session's location. For internal post-sync bookkeeping (patching a
  /// record's Zoho id / doc number / pending flag right after a push
  /// succeeds) — that write must never silently no-op just because the
  /// record's location happens not to match the current session.
  List<SalesOrder> getAllLocalOrdersUnfiltered() => _getAllLocalOrders();

  /// Caches a newly created sales order locally.
  ///
  /// Note: Unlike Sales Invoices, creating a Sales Order does not directly deduct physical inventory stock levels immediately.
  Future<void> saveLocalOrder(SalesOrder order) => _withOrdersLock(() async {
    final stamped = order.locationId == null && assignedWarehouseId != null
        ? order.copyWith(locationId: assignedWarehouseId)
        : order;
    final current = _getAllLocalOrders();
    final model = SalesOrderModel.fromDomain(stamped);

    // Add or update
    final index = current.indexWhere((ord) => ord.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((ord) => jsonEncode(SalesOrderModel.fromDomain(ord).toJson()))
        .toList();
    await _localHistoryBox.put('sales_orders', serialized);
  });

  /// Merges a freshly downloaded set of remote sales orders into the local cache.
  ///
  /// Upsert, not replace: a fetch may be date-scoped (e.g. today only), so any
  /// local order outside that range must survive untouched. A local order is
  /// dropped when:
  /// - remote carries a fresher copy of the same id (replaced by the remote row), or
  /// - [pruneMissingInRange] is true and the order's date falls inside the
  ///   authoritative window ([rangeStart] / [rangeEnd]) but remote no longer
  ///   lists it (deleted on Zoho), or
  /// - a still-pending local row is no longer queued and remote already
  ///   confirms it (matched by `zohoOrderId`).
  ///
  /// Pass [pruneMissingInRange] only from list refreshes. Single-order detail
  /// fetches must leave it false so one upsert does not wipe the cache.
  Future<void> saveRemoteOrders(
    List<SalesOrder> remote, {
    bool pruneMissingInRange = false,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) =>
      _withOrdersLock(() async {
        final current = _getAllLocalOrders();
        final queuedOrderIds = getSyncQueue()
            .where(
              (q) =>
                  (q.type == 'sales_order' || q.type == 'update_sales_order') &&
                  q.status != SyncStatus.completed,
            )
            .map((q) => q.id)
            .toSet();

        final merged = mergeRemoteOrders(
          current: current,
          remote: remote,
          queuedOrderIds: queuedOrderIds,
          pruneMissingInRange: pruneMissingInRange,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        );
        final serialized = merged
            .map((ord) => jsonEncode(SalesOrderModel.fromDomain(ord).toJson()))
            .toList();
        await _localHistoryBox.put('sales_orders', serialized);
      });

  /// Pure merge step behind [saveRemoteOrders] — factored out so the race
  /// scenario (a locally-pending edit vs. a stale/concurrent remote fetch)
  /// can be unit tested without a real Hive box.
  ///
  /// Upsert, not replace: a fetch may be date-scoped (e.g. today only), so any
  /// local order outside that range must survive untouched. When
  /// [pruneMissingInRange] is true, a synced local order whose calendar date
  /// sits inside [rangeStart]..[rangeEnd] (inclusive; open bounds allowed) and
  /// is absent from [remote] is treated as deleted on Zoho and dropped.
  /// Both bounds null with prune enabled means the remote list is fully
  /// authoritative (unbounded list fetch).
  ///
  /// An id present in the fresh [remote] fetch does NOT by itself prove a
  /// pending local edit already landed — the fetch and the background sync
  /// push race independently, and an update never changes the order's id.
  /// Only drop a still-queued edit once its own sync-queue item — passed in
  /// as [queuedOrderIds] — is gone.
  @visibleForTesting
  static List<SalesOrder> mergeRemoteOrders({
    required List<SalesOrder> current,
    required List<SalesOrder> remote,
    required Set<String> queuedOrderIds,
    bool pruneMissingInRange = false,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) {
    final byId = {for (final o in current) o.id: o};

    // Header-only remote rows (empty items) keep any cached full line items.
    // Prefer **remote** locationId when set (session van stamp from
    // fetchRemoteOrders). Never re-apply a stale local HQ location_id that
    // came from Zoho's primary branch — that hid orders from every van list.
    final mergedRemote = <SalesOrder>[];
    for (final remoteOrd in remote) {
      final local = byId[remoteOrd.id];
      // Still-queued local edit wins: keep only the local row (see keptLocal).
      // Do not also append remote or the list ends up with two copies of the id.
      if (local != null &&
          local.isPendingSync &&
          queuedOrderIds.contains(local.id)) {
        continue;
      }
      if (remoteOrd.items.isEmpty &&
          local != null &&
          local.items.isNotEmpty) {
        mergedRemote.add(
          remoteOrd.copyWith(
            items: local.items,
            locationId: remoteOrd.locationId ?? local.locationId,
            notes: remoteOrd.notes.isNotEmpty ? remoteOrd.notes : local.notes,
            zohoOrderId: remoteOrd.zohoOrderId ?? local.zohoOrderId,
            isPendingSync: false,
          ),
        );
      } else {
        mergedRemote.add(
          remoteOrd.isPendingSync
              ? remoteOrd.copyWith(isPendingSync: false)
              : remoteOrd,
        );
      }
    }

    final remoteIds = remote.map((o) => o.id).toSet();
    final keptLocal = current.where((o) {
      if (o.isPendingSync) {
        if (queuedOrderIds.contains(o.id)) return true;
        return o.zohoOrderId == null || !remoteIds.contains(o.zohoOrderId);
      }
      // Already in remote → superseded by mergedRemote.
      if (remoteIds.contains(o.id)) return false;
      // List refresh: remote is authoritative for the fetched window — a
      // synced order in that window missing from remote was deleted in Zoho.
      if (pruneMissingInRange &&
          _orderDateInAuthoritativeRange(o.date, rangeStart, rangeEnd)) {
        return false;
      }
      return true;
    }).toList();

    return [...keptLocal, ...mergedRemote];
  }

  /// Calendar-date check for Zoho `date_start`/`date_end` windows (yyyy-MM-dd).
  /// Both bounds null ⇒ every date is in range (unbounded authoritative fetch).
  static bool _orderDateInAuthoritativeRange(
    DateTime date,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  ) {
    final d = DateTime(date.year, date.month, date.day);
    if (rangeStart != null) {
      final start = DateTime(
        rangeStart.year,
        rangeStart.month,
        rangeStart.day,
      );
      if (d.isBefore(start)) return false;
    }
    if (rangeEnd != null) {
      final end = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
      if (d.isAfter(end)) return false;
    }
    return true;
  }

  /// Retrieves the full, unfiltered list of stock transfers recorded locally (for internal read-modify-write use).
  List<StockTransfer> _getAllLocalStockTransfers() {
    final rawList = _localHistoryBox.get('stock_transfers', defaultValue: []);
    return (rawList as List)
        .map<StockTransfer>(
          (item) => StockTransferModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves list of stock transfers (Issue to Van / Stock Unloading) recorded
  /// locally, scoped to the active session location.
  ///
  /// Unlike [_filterByActiveLocation]'s other callers, a transfer's `locationId`
  /// (the app-local bookkeeping field, stamped only on local creation) is
  /// `null` for anything parsed from a Zoho response — Zoho never sends a
  /// `location_id` key for Transfer Orders. Falls back to matching the real
  /// `fromLocationId`/`toLocationId` fields in that case, so remote-fetched
  /// transfers are still scoped to this van instead of showing for everyone.
  List<StockTransfer> getLocalStockTransfers() {
    final active = assignedWarehouseId;
    final all = _getAllLocalStockTransfers();
    if (active == null) return List<StockTransfer>.of(all);
    return all.where((t) {
      if (t.locationId != null) return t.locationId == active;
      return t.fromLocationId == active || t.toLocationId == active;
    }).toList();
  }

  /// Retrieves every locally-cached stock transfer regardless of the active
  /// session's location. For internal post-sync bookkeeping (patching a
  /// record's Zoho id / pending flag right after a push succeeds) — that
  /// write must never silently no-op just because the record's location
  /// happens not to match the current session.
  List<StockTransfer> getAllLocalStockTransfersUnfiltered() =>
      _getAllLocalStockTransfers();

  /// Caches a newly created stock transfer locally and adjusts the van's local
  /// item stock levels: [StockTransferDirection.load] increases stock (Issue
  /// to Van), [StockTransferDirection.unload] decreases it (Stock Unloading).
  ///
  /// Validates stock *before* persisting anything: an unload that would drive
  /// an item's stock below zero throws [InsufficientStockException] and
  /// neither the transfer record nor the stock levels are written — mirrors
  /// the invariant enforced by [saveLocalInvoice].
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {
    final stamped =
        transfer.locationId == null && assignedWarehouseId != null
        ? transfer.copyWith(locationId: assignedWarehouseId)
        : transfer;

    // Compute (and validate) the resulting item stock levels before writing anything.
    final localItems = getItems();
    for (final line in stamped.lines) {
      final itemIndex = localItems.indexWhere((it) => it.id == line.item.id);
      if (itemIndex < 0) continue;
      final existingItem = localItems[itemIndex];
      final updatedStock = stamped.direction == StockTransferDirection.load
          // New stock = current stock (as shown to the user when they
          // planned this transfer) + qty transferred. `line.item.stock` is
          // that baseline — the grid stamps StockTransferRow.item (and thus
          // this line's item) from the same fetch that set currentStock, so
          // it must be used here instead of re-reading `existingItem.stock`,
          // which reflects whatever the cache holds *now* and can have
          // drifted from what the user actually saw.
          ? line.item.stock + line.quantity
          : deductStock(
              itemId: existingItem.id,
              itemName: existingItem.name,
              available: existingItem.stock,
              requested: line.quantity,
            );
      localItems[itemIndex] = existingItem.copyWith(stock: updatedStock);
    }

    // Stock validation passed — now persist the transfer record and the updated stock.
    final current = _getAllLocalStockTransfers();
    final model = StockTransferModel.fromDomain(stamped);

    final index = current.indexWhere((t) => t.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((t) => jsonEncode(StockTransferModel.fromDomain(t).toJson()))
        .toList();
    await _localHistoryBox.put('stock_transfers', serialized);
    await saveItems(localItems);
  }

  /// Upserts [transfer] into the local stock-transfer cache without touching
  /// item stock levels — for post-sync bookkeeping only (patching the Zoho
  /// id / pending flag once a push succeeds). Creating a transfer must go
  /// through [saveLocalStockTransfer] instead, which applies the stock
  /// adjustment; calling it again here would double-apply it.
  Future<void> updateStockTransferRecord(StockTransfer transfer) async {
    final current = _getAllLocalStockTransfers();
    final index = current.indexWhere((t) => t.id == transfer.id);
    if (index < 0) return;
    current[index] = StockTransferModel.fromDomain(transfer);

    final serialized = current
        .map((t) => jsonEncode(StockTransferModel.fromDomain(t).toJson()))
        .toList();
    await _localHistoryBox.put('stock_transfers', serialized);
  }

  /// Merges a freshly downloaded set of remote stock transfers into the local
  /// cache. Same shape as [saveRemoteOrders]: a still-pending local transfer
  /// is kept unless remote already confirms it via `zohoTransferId`; a synced
  /// local transfer is kept unless remote carries a fresher copy by `id`.
  Future<void> saveRemoteStockTransfers(List<StockTransfer> remote) async {
    final current = _getAllLocalStockTransfers();
    final remoteIds = remote.map((t) => t.id).toSet();
    final keptLocal = current.where((t) {
      if (t.isPendingSync) {
        return t.zohoTransferId == null ||
            !remoteIds.contains(t.zohoTransferId);
      }
      return !remoteIds.contains(t.id);
    }).toList();

    final merged = [...keptLocal, ...remote];
    final serialized = merged
        .map((t) => jsonEncode(StockTransferModel.fromDomain(t).toJson()))
        .toList();
    await _localHistoryBox.put('stock_transfers', serialized);
  }

  /// Retrieves the full, unfiltered list of receipts recorded locally (for internal read-modify-write use).
  List<ReceiptVoucher> _getAllLocalReceipts() {
    final rawList = _localHistoryBox.get('receipts', defaultValue: []);
    return (rawList as List)
        .map<ReceiptVoucher>(
          (item) => ReceiptVoucherModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves all collection receipts recorded locally, scoped to the active session location.
  List<ReceiptVoucher> getLocalReceipts() =>
      _filterByActiveLocation(_getAllLocalReceipts(), (rec) => rec.locationId);

  /// Every locally-cached receipt regardless of session location.
  List<ReceiptVoucher> getAllLocalReceiptsUnfiltered() =>
      _getAllLocalReceipts();

  /// Caches a newly created receipt locally and instantly decrements the matching customer's outstanding balance in memory.
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {
    var stamped = voucher.locationId == null && assignedWarehouseId != null
        ? voucher.copyWith(locationId: assignedWarehouseId)
        : voucher;
    final salespersonId = getCurrentSalesperson()?.id;
    if (stamped.salespersonId == null &&
        salespersonId != null &&
        salespersonId.isNotEmpty) {
      stamped = stamped.copyWith(salespersonId: salespersonId);
    }
    final current = _getAllLocalReceipts();
    final model = ReceiptVoucherModel.fromDomain(stamped);

    final index = current.indexWhere((rec) => rec.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((rec) => jsonEncode(ReceiptVoucherModel.fromDomain(rec).toJson()))
        .toList();
    await _localHistoryBox.put('receipts', serialized);

    // Adjust local Customer outstanding balance instantly!
    final localCustomers = getCustomers();
    final customerIndex = localCustomers.indexWhere(
      (cust) => cust.id == voucher.customerId,
    );
    if (customerIndex >= 0) {
      final existingCust = localCustomers[customerIndex];
      final updatedBalance = existingCust.outstandingBalance - voucher.amount;
      localCustomers[customerIndex] = existingCust.copyWith(
        outstandingBalance: updatedBalance >= 0 ? updatedBalance : 0.0,
      );
    }
    await saveCustomers(localCustomers);
  }

  /// Upserts [voucher] without adjusting customer outstanding — post-sync
  /// bookkeeping only. Creating a receipt must go through [saveLocalReceipt].
  Future<void> updateReceiptRecord(ReceiptVoucher voucher) async {
    final current = _getAllLocalReceipts();
    final index = current.indexWhere((r) => r.id == voucher.id);
    if (index < 0) return;
    current[index] = ReceiptVoucherModel.fromDomain(voucher);

    final serialized = current
        .map((rec) => jsonEncode(ReceiptVoucherModel.fromDomain(rec).toJson()))
        .toList();
    await _localHistoryBox.put('receipts', serialized);
  }

  /// Merges a freshly downloaded set of remote receipts into the local cache.
  /// Upsert, not replace — matches pending locals by [ReceiptVoucher.zohoPaymentId].
  ///
  /// Header-only remote rows (empty allocations) preserve any existing local
  /// invoice allocations so list refreshes do not wipe a cached full detail.
  Future<void> saveRemoteReceipts(List<ReceiptVoucher> remote) async {
    final current = _getAllLocalReceipts();
    final queuedIds = getSyncQueue()
        .where((q) => q.type == 'receipt' && q.status != SyncStatus.completed)
        .map((q) => q.id)
        .toSet();

    ReceiptVoucher? localFor(ReceiptVoucher remoteRec) {
      for (final local in current) {
        if (local.id == remoteRec.id) return local;
        final zohoId = local.zohoPaymentId;
        if (zohoId != null &&
            zohoId.isNotEmpty &&
            (zohoId == remoteRec.id || zohoId == remoteRec.zohoPaymentId)) {
          return local;
        }
      }
      return null;
    }

    final mergedRemote = <ReceiptVoucher>[];
    for (final remoteRec in remote) {
      final local = localFor(remoteRec);
      if (local != null &&
          local.isPendingSync &&
          queuedIds.contains(local.id)) {
        continue;
      }
      if (remoteRec.allocations.isEmpty &&
          local != null &&
          local.allocations.isNotEmpty) {
        mergedRemote.add(
          remoteRec.copyWith(
            allocations: local.allocations,
            locationId: remoteRec.locationId ?? local.locationId,
            paymentNumber: remoteRec.paymentNumber.isNotEmpty
                ? remoteRec.paymentNumber
                : local.paymentNumber,
            referenceNumber: remoteRec.referenceNumber.isNotEmpty
                ? remoteRec.referenceNumber
                : local.referenceNumber,
            zohoPaymentId: remoteRec.zohoPaymentId ?? local.zohoPaymentId,
            isPendingSync: false,
          ),
        );
      } else {
        mergedRemote.add(
          remoteRec.copyWith(
            zohoPaymentId: remoteRec.zohoPaymentId ?? local?.zohoPaymentId,
            isPendingSync: false,
          ),
        );
      }
    }

    final remoteIds = remote.map((r) => r.id).toSet();
    final keptLocal = current.where((r) {
      if (r.isPendingSync) {
        if (queuedIds.contains(r.id)) return true;
        return r.zohoPaymentId == null || !remoteIds.contains(r.zohoPaymentId);
      }
      if (remoteIds.contains(r.id)) return false;
      if (r.zohoPaymentId != null && remoteIds.contains(r.zohoPaymentId)) {
        return false;
      }
      return true;
    }).toList();

    final merged = [...keptLocal, ...mergedRemote];
    final serialized = merged
        .map((rec) => jsonEncode(ReceiptVoucherModel.fromDomain(rec).toJson()))
        .toList();
    await _localHistoryBox.put('receipts', serialized);
  }

  /// Retrieves the full, unfiltered list of sales returns recorded locally (for internal read-modify-write use).
  List<SalesReturn> _getAllLocalReturns() {
    final rawList = _localHistoryBox.get('returns', defaultValue: []);
    return (rawList as List)
        .map<SalesReturn>(
          (item) => SalesReturnModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves list of sales returns recorded locally, scoped to the active session location.
  List<SalesReturn> getLocalReturns() =>
      _filterByActiveLocation(_getAllLocalReturns(), (ret) => ret.locationId);

  /// Every locally-cached sales return regardless of session location.
  List<SalesReturn> getAllLocalReturnsUnfiltered() => _getAllLocalReturns();

  /// Caches a sales return locally and immediately restores returned product stock levels back in the local inventory.
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {
    final stamped =
        salesReturn.locationId == null && assignedWarehouseId != null
        ? salesReturn.copyWith(locationId: assignedWarehouseId)
        : salesReturn;
    final current = _getAllLocalReturns();
    final model = SalesReturnModel.fromDomain(stamped);

    final index = current.indexWhere((ret) => ret.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((ret) => jsonEncode(SalesReturnModel.fromDomain(ret).toJson()))
        .toList();
    await _localHistoryBox.put('returns', serialized);

    // Restore stock in local cached inventory instantly!
    final localItems = getItems();
    for (final line in stamped.items) {
      final itemIndex = localItems.indexWhere(
        (it) => it.id == line.invoiceLineItem.item.id,
      );
      if (itemIndex >= 0) {
        final existingItem = localItems[itemIndex];
        localItems[itemIndex] = existingItem.copyWith(
          stock: existingItem.stock + line.returnedQuantity,
        );
      }
    }
    await saveItems(localItems);
  }

  /// Upserts [salesReturn] without restoring stock — post-sync bookkeeping only.
  Future<void> updateReturnRecord(SalesReturn salesReturn) async {
    final current = _getAllLocalReturns();
    final index = current.indexWhere((r) => r.id == salesReturn.id);
    if (index < 0) return;
    current[index] = SalesReturnModel.fromDomain(salesReturn);

    final serialized = current
        .map((ret) => jsonEncode(SalesReturnModel.fromDomain(ret).toJson()))
        .toList();
    await _localHistoryBox.put('returns', serialized);
  }

  /// Merges a freshly downloaded set of remote sales returns into the local cache.
  /// Upsert, not replace — matches pending locals by [SalesReturn.zohoCreditNoteId].
  ///
  /// Header-only remote rows (`items` empty) preserve any existing local line
  /// items so list refreshes do not wipe a previously cached full detail.
  Future<void> saveRemoteReturns(List<SalesReturn> remote) async {
    final current = _getAllLocalReturns();
    final queuedIds = getSyncQueue()
        .where((q) => q.type == 'return' && q.status != SyncStatus.completed)
        .map((q) => q.id)
        .toSet();

    SalesReturn? localFor(SalesReturn remoteRet) {
      for (final local in current) {
        if (local.id == remoteRet.id) return local;
        final zohoId = local.zohoCreditNoteId;
        if (zohoId != null &&
            zohoId.isNotEmpty &&
            (zohoId == remoteRet.id || zohoId == remoteRet.zohoCreditNoteId)) {
          return local;
        }
      }
      return null;
    }

    final mergedRemote = <SalesReturn>[];
    for (final remoteRet in remote) {
      final local = localFor(remoteRet);
      if (local != null &&
          local.isPendingSync &&
          queuedIds.contains(local.id)) {
        continue;
      }
      if (remoteRet.items.isEmpty &&
          local != null &&
          local.items.isNotEmpty) {
        mergedRemote.add(
          remoteRet.copyWith(
            items: local.items,
            locationId: remoteRet.locationId ?? local.locationId,
            reason: remoteRet.reason.isNotEmpty ? remoteRet.reason : local.reason,
            zohoCreditNoteId:
                remoteRet.zohoCreditNoteId ?? local.zohoCreditNoteId,
            isPendingSync: false,
          ),
        );
      } else {
        mergedRemote.add(
          remoteRet.copyWith(
            zohoCreditNoteId:
                remoteRet.zohoCreditNoteId ?? local?.zohoCreditNoteId,
            isPendingSync: false,
          ),
        );
      }
    }

    final remoteIds = remote.map((r) => r.id).toSet();
    final keptLocal = current.where((r) {
      if (r.isPendingSync) {
        if (queuedIds.contains(r.id)) return true;
        return r.zohoCreditNoteId == null ||
            !remoteIds.contains(r.zohoCreditNoteId);
      }
      if (remoteIds.contains(r.id)) return false;
      if (r.zohoCreditNoteId != null &&
          remoteIds.contains(r.zohoCreditNoteId)) {
        return false;
      }
      return true;
    }).toList();

    final merged = [...keptLocal, ...mergedRemote];
    final serialized = merged
        .map((ret) => jsonEncode(SalesReturnModel.fromDomain(ret).toJson()))
        .toList();
    await _localHistoryBox.put('returns', serialized);
  }

  /// Retrieves the full, unfiltered list of expenses recorded locally (for internal read-modify-write use).
  List<ExpenseEntry> _getAllLocalExpenses() {
    final rawList = _localHistoryBox.get('expenses', defaultValue: []);
    return (rawList as List)
        .map<ExpenseEntry>(
          (item) => ExpenseEntryModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves all Filed route expenses, scoped to the active session location.
  List<ExpenseEntry> getLocalExpenses() =>
      _filterByActiveLocation(_getAllLocalExpenses(), (exp) => exp.locationId);

  /// Every locally-cached expense regardless of session location.
  List<ExpenseEntry> getAllLocalExpensesUnfiltered() => _getAllLocalExpenses();

  /// Caches a new expense voucher locally.
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    final stamped = expense.locationId == null && assignedWarehouseId != null
        ? expense.copyWith(locationId: assignedWarehouseId)
        : expense;
    final current = _getAllLocalExpenses();
    final model = ExpenseEntryModel.fromDomain(stamped);

    final index = current.indexWhere((exp) => exp.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((exp) => jsonEncode(ExpenseEntryModel.fromDomain(exp).toJson()))
        .toList();
    await _localHistoryBox.put('expenses', serialized);
  }

  /// Upserts [expense] in place — post-sync bookkeeping (Zoho id / pending).
  Future<void> updateExpenseRecord(ExpenseEntry expense) async {
    final current = _getAllLocalExpenses();
    final index = current.indexWhere((e) => e.id == expense.id);
    if (index < 0) return;
    current[index] = ExpenseEntryModel.fromDomain(expense);

    final serialized = current
        .map((exp) => jsonEncode(ExpenseEntryModel.fromDomain(exp).toJson()))
        .toList();
    await _localHistoryBox.put('expenses', serialized);
  }

  /// Merges a freshly downloaded set of remote expenses into the local cache.
  /// Upsert, not replace — matches pending locals by [ExpenseEntry.zohoExpenseId].
  ///
  /// Header-only remote rows (`lines` empty) preserve any existing local line
  /// items so list refreshes do not wipe a previously cached full detail.
  Future<void> saveRemoteExpenses(List<ExpenseEntry> remote) async {
    final current = _getAllLocalExpenses();
    final queuedIds = getSyncQueue()
        .where((q) => q.type == 'expense' && q.status != SyncStatus.completed)
        .map((q) => q.id)
        .toSet();

    ExpenseEntry? localFor(ExpenseEntry remoteExp) {
      for (final local in current) {
        if (local.id == remoteExp.id) return local;
        final zohoId = local.zohoExpenseId;
        if (zohoId != null &&
            zohoId.isNotEmpty &&
            (zohoId == remoteExp.id || zohoId == remoteExp.zohoExpenseId)) {
          return local;
        }
      }
      return null;
    }

    final mergedRemote = <ExpenseEntry>[];
    for (final remoteExp in remote) {
      final local = localFor(remoteExp);
      if (local != null &&
          local.isPendingSync &&
          queuedIds.contains(local.id)) {
        continue;
      }
      if (remoteExp.lines.isEmpty &&
          local != null &&
          local.lines.isNotEmpty) {
        mergedRemote.add(
          remoteExp.copyWith(
            lines: local.lines,
            locationId: remoteExp.locationId ?? local.locationId,
            receiptImagePath:
                remoteExp.receiptImagePath ?? local.receiptImagePath,
            zohoExpenseId: remoteExp.zohoExpenseId ?? local.zohoExpenseId,
            isPendingSync: false,
          ),
        );
      } else {
        mergedRemote.add(
          remoteExp.copyWith(
            zohoExpenseId: remoteExp.zohoExpenseId ?? local?.zohoExpenseId,
            isPendingSync: false,
          ),
        );
      }
    }

    final remoteIds = remote.map((e) => e.id).toSet();
    final keptLocal = current.where((e) {
      if (e.isPendingSync) {
        if (queuedIds.contains(e.id)) return true;
        return e.zohoExpenseId == null || !remoteIds.contains(e.zohoExpenseId);
      }
      if (remoteIds.contains(e.id)) return false;
      if (e.zohoExpenseId != null && remoteIds.contains(e.zohoExpenseId)) {
        return false;
      }
      return true;
    }).toList();

    final merged = [...keptLocal, ...mergedRemote];
    final serialized = merged
        .map((exp) => jsonEncode(ExpenseEntryModel.fromDomain(exp).toJson()))
        .toList();
    await _localHistoryBox.put('expenses', serialized);
  }

  /// Retrieves the end-of-trip daily cash closing record, if filed.
  CashClosing? getLocalCashClosing() {
    final raw = _localHistoryBox.get('cash_closing');
    if (raw == null) return null;
    return CashClosingModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw)),
    );
  }

  /// Caches the daily cash closing reconciliation record.
  Future<void> saveLocalCashClosing(CashClosing closing) async {
    final model = CashClosingModel.fromDomain(closing);
    await _localHistoryBox.put('cash_closing', jsonEncode(model.toJson()));
  }

  /// True if there's recorded sales activity (invoices, receipts, or
  /// expenses) dated today, but no cash-closing reconciliation has been
  /// filed for today — i.e. the day-close workflow is still outstanding.
  ///
  /// Used to gate logout so a day's activity can't be walked away from
  /// without reconciling cash in hand against expected takings.
  bool hasPendingCashClosingForToday() {
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final hasActivityToday =
        getLocalInvoices().any((inv) => isToday(inv.date)) ||
        getLocalReceipts().any((rec) => isToday(rec.date)) ||
        getLocalExpenses().any((exp) => isToday(exp.date));
    if (!hasActivityToday) return false;

    final closing = getLocalCashClosing();
    return closing == null || !isToday(closing.date);
  }

  /// Gets the cached OAuth 2.0 Access Token for Zoho Books.
  String? get oauthAccessToken => _masterBox.get('oauth_access_token');

  /// Saves the cached OAuth 2.0 Access Token for Zoho Books.
  Future<void> setOauthAccessToken(String? token) async {
    await _masterBox.put('oauth_access_token', token);
  }

  /// Gets the token expiry timestamp in milliseconds.
  int? get oauthTokenExpiry => _masterBox.get('oauth_token_expiry');

  /// Saves the token expiry timestamp in milliseconds.
  Future<void> setOauthTokenExpiry(int? expiryMillis) async {
    await _masterBox.put('oauth_token_expiry', expiryMillis);
  }

  /// Active update channel for in-app OTA updates ('production' or 'beta').
  String get updateChannel =>
      _masterBox.get('update_channel', defaultValue: 'production');

  /// Sets the active update channel ('production' or 'beta').
  Future<void> setUpdateChannel(String channel) async {
    await _masterBox.put('update_channel', channel);
  }
}
