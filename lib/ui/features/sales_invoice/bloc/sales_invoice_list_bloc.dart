// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/invoice_repository.dart';
import '../../../../domain/repositories/sales_order_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../domain/utils/stock_rules.dart';
import '../../../core/utils/date_filter.dart';
import '../../../core/utils/error_mapper.dart';
import 'sales_invoice_list_event.dart';
import 'sales_invoice_list_state.dart';

/// Manages sales-invoice listing, date filtering, live-first remote loads, and batch conversions.
class SalesInvoiceListBloc
    extends Bloc<SalesInvoiceListEvent, SalesInvoiceListState> {
  final InvoiceRepository _invoiceRepository;
  final SalesOrderRepository _salesOrderRepository;
  final SyncRepository _syncRepository;
  final DocumentNumberService _documentNumberService;

  /// Bumped on every remote list request; stale completions must not emit.
  int _fetchGeneration = 0;

  SalesInvoiceListBloc({
    required InvoiceRepository invoiceRepository,
    required SalesOrderRepository salesOrderRepository,
    required SyncRepository syncRepository,
    required DocumentNumberService documentNumberService,
  }) : _invoiceRepository = invoiceRepository,
       _salesOrderRepository = salesOrderRepository,
       _syncRepository = syncRepository,
       _documentNumberService = documentNumberService,
       super(
         SalesInvoiceListState(
           startDate: todayDate(),
           endDate: todayDate(),
         ),
       ) {
    on<LoadInvoices>(_onLoadInvoices);
    on<RefreshInvoicesFromZoho>(_onRefreshInvoicesFromZoho);
    on<SetDateFilter>(_onSetDateFilter);
    on<ConvertOrdersBatch>(_onConvertOrdersBatch);
    on<ClearInvoiceListMessages>(_onClearMessages);
  }

  Future<void> _fetchInvoices(
    Emitter<SalesInvoiceListState> emit, {
    required DateTime? rangeStart,
    required DateTime? rangeEnd,
    bool applyDates = false,
  }) async {
    final generation = ++_fetchGeneration;

    emit(
      state.copyWith(
        startDate: applyDates ? () => rangeStart : null,
        endDate: applyDates ? () => rangeEnd : null,
        status: SalesInvoiceListStatus.loading,
        clearMessages: true,
      ),
    );

    try {
      final loaded = await _invoiceRepository.fetchRemoteInvoices(
        startDate: rangeStart,
        endDate: rangeEnd,
      );
      if (generation != _fetchGeneration) return;
      emit(
        state.copyWith(
          invoices: loaded,
          status: SalesInvoiceListStatus.success,
        ),
      );
    } catch (e) {
      if (generation != _fetchGeneration) return;
      emit(
        state.copyWith(
          invoices: _invoiceRepository.getLocalInvoices(),
          status: SalesInvoiceListStatus.failure,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  Future<void> _onLoadInvoices(
    LoadInvoices event,
    Emitter<SalesInvoiceListState> emit,
  ) =>
      _fetchInvoices(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onRefreshInvoicesFromZoho(
    RefreshInvoicesFromZoho event,
    Emitter<SalesInvoiceListState> emit,
  ) =>
      _fetchInvoices(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onSetDateFilter(
    SetDateFilter event,
    Emitter<SalesInvoiceListState> emit,
  ) =>
      _fetchInvoices(
        emit,
        rangeStart: event.startDate,
        rangeEnd: event.endDate,
        applyDates: true,
      );

  void _onClearMessages(
    ClearInvoiceListMessages event,
    Emitter<SalesInvoiceListState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }

  /// Converts each open order in [event.orders] to a local invoice, continuing
  /// past individual failures (e.g. insufficient stock) and reporting a summary.
  Future<void> _onConvertOrdersBatch(
    ConvertOrdersBatch event,
    Emitter<SalesInvoiceListState> emit,
  ) async {
    final candidates = event.orders.where((o) => !o.isConverted).toList();
    if (candidates.isEmpty) {
      emit(
        state.copyWith(
          errorMessage: 'No open orders selected to convert',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: SalesInvoiceListStatus.loading,
        clearMessages: true,
      ),
    );
    var successCount = 0;
    final failures = <String>[];

    for (var i = 0; i < candidates.length; i++) {
      final order = candidates[i];
      try {
        await _convertSingleOrder(order, batchIndex: i);
        successCount++;
      } on InsufficientStockException catch (e) {
        failures.add('${order.orderNumber}: ${userFacingMessage(e)}');
      } catch (e) {
        failures.add('${order.orderNumber}: $e');
      }
    }

    unawaited(_syncRepository.triggerSync());
    final updatedInvoices = _invoiceRepository.getLocalInvoices();

    if (successCount == 0) {
      emit(
        state.copyWith(
          invoices: updatedInvoices,
          status: SalesInvoiceListStatus.failure,
          errorMessage: failures.isEmpty
              ? 'No orders converted'
              : 'Convert failed. Load stock first if needed.\n${failures.join('\n')}',
        ),
      );
      return;
    }

    final summary = failures.isEmpty
        ? 'Converted $successCount order${successCount == 1 ? '' : 's'} to invoice'
        : 'Converted $successCount of ${candidates.length}. '
              'Failures (try Items → Create Stock Transfer first):\n'
              '${failures.join('\n')}';

    emit(
      state.copyWith(
        invoices: updatedInvoices,
        status: SalesInvoiceListStatus.success,
        successMessage: summary,
      ),
    );
  }

  Future<void> _convertSingleOrder(
    SalesOrder order, {
    int batchIndex = 0,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tempId = 'temp_inv_${stamp}_$batchIndex';
    final invoiceNum = await _documentNumberService.nextNumber(
      DocType.invoice,
    );

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

    final invoice = SalesInvoice(
      id: tempId,
      invoiceNumber: invoiceNum,
      customerId: order.customerId,
      customerName: order.customerName,
      date: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 7)),
      items: items,
      notes: order.notes,
      isPendingSync: true,
    );

    await _invoiceRepository.saveLocalInvoice(invoice);

    final orders = _salesOrderRepository.getLocalOrders();
    final localOrder = orders.firstWhere(
      (o) => o.id == order.id,
      orElse: () => order,
    );
    await _salesOrderRepository.saveLocalOrder(
      localOrder.copyWith(
        status: SalesOrderStatus.invoiced,
        convertedInvoiceNumber: invoiceNum,
      ),
    );

    final convertItem = SyncQueueItem(
      id: tempId,
      type: 'convert_so',
      payload: {
        'salesorder_id': localOrder.zohoOrderId ?? localOrder.id,
        'source_order_id': localOrder.id,
        'local_invoice_id': invoice.id,
      },
      status: SyncStatus.pending,
      timestamp: DateTime.now(),
    );
    await _invoiceRepository.enqueueSyncItem(convertItem);
  }
}
