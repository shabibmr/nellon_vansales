// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/models/sales_invoice_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../domain/utils/stock_rules.dart';
import 'sales_invoice_editor_event.dart';
import 'sales_invoice_editor_state.dart';

/// Manages a single sales-invoice form: open, edit lines, save, enqueue sync.
class SalesInvoiceEditorBloc
    extends Bloc<SalesInvoiceEditorEvent, SalesInvoiceEditorState> {
  final SalesRepository _salesRepository;
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
    if (event.invoice.isPendingSync || _isLocalInvoiceId(event.invoice.id)) {
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
    await _loadEditingInvoiceFromZoho(event.invoice.id, emit);
  }

  Future<void> _onRetryLoadSalesInvoice(
    RetryLoadSalesInvoice event,
    Emitter<SalesInvoiceEditorState> emit,
  ) async {
    final invoiceId = state.editingInvoiceId;
    if (invoiceId == null || invoiceId.isEmpty) return;
    emit(state.copyWith(isEditorLoading: true, clearEditorError: true));
    await _loadEditingInvoiceFromZoho(invoiceId, emit);
  }

  Future<void> _loadEditingInvoiceFromZoho(
    String invoiceId,
    Emitter<SalesInvoiceEditorState> emit,
  ) async {
    try {
      final fetched = await _salesRepository.fetchInvoiceById(invoiceId);
      if (fetched == null) {
        emit(
          state.copyWith(
            isEditorLoading: false,
            editorError: 'This sales invoice was not found in Zoho Books.',
          ),
        );
        return;
      }
      emit(_openedFrom(fetched));
    } catch (e) {
      emit(
        state.copyWith(
          isEditorLoading: false,
          editorError: humanizeSyncError(e),
        ),
      );
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
      emit(state.copyWith(errorMessage: e.toString()));
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

      await _salesRepository.saveLocalInvoice(invoice);

      final sourceOrderId = state.sourceOrderId;
      if (sourceOrderId != null) {
        final orders = _salesRepository.getLocalOrders();
        final order = orders.firstWhere(
          (o) => o.id == sourceOrderId,
          orElse: () => state.sourceOrder!,
        );
        await _salesRepository.saveLocalOrder(
          order.copyWith(
            status: SalesOrderStatus.invoiced,
            convertedInvoiceNumber: invoiceNum,
          ),
        );

        final convertItem = SyncQueueItem(
          id: tempId,
          type: 'convert_so',
          payload: {
            'salesorder_id': order.zohoOrderId ?? order.id,
            'source_order_id': order.id,
            'local_invoice_id': invoice.id,
          },
          status: SyncStatus.pending,
          timestamp: DateTime.now(),
        );
        await _salesRepository.enqueueSyncItem(convertItem);
      } else {
        final syncItem = SyncQueueItem(
          id: tempId,
          type: 'invoice',
          payload: SalesInvoiceModel.fromDomain(invoice).toJson(),
          status: SyncStatus.pending,
          timestamp: DateTime.now(),
        );
        await _salesRepository.enqueueSyncItem(syncItem);
      }

      _syncRepository.triggerSync();

      emit(
        state.copyWith(
          editingInvoiceId: invoice.id,
          editingInvoice: invoice,
          isEditingNew: false,
          isSaving: false,
          successMessage: 'Invoice saved successfully',
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
