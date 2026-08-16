// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/models/submit_result.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../domain/utils/stock_rules.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';
import '../../../core/utils/error_mapper.dart';
import 'sales_invoice_editor_event.dart';
import 'sales_invoice_editor_state.dart';

/// Manages a single sales-invoice form: open, edit lines, save, enqueue sync.
class SalesInvoiceEditorBloc
    extends Bloc<SalesInvoiceEditorEvent, SalesInvoiceEditorState> {
  final SalesRepository _salesRepository;
  // ignore: unused_field — kept so existing BlocProvider wiring stays unchanged
  final SyncRepository _syncRepository;
  final DocumentNumberService _documentNumberService;

  SalesInvoiceEditorBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
    required DocumentNumberService documentNumberService,
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       _documentNumberService = documentNumberService,
       super(const SalesInvoiceEditorState()) {
    on<StartNewInvoice>(_onStartNewInvoice);
    on<OpenSalesInvoice>(_onOpenSalesInvoice);
    on<StartInvoiceFromOrder>(_onStartInvoiceFromOrder);
    on<RetryLoadSalesInvoice>(_onRetryLoadSalesInvoice);
    on<RefreshSalesInvoiceFromZoho>(_onRefreshSalesInvoiceFromZoho);
    on<UpdateInvoiceNotes>(_onUpdateInvoiceNotes);
    on<UpdateInvoiceDate>(_onUpdateInvoiceDate);
    on<UpdateInvoiceCustomer>(_onUpdateInvoiceCustomer);
    on<AddOrUpdateLineItem>(_onAddOrUpdateLineItem);
    on<RemoveLineItem>(_onRemoveLineItem);
    on<SaveInvoice>(_onSaveInvoice);
    on<ClearSalesInvoiceEditorMessages>(_onClearMessages);
  }

  static bool _isLocalInvoiceId(String id) => id.startsWith('temp_inv_');

  void _onStartNewInvoice(
    StartNewInvoice event,
    Emitter<SalesInvoiceEditorState> emit,
  ) {
    final now = DateTime.now();
    emit(
      state.copyWith(
        clearEditingInvoiceId: true,
        clearEditingCustomer: event.customer == null,
        clearMessages: true,
        clearSource: true,
        editingDate: now,
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

  Future<void> _onOpenSalesInvoice(
    OpenSalesInvoice event,
    Emitter<SalesInvoiceEditorState> emit,
  ) async {
    if (event.invoice.isPendingSync) {
      emit(_openedFrom(event.invoice));
      return;
    }
    final remoteId = event.invoice.zohoInvoiceId ?? event.invoice.id;
    if (_isLocalInvoiceId(remoteId)) {
      emit(_openedFrom(event.invoice));
      return;
    }

    emit(
      state.copyWith(
        editingInvoiceId: event.invoice.id,
        clearEditingInvoice: true,
        clearEditingCustomer: true,
        clearMessages: true,
        clearEditorError: true,
        clearSource: true,
        editingItems: const [],
        editingNotes: '',
        isEditingNew: false,
        isEditorLoading: true,
        isSaving: false,
      ),
    );
    await _loadEditingInvoiceFromZoho(remoteId, emit);
  }

  Future<void> _onRetryLoadSalesInvoice(
    RetryLoadSalesInvoice event,
    Emitter<SalesInvoiceEditorState> emit,
  ) async {
    final invoiceId = _remoteInvoiceIdForLoad();
    if (invoiceId == null || invoiceId.isEmpty) return;
    emit(state.copyWith(isEditorLoading: true, clearEditorError: true));
    await _loadEditingInvoiceFromZoho(invoiceId, emit);
  }

  Future<void> _onRefreshSalesInvoiceFromZoho(
    RefreshSalesInvoiceFromZoho event,
    Emitter<SalesInvoiceEditorState> emit,
  ) async {
    final invoiceId = _remoteInvoiceIdForLoad();
    if (invoiceId == null ||
        invoiceId.isEmpty ||
        _isLocalInvoiceId(invoiceId) ||
        state.isEditorLoading ||
        state.isRefreshing ||
        state.editingInvoice == null) {
      return;
    }
    emit(
      state.copyWith(
        isRefreshing: true,
        clearEditorError: true,
        clearMessages: true,
      ),
    );
    await _loadEditingInvoiceFromZoho(
      invoiceId,
      emit,
      isRefresh: true,
      forceDirty: event.forceDirty,
    );
  }

  String? _remoteInvoiceIdForLoad() {
    final zohoId = state.editingInvoice?.zohoInvoiceId;
    if (zohoId != null && zohoId.isNotEmpty) return zohoId;
    return state.editingInvoiceId ?? state.editingInvoice?.id;
  }

  void _onUpdateInvoiceNotes(
    UpdateInvoiceNotes event,
    Emitter<SalesInvoiceEditorState> emit,
  ) {
    emit(state.copyWith(editingNotes: event.notes));
  }

  Future<void> _loadEditingInvoiceFromZoho(
    String invoiceId,
    Emitter<SalesInvoiceEditorState> emit, {
    bool isRefresh = false,
    bool forceDirty = false,
  }) async {
    final previous = isRefresh ? state.editingInvoice : null;
    final wasDirty = isRefresh && (state.isFormDirty || forceDirty);

    // Prefer remote; on open/retry fall back to local with a soft notice.
    SalesInvoice? fetched;
    try {
      fetched = await _salesRepository.fetchInvoiceById(
        invoiceId,
        forceRemote: true,
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
      try {
        fetched = await _salesRepository.fetchInvoiceById(
          invoiceId,
          forceRemote: false,
        );
      } catch (_) {
        fetched = null;
      }
      if (fetched != null) {
        emit(
          _openedFrom(fetched).copyWith(
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
        SalesInvoice? local;
        try {
          local = await _salesRepository.fetchInvoiceById(
            invoiceId,
            forceRemote: false,
          );
        } catch (_) {
          local = null;
        }
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
            errorMessage: 'This sales invoice was not found in Zoho Books.',
          ),
        );
      } else {
        emit(
          state.copyWith(
            isEditorLoading: false,
            isRefreshing: false,
            editorError: 'This sales invoice was not found in Zoho Books.',
          ),
        );
      }
      return;
    }

    final opened = _openedFrom(fetched);
    if (isRefresh) {
      final contentUnchanged = previous != null &&
          VoucherContentFingerprint.salesInvoice(previous) ==
              VoucherContentFingerprint.salesInvoice(fetched);
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

  void _onStartInvoiceFromOrder(
    StartInvoiceFromOrder event,
    Emitter<SalesInvoiceEditorState> emit,
  ) {
    final order = event.order;
    final customer = _customerForId(order.customerId, order.customerName);

    final items = order.items
        .map(
          (line) => InvoiceLineItem(
            item: line.item,
            quantity: line.quantity,
            rate: line.rate,
            taxPercentage: line.taxPercentage,
            discount: line.discount,
            uom: line.displayUom,
            unitConversionId: line.unitConversionId,
          ),
        )
        .toList();

    emit(
      state.copyWith(
        editingInvoiceId: 'temp_inv_${DateTime.now().millisecondsSinceEpoch}',
        editingDate: DateTime.now(),
        editingCustomer: customer,
        editingItems: items,
        editingNotes: order.notes,
        isEditingNew: true,
        sourceOrderId: order.id,
        sourceOrder: order,
        isEditorLoading: false,
        isSaving: false,
        clearMessages: true,
        clearEditorError: true,
      ),
    );
  }

  Customer _customerForId(String customerId, String nameFallback) {
    for (final c in _salesRepository.getCustomers()) {
      if (c.id == customerId) return c;
    }
    return Customer(
      id: customerId,
      name: nameFallback,
      companyName: nameFallback,
      email: '',
      phone: '',
      address: '',
      outstandingBalance: 0,
      creditLimit: 0,
      routeId: '',
      sequence: 0,
    );
  }

  SalesInvoiceEditorState _openedFrom(SalesInvoice invoice) {
    final customer = _customerForId(invoice.customerId, invoice.customerName);

    return state.copyWith(
      editingInvoiceId: invoice.id,
      editingInvoice: invoice.copyWith(),
      editingDate: invoice.date,
      editingCustomer: customer,
      editingItems: List.of(invoice.items),
      editingNotes: invoice.notes,
      isEditingNew: false,
      isEditorLoading: false,
      isSaving: false,
      clearMessages: true,
      clearEditorError: true,
      clearSource: true,
    );
  }

  void _onUpdateInvoiceDate(
    UpdateInvoiceDate event,
    Emitter<SalesInvoiceEditorState> emit,
  ) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onUpdateInvoiceCustomer(
    UpdateInvoiceCustomer event,
    Emitter<SalesInvoiceEditorState> emit,
  ) {
    emit(state.copyWith(editingCustomer: event.customer));
  }

  void _onAddOrUpdateLineItem(
    AddOrUpdateLineItem event,
    Emitter<SalesInvoiceEditorState> emit,
  ) {
    final items = List<InvoiceLineItem>.from(state.editingItems);
    final idx = items.indexWhere((line) => line.item.id == event.item.id);

    double originalBaseQty = 0;
    if (!state.isEditingNew && state.editingInvoice != null) {
      final origLineIndex = state.editingInvoice!.items.indexWhere(
        (line) => line.item.id == event.item.id,
      );
      if (origLineIndex >= 0) {
        originalBaseQty = state.editingInvoice!.items[origLineIndex].quantityInBase;
      }
    }

    final lineUom = (event.uom != null && event.uom!.trim().isNotEmpty)
        ? event.uom!.trim()
        : event.item.uom;
    final requestedBaseQty =
        event.quantity * event.item.conversionRateFor(lineUom);

    final allowedStock = event.item.stock + originalBaseQty;
    try {
      deductStock(
        itemId: event.item.id,
        itemName: event.item.name,
        available: allowedStock,
        requested: requestedBaseQty,
      );
    } on InsufficientStockException catch (e) {
      emit(state.copyWith(errorMessage: userFacingMessage(e)));
      return;
    }

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
          InvoiceLineItem(
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
    RemoveLineItem event,
    Emitter<SalesInvoiceEditorState> emit,
  ) {
    final items = List<InvoiceLineItem>.from(state.editingItems);
    items.removeWhere((line) => line.item.id == event.item.id);
    emit(state.copyWith(editingItems: items));
  }

  Future<void> _onSaveInvoice(
    SaveInvoice event,
    Emitter<SalesInvoiceEditorState> emit,
  ) async {
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
          state.editingInvoiceId ??
          'temp_inv_${DateTime.now().millisecondsSinceEpoch}';

      String invoiceNum;
      if (isNew) {
        invoiceNum = await _documentNumberService.nextNumber(DocType.invoice);
      } else {
        final originalInvoice = state.editingInvoice;
        if (originalInvoice == null || originalInvoice.id != tempId) {
          emit(
            state.copyWith(
              isSaving: false,
              errorMessage: 'Could not find the invoice being edited',
            ),
          );
          return;
        }
        invoiceNum = originalInvoice.invoiceNumber;
      }

      if (isTempCustomerId(state.editingCustomer!.id)) {
        emit(
          state.copyWith(
            isSaving: false,
            errorMessage: 'Customer must sync to Zoho before invoicing',
          ),
        );
        return;
      }

      final invoice = SalesInvoice(
        id: tempId,
        invoiceNumber: invoiceNum,
        customerId: state.editingCustomer!.id,
        customerName: state.editingCustomer!.name,
        date: state.editingDate ?? DateTime.now(),
        dueDate: (state.editingDate ?? DateTime.now()).add(
          const Duration(days: 7),
        ),
        items: state.editingItems,
        notes: event.notes,
        isPendingSync: true,
      );

      final SubmitResult result;
      final sourceOrderId = state.sourceOrderId;
      if (sourceOrderId != null) {
        final orders = _salesRepository.getLocalOrders();
        final order = orders.firstWhere(
          (o) => o.id == sourceOrderId,
          orElse: () => state.sourceOrder!,
        );
        final zohoOrderId = order.zohoOrderId;
        if (zohoOrderId == null || zohoOrderId.isEmpty) {
          emit(
            state.copyWith(
              isSaving: false,
              errorMessage: 'Order must sync to Zoho before converting',
            ),
          );
          return;
        }
        result = await _salesRepository.submitConvertSalesOrder(
          order: order,
          invoice: invoice,
        );
      } else {
        result = await _salesRepository.submitInvoice(invoice);
      }

      emit(
        state.copyWith(
          editingInvoiceId: invoice.id,
          editingInvoice: invoice,
          isEditingNew: false,
          isSaving: false,
          successMessage: result.message('Invoice saved successfully'),
          clearSource: true,
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
    ClearSalesInvoiceEditorMessages event,
    Emitter<SalesInvoiceEditorState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
