import 'dart:convert';
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
import '../../domain/models/payment_account.dart';
import '../../domain/models/tax.dart';
import '../../domain/models/expense_account.dart';
import '../../domain/models/organization.dart';
import '../../domain/models/open_invoice.dart';
import '../models/customer_model.dart';
import '../models/item_model.dart';
import '../models/sales_invoice_model.dart';
import '../models/receipt_voucher_model.dart';
import '../models/sales_return_model.dart';
import '../models/expense_entry_model.dart';
import '../models/cash_closing_model.dart';
import '../models/warehouse_model.dart';
import '../models/payment_account_model.dart';
import '../models/tax_model.dart';
import '../models/expense_account_model.dart';
import '../models/organization_model.dart';
import '../models/open_invoice_model.dart';
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

  late Box _masterBox;
  late Box _syncQueueBox;
  late Box _localHistoryBox;

  /// Initializes the local database bindings and opens Hive boxes.
  Future<void> init() async {
    await Hive.initFlutter();
    _masterBox = await Hive.openBox(_masterBoxName);
    _syncQueueBox = await Hive.openBox(_syncQueueBoxName);
    _localHistoryBox = await Hive.openBox(_localHistoryBoxName);
  }

  /// Clears all local caches, queues, and transaction histories.
  Future<void> clearAll() async {
    await _masterBox.clear();
    await _syncQueueBox.clear();
    await _localHistoryBox.clear();
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

  /// Retrieves the list of synced master customer records.
  List<Customer> getCustomers() {
    final rawList = _masterBox.get('customers', defaultValue: []);
    return (rawList as List)
        .map((item) => CustomerModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  /// Saves or refreshes customer master lists.
  Future<void> saveCustomers(List<Customer> customers) async {
    final serialized = customers
        .map((c) => jsonEncode(CustomerModel.fromDomain(c).toJson()))
        .toList();
    await _masterBox.put('customers', serialized);
  }

  /// Retrieves the list of synced master stocked inventory products.
  List<Item> getItems() {
    final rawList = _masterBox.get('items', defaultValue: []);
    return (rawList as List)
        .map((item) => ItemModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  /// Saves or refreshes inventory items list.
  Future<void> saveItems(List<Item> items) async {
    final serialized = items
        .map((i) => jsonEncode(ItemModel.fromDomain(i).toJson()))
        .toList();
    await _masterBox.put('items', serialized);
  }

  /// Retrieves the list of synced master routes.
  List<RouteModel> getRoutes() {
    final rawList = _masterBox.get('routes', defaultValue: []);
    return (rawList as List)
        .map((item) {
          final decoded = Map<String, dynamic>.from(jsonDecode(item));
          return RouteModel(
            id: decoded['id'] ?? '',
            name: decoded['name'] ?? '',
            description: decoded['description'] ?? '',
          );
        })
        .toList();
  }

  /// Saves master delivery routes list.
  Future<void> saveRoutes(List<RouteModel> routes) async {
    final serialized = routes
        .map((r) => jsonEncode({'id': r.id, 'name': r.name, 'description': r.description}))
        .toList();
    await _masterBox.put('routes', serialized);
  }

  /// Retrieves list of synced warehouses.
  List<Warehouse> getWarehouses() {
    final rawList = _masterBox.get('warehouses', defaultValue: []);
    return (rawList as List)
        .map((w) => WarehouseModel.fromJson(Map<String, dynamic>.from(jsonDecode(w))))
        .toList();
  }

  /// Saves master warehouses list.
  Future<void> saveWarehouses(List<Warehouse> warehouses) async {
    final serialized = warehouses
        .map((w) => jsonEncode(WarehouseModel.fromDomain(w).toJson()))
        .toList();
    await _masterBox.put('warehouses', serialized);
  }

  /// Retrieves payment/bank ledgers for receipt mapping.
  List<PaymentAccount> getPaymentAccounts() {
    final rawList = _masterBox.get('payment_accounts', defaultValue: []);
    return (rawList as List)
        .map((a) => PaymentAccountModel.fromJson(Map<String, dynamic>.from(jsonDecode(a))))
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
        .map((a) => ExpenseAccountModel.fromJson(Map<String, dynamic>.from(jsonDecode(a))))
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
    return OrganizationModel.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  /// Caches active Organization configurations.
  Future<void> saveOrganization(Organization org) async {
    await _masterBox.put(
      'organization',
      jsonEncode(OrganizationModel.fromDomain(org).toJson()),
    );
  }

  /// Retrieves synced outstanding customer invoices snapshot.
  ///
  /// Optionally filters outstanding invoices down to a specific [customerId].
  List<OpenInvoice> getOpenInvoices({String? customerId}) {
    final rawList = _masterBox.get('open_invoices', defaultValue: []);
    final all = (rawList as List)
        .map((i) => OpenInvoiceModel.fromJson(Map<String, dynamic>.from(jsonDecode(i))))
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

  /// Retrieves list of invoices recorded locally.
  List<SalesInvoice> getLocalInvoices() {
    final rawList = _localHistoryBox.get('invoices', defaultValue: []);
    return (rawList as List)
        .map((item) => SalesInvoiceModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  /// Caches a newly created sales invoice locally and immediately updates corresponding item stock level in the van.
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {
    final current = getLocalInvoices();
    final model = SalesInvoiceModel.fromDomain(invoice);
    
    // Add or update
    final index = current.indexWhere((inv) => inv.id == invoice.id);
    SalesInvoice? oldInvoice;
    if (index >= 0) {
      oldInvoice = current[index];
      current[index] = model;
    } else {
      current.insert(0, model);
    }
    
    final serialized = current.map((inv) => jsonEncode(SalesInvoiceModel.fromDomain(inv).toJson())).toList();
    await _localHistoryBox.put('invoices', serialized);
    
    // Update local cached item inventory stock instantly!
    final localItems = getItems();
    if (oldInvoice != null) {
      for (final line in oldInvoice.items) {
        final itemIndex = localItems.indexWhere((it) => it.id == line.item.id);
        if (itemIndex >= 0) {
          final existingItem = localItems[itemIndex];
          localItems[itemIndex] = existingItem.copyWith(stock: existingItem.stock + line.quantity);
        }
      }
    }
    for (final line in invoice.items) {
      final itemIndex = localItems.indexWhere((it) => it.id == line.item.id);
      if (itemIndex >= 0) {
        final existingItem = localItems[itemIndex];
        final updatedStock = existingItem.stock - line.quantity;
        localItems[itemIndex] = existingItem.copyWith(stock: updatedStock >= 0 ? updatedStock : 0);
      }
    }
    await saveItems(localItems);
  }

  /// Retrieves all collection receipts recorded locally.
  List<ReceiptVoucher> getLocalReceipts() {
    final rawList = _localHistoryBox.get('receipts', defaultValue: []);
    return (rawList as List)
        .map((item) => ReceiptVoucherModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  /// Caches a newly created receipt locally and instantly decrements the matching customer's outstanding balance in memory.
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {
    final current = getLocalReceipts();
    final model = ReceiptVoucherModel.fromDomain(voucher);
    
    final index = current.indexWhere((rec) => rec.id == voucher.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }
    
    final serialized = current.map((rec) => jsonEncode(ReceiptVoucherModel.fromDomain(rec).toJson())).toList();
    await _localHistoryBox.put('receipts', serialized);
    
    // Adjust local Customer outstanding balance instantly!
    final localCustomers = getCustomers();
    final customerIndex = localCustomers.indexWhere((cust) => cust.id == voucher.customerId);
    if (customerIndex >= 0) {
      final existingCust = localCustomers[customerIndex];
      final updatedBalance = existingCust.outstandingBalance - voucher.amount;
      localCustomers[customerIndex] = existingCust.copyWith(
        outstandingBalance: updatedBalance >= 0 ? updatedBalance : 0.0,
      );
    }
    await saveCustomers(localCustomers);
  }

  /// Retrieves list of sales returns recorded locally.
  List<SalesReturn> getLocalReturns() {
    final rawList = _localHistoryBox.get('returns', defaultValue: []);
    return (rawList as List)
        .map((item) => SalesReturnModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  /// Caches a sales return locally and immediately restores returned product stock levels back in the local inventory.
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {
    final current = getLocalReturns();
    final model = SalesReturnModel.fromDomain(salesReturn);
    
    final index = current.indexWhere((ret) => ret.id == salesReturn.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }
    
    final serialized = current.map((ret) => jsonEncode(SalesReturnModel.fromDomain(ret).toJson())).toList();
    await _localHistoryBox.put('returns', serialized);
    
    // Restore stock in local cached inventory instantly!
    final localItems = getItems();
    for (final line in salesReturn.items) {
      final itemIndex = localItems.indexWhere((it) => it.id == line.invoiceLineItem.item.id);
      if (itemIndex >= 0) {
        final existingItem = localItems[itemIndex];
        localItems[itemIndex] = existingItem.copyWith(stock: existingItem.stock + line.returnedQuantity);
      }
    }
    await saveItems(localItems);
  }

  /// Retrieves all Filed route expenses.
  List<ExpenseEntry> getLocalExpenses() {
    final rawList = _localHistoryBox.get('expenses', defaultValue: []);
    return (rawList as List)
        .map((item) => ExpenseEntryModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  /// Caches a new expense voucher locally.
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    final current = getLocalExpenses();
    final model = ExpenseEntryModel.fromDomain(expense);
    
    final index = current.indexWhere((exp) => exp.id == expense.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }
    
    final serialized = current.map((exp) => jsonEncode(ExpenseEntryModel.fromDomain(exp).toJson())).toList();
    await _localHistoryBox.put('expenses', serialized);
  }

  /// Retrieves the end-of-trip daily cash closing record, if filed.
  CashClosing? getLocalCashClosing() {
    final raw = _localHistoryBox.get('cash_closing');
    if (raw == null) return null;
    return CashClosingModel.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  /// Caches the daily cash closing reconciliation record.
  Future<void> saveLocalCashClosing(CashClosing closing) async {
    final model = CashClosingModel.fromDomain(closing);
    await _localHistoryBox.put('cash_closing', jsonEncode(model.toJson()));
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
}
