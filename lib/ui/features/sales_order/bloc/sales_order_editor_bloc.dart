// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';
import 'sales_order_editor_event.dart';
import 'sales_order_editor_state.dart';

/// Manages a single sales-order form: open, edit lines, save, enqueue sync.
class SalesOrderEditorBloc
    extends Bloc<SalesOrderEditorEvent, SalesOrderEditorState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;
  final DocumentNumberService _documentNumberService;

  SalesOrderEditorBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
    required DocumentNumberService documentNumberService,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       _documentNumberService = documentNumberService,
       super(const SalesOrderEditorState()) {
    on<StartNewSalesOrder>(_onStartNewSalesOrder);
    on<OpenSalesOrder>(_onOpenSalesOrder);
    on<RetryLoadSalesOrder>(_onRetryLoadSalesOrder);
    on<RefreshSalesOrderFromZoho>(_onRefreshSalesOrderFromZoho);
    on<UpdateOrderNotes>(_onUpdateOrderNotes);
    on<UpdateOrderShipmentDate>(_onUpdateShipmentDate);
    on<UpdateOrderCustomer>(_onUpdateOrderCustomer);
    on<AddOrUpdateOrderLine>(_onAddOrUpdateLineItem);
    on<RemoveOrderLine>(_onRemoveLineItem);
    on<SaveSalesOrder>(_onSaveOrder);
    on<ClearSalesOrderEditorMessages>(_onClearMessages);
  }

  /// True for an id minted offline in [_onSaveOrder] that Zoho has never seen.
  static bool _isLocalOrderId(String id) => id.startsWith('temp_so_');

  void _onStartNewSalesOrder(
    StartNewSalesOrder event,
    Emitter<SalesOrderEditorState> emit,
  ) {
    final now = DateTime.now();
    emit(
      state.copyWith(
        clearEditingOrderId: true,
        clearEditingCustomer: event.customer == null,
        clearMessages: true,
        editingDate: now,
        editingShipmentDate: now,
        editingItems: const [],
        editingNotes: '',
        isEditingNew: true,
        isEditorLoading: false,
        isSaving: false,
        clearEditorError: true,
        editingCustomer: event.customer,
      ),
    );
  }

  /// Opens [event.order]. A saved order is always re-read from Zoho so the
  /// editor shows the server's current copy — the list endpoint returns headers
  /// without `line_items`. Only a pending first push opens locally.
  Future<void> _onOpenSalesOrder(
    OpenSalesOrder event,
    Emitter<SalesOrderEditorState> emit,
  ) async {
    if (event.order.isPendingSync || _isLocalOrderId(event.order.id)) {
      emit(_openedFrom(event.order));
      return;
    }

    emit(
      state.copyWith(
        editingOrderId: event.order.id,
        clearEditingOrder: true,
        clearEditingCustomer: true,
        clearMessages: true,
        clearEditorError: true,
        editingItems: const [],
        editingNotes: '',
        isEditingNew: false,
        isEditorLoading: true,
        isSaving: false,
      ),
    );
    final remoteId = event.order.zohoOrderId ?? event.order.id;
    await _loadEditingOrderFromZoho(remoteId, emit);
  }

  Future<void> _onRetryLoadSalesOrder(
    RetryLoadSalesOrder event,
    Emitter<SalesOrderEditorState> emit,
  ) async {
    final orderId = _remoteOrderIdForLoad();
    if (orderId == null || orderId.isEmpty) return;
    emit(state.copyWith(isEditorLoading: true, clearEditorError: true));
    await _loadEditingOrderFromZoho(orderId, emit);
  }

  Future<void> _onRefreshSalesOrderFromZoho(
    RefreshSalesOrderFromZoho event,
    Emitter<SalesOrderEditorState> emit,
  ) async {
    final orderId = _remoteOrderIdForLoad();
    if (orderId == null ||
        orderId.isEmpty ||
        _isLocalOrderId(orderId) ||
        state.isEditorLoading ||
        state.isRefreshing ||
        state.editingOrder == null) {
      return;
    }
    emit(
      state.copyWith(
        isRefreshing: true,
        clearEditorError: true,
        clearMessages: true,
      ),
    );
    await _loadEditingOrderFromZoho(
      orderId,
      emit,
      isRefresh: true,
      forceDirty: event.forceDirty,
    );
  }

  void _onUpdateOrderNotes(
    UpdateOrderNotes event,
    Emitter<SalesOrderEditorState> emit,
  ) {
    emit(state.copyWith(editingNotes: event.notes));
  }

  String? _remoteOrderIdForLoad() {
    final zohoId = state.editingOrder?.zohoOrderId;
    if (zohoId != null && zohoId.isNotEmpty) return zohoId;
    return state.editingOrderId;
  }

  /// Local-only resolve (no network) for offline open fallback.
  SalesOrder? _localOrderById(String orderId) {
    for (final o in _salesRepository.getLocalOrders()) {
      if (o.id == orderId || o.zohoOrderId == orderId) return o;
    }
    return null;
  }

  /// Reads `GET /salesorders/{id}`. On failure keeps a blank form + [editorError].
  Future<void> _loadEditingOrderFromZoho(
    String orderId,
    Emitter<SalesOrderEditorState> emit, {
    bool isRefresh = false,
    bool forceDirty = false,
  }) async {
    final previous = isRefresh ? state.editingOrder : null;
    final wasDirty = isRefresh && (state.isFormDirty || forceDirty);

    SalesOrder? fetched;
    try {
      fetched = await _salesRepository.fetchRemoteOrder(
        orderId,
        allowOfflineFallback: false,
      );
    } catch (e) {
      if (isRefresh) {
        emit(
          state.copyWith(
            isRefreshing: false,
            errorMessage: humanizeSyncError(e),
          ),
        );
        return;
      }
      final local = _localOrderById(orderId);
      if (local != null) {
        emit(
          _openedFrom(local).copyWith(
            infoMessage: 'Showing offline copy',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          isEditorLoading: false,
          isRefreshing: false,
          editorError: humanizeSyncError(e),
        ),
      );
      return;
    }

    if (fetched == null) {
      if (!isRefresh) {
        final local = _localOrderById(orderId);
        if (local != null) {
          emit(
            _openedFrom(local).copyWith(
              infoMessage: 'Not found in Zoho — showing local copy',
            ),
          );
          return;
        }
      }
      if (isRefresh && previous != null) {
        emit(
          state.copyWith(
            isRefreshing: false,
            errorMessage: 'This sales order was not found in Zoho Books.',
          ),
        );
      } else {
        emit(
          state.copyWith(
            isEditorLoading: false,
            isRefreshing: false,
            editorError: 'This sales order was not found in Zoho Books.',
          ),
        );
      }
      return;
    }

    final opened = _openedFrom(fetched);
    if (isRefresh) {
      final contentUnchanged = previous != null &&
          VoucherContentFingerprint.salesOrder(previous) ==
              VoucherContentFingerprint.salesOrder(fetched);
      emit(
        opened.copyWith(
          isRefreshing: false,
          infoMessage: (wasDirty || !contentUnchanged)
              ? 'Updated from Zoho Books'
              : 'Already up to date',
        ),
      );
    } else {
      emit(opened);
    }
  }

  /// Prefer the master-data customer when present so credit/route/contact
  /// fields are real; fall back to a name-only stub for offline orphans.
  Customer _customerForOrder(SalesOrder order) {
    for (final c in _salesRepository.getCustomers()) {
      if (c.id == order.customerId) return c;
    }
    return Customer(
      id: order.customerId,
      name: order.customerName,
      companyName: order.customerName,
      email: '',
      phone: '',
      address: '',
      outstandingBalance: 0,
      creditLimit: 0,
      routeId: '',
      sequence: 0,
    );
  }

  /// Seeds form fields from [order] — shared by local and Zoho open paths.
  SalesOrderEditorState _openedFrom(SalesOrder order) {
    final customer = _customerForOrder(order);

    return state.copyWith(
      editingOrderId: order.id,
      editingOrder: order.copyWith(),
      editingDate: order.date,
      editingShipmentDate: order.shipmentDate,
      editingCustomer: customer,
      editingItems: List.of(order.items),
      editingNotes: order.notes,
      isEditingNew: false,
      isEditorLoading: false,
      isSaving: false,
      clearMessages: true,
      clearEditorError: true,
    );
  }

  void _onUpdateShipmentDate(
    UpdateOrderShipmentDate event,
    Emitter<SalesOrderEditorState> emit,
  ) {
    emit(state.copyWith(editingShipmentDate: event.shipmentDate));
  }

  void _onUpdateOrderCustomer(
    UpdateOrderCustomer event,
    Emitter<SalesOrderEditorState> emit,
  ) {
    emit(state.copyWith(editingCustomer: event.customer));
  }

  void _onAddOrUpdateLineItem(
    AddOrUpdateOrderLine event,
    Emitter<SalesOrderEditorState> emit,
  ) {
    final items = List<OrderLineItem>.from(state.editingItems);
    final idx = items.indexWhere((line) => line.item.id == event.item.id);

    final lineUom = (event.uom != null && event.uom!.trim().isNotEmpty)
        ? event.uom!.trim()
        : event.item.uom;

    if (idx >= 0) {
      if (event.quantity <= 0) {
        items.removeAt(idx);
      } else {
        items[idx] = items[idx].copyWith(
          quantity: event.quantity,
          rate: event.rate,
          discount: event.discount,
          uom: lineUom,
          unitConversionId: event.unitConversionId,
        );
      }
    } else {
      if (event.quantity > 0) {
        items.add(
          OrderLineItem(
            item: event.item,
            quantity: event.quantity,
            rate: event.rate ?? event.item.rate,
            taxPercentage: event.item.taxPercentage,
            discount: event.discount ?? 0.0,
            uom: lineUom,
            unitConversionId: event.unitConversionId ?? '',
          ),
        );
      }
    }
    emit(state.copyWith(editingItems: items, clearMessages: true));
  }

  void _onRemoveLineItem(
    RemoveOrderLine event,
    Emitter<SalesOrderEditorState> emit,
  ) {
    final items = List<OrderLineItem>.from(state.editingItems);
    items.removeWhere((line) => line.item.id == event.item.id);
    emit(state.copyWith(editingItems: items));
  }

  Future<void> _onSaveOrder(
    SaveSalesOrder event,
    Emitter<SalesOrderEditorState> emit,
  ) async {
    if (state.isConverted) {
      emit(
        state.copyWith(
          errorMessage: 'This sales order has already been converted to an invoice',
        ),
      );
      return;
    }
    if (state.editingCustomer == null) {
      emit(state.copyWith(errorMessage: 'Please select a customer'));
      return;
    }
    if (state.editingItems.isEmpty) {
      emit(state.copyWith(errorMessage: 'Please add at least one line item'));
      return;
    }

    emit(state.copyWith(isSaving: true, clearMessages: true));
    try {
      final isNew = state.isEditingNew;
      final tempId =
          state.editingOrderId ??
          'temp_so_${DateTime.now().millisecondsSinceEpoch}';

      String orderNum;
      String? existingZohoOrderId;
      if (isNew) {
        orderNum = await _documentNumberService.nextNumber(DocType.salesOrder);
      } else {
        final originalOrder = state.editingOrder;
        if (originalOrder == null || originalOrder.id != tempId) {
          emit(
            state.copyWith(
              isSaving: false,
              errorMessage: 'Could not find the order being edited',
            ),
          );
          return;
        }
        orderNum = originalOrder.orderNumber;
        existingZohoOrderId = originalOrder.zohoOrderId;
      }

      final order = SalesOrder(
        id: tempId,
        orderNumber: orderNum,
        customerId: state.editingCustomer!.id,
        customerName: state.editingCustomer!.name,
        date: state.editingDate ?? DateTime.now(),
        shipmentDate:
            state.editingShipmentDate ?? state.editingDate ?? DateTime.now(),
        items: state.editingItems,
        notes: event.notes,
        isPendingSync: true,
        zohoOrderId: existingZohoOrderId,
        status: state.editingOrder?.status ?? SalesOrderStatus.open,
        convertedInvoiceNumber: state.editingOrder?.convertedInvoiceNumber,
      );

      await _salesRepository.saveLocalOrder(order);

      final isUpdate =
          existingZohoOrderId != null && existingZohoOrderId.isNotEmpty;
      await _salesRepository.enqueueSalesOrder(order, isUpdate: isUpdate);

      unawaited(_syncRepository.triggerSync());

      emit(
        state.copyWith(
          editingOrderId: order.id,
          editingOrder: order,
          isEditingNew: false,
          isSaving: false,
          successMessage: 'Sales Order saved successfully',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  void _onClearMessages(
    ClearSalesOrderEditorMessages event,
    Emitter<SalesOrderEditorState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
