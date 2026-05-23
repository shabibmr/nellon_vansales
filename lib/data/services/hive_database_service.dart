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
import '../models/customer_model.dart';
import '../models/item_model.dart';
import '../models/sales_invoice_model.dart';
import '../models/receipt_voucher_model.dart';
import '../models/sales_return_model.dart';
import '../models/expense_entry_model.dart';
import '../models/cash_closing_model.dart';
import '../models/sync_queue_item.dart';

class HiveDatabaseService {
  static const String _masterBoxName = 'master_data_box';
  static const String _syncQueueBoxName = 'sync_queue_box';
  static const String _localHistoryBoxName = 'local_history_box';

  late Box _masterBox;
  late Box _syncQueueBox;
  late Box _localHistoryBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _masterBox = await Hive.openBox(_masterBoxName);
    _syncQueueBox = await Hive.openBox(_syncQueueBoxName);
    _localHistoryBox = await Hive.openBox(_localHistoryBoxName);
  }

  // --- Clear Database ---
  Future<void> clearAll() async {
    await _masterBox.clear();
    await _syncQueueBox.clear();
    await _localHistoryBox.clear();
  }

  // --- Active Session Keys (Route, Van Warehouse, etc.) ---
  String? get activeRouteId => _masterBox.get('active_route_id');
  Future<void> setActiveRouteId(String? routeId) async {
    await _masterBox.put('active_route_id', routeId);
  }

  String? get assignedWarehouseId => _masterBox.get('assigned_warehouse_id');
  Future<void> setAssignedWarehouseId(String? warehouseId) async {
    await _masterBox.put('assigned_warehouse_id', warehouseId);
  }

  // --- Master: Customers ---
  List<Customer> getCustomers() {
    final rawList = _masterBox.get('customers', defaultValue: []);
    return (rawList as List)
        .map((item) => CustomerModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  Future<void> saveCustomers(List<Customer> customers) async {
    final serialized = customers
        .map((c) => jsonEncode(CustomerModel.fromDomain(c).toJson()))
        .toList();
    await _masterBox.put('customers', serialized);
  }

  // --- Master: Items (Inventory) ---
  List<Item> getItems() {
    final rawList = _masterBox.get('items', defaultValue: []);
    return (rawList as List)
        .map((item) => ItemModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  Future<void> saveItems(List<Item> items) async {
    final serialized = items
        .map((i) => jsonEncode(ItemModel.fromDomain(i).toJson()))
        .toList();
    await _masterBox.put('items', serialized);
  }

  // --- Master: Routes ---
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

  Future<void> saveRoutes(List<RouteModel> routes) async {
    final serialized = routes
        .map((r) => jsonEncode({'id': r.id, 'name': r.name, 'description': r.description}))
        .toList();
    await _masterBox.put('routes', serialized);
  }

  // --- Sync Queue (Post data offline queue) ---
  List<SyncQueueItem> getSyncQueue() {
    final keys = _syncQueueBox.keys.toList();
    return keys.map((key) {
      final raw = _syncQueueBox.get(key);
      return SyncQueueItem.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    }).toList();
  }

  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    await _syncQueueBox.put(item.id, jsonEncode(item.toJson()));
  }

  Future<void> updateSyncItem(SyncQueueItem item) async {
    await _syncQueueBox.put(item.id, jsonEncode(item.toJson()));
  }

  Future<void> dequeueSyncItem(String id) async {
    await _syncQueueBox.delete(id);
  }

  // --- Local Transaction History (For dashboards & instant offline display) ---
  List<SalesInvoice> getLocalInvoices() {
    final rawList = _localHistoryBox.get('invoices', defaultValue: []);
    return (rawList as List)
        .map((item) => SalesInvoiceModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

  Future<void> saveLocalInvoice(SalesInvoice invoice) async {
    final current = getLocalInvoices();
    final model = SalesInvoiceModel.fromDomain(invoice);
    
    // Add or update
    final index = current.indexWhere((inv) => inv.id == invoice.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }
    
    final serialized = current.map((inv) => jsonEncode(SalesInvoiceModel.fromDomain(inv).toJson())).toList();
    await _localHistoryBox.put('invoices', serialized);
    
    // Update local cached item inventory stock instantly!
    final localItems = getItems();
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

  List<ReceiptVoucher> getLocalReceipts() {
    final rawList = _localHistoryBox.get('receipts', defaultValue: []);
    return (rawList as List)
        .map((item) => ReceiptVoucherModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

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

  List<SalesReturn> getLocalReturns() {
    final rawList = _localHistoryBox.get('returns', defaultValue: []);
    return (rawList as List)
        .map((item) => SalesReturnModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

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

  List<ExpenseEntry> getLocalExpenses() {
    final rawList = _localHistoryBox.get('expenses', defaultValue: []);
    return (rawList as List)
        .map((item) => ExpenseEntryModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))))
        .toList();
  }

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

  CashClosing? getLocalCashClosing() {
    final raw = _localHistoryBox.get('cash_closing');
    if (raw == null) return null;
    return CashClosingModel.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  Future<void> saveLocalCashClosing(CashClosing closing) async {
    final model = CashClosingModel.fromDomain(closing);
    await _localHistoryBox.put('cash_closing', jsonEncode(model.toJson()));
  }

  // --- OAuth 2.0 Token Storage ---
  String? get oauthAccessToken => _masterBox.get('oauth_access_token');
  Future<void> setOauthAccessToken(String? token) async {
    await _masterBox.put('oauth_access_token', token);
  }

  int? get oauthTokenExpiry => _masterBox.get('oauth_token_expiry');
  Future<void> setOauthTokenExpiry(int? expiryMillis) async {
    await _masterBox.put('oauth_token_expiry', expiryMillis);
  }
}
