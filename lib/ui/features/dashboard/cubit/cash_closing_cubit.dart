import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/cash_closing.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../ui/core/utils/error_mapper.dart';
import 'cash_closing_state.dart';

class CashClosingCubit extends Cubit<CashClosingState> {
  final SalesRepository salesRepository;
  final SyncRepository syncRepository;

  CashClosingCubit({
    required this.salesRepository,
    required this.syncRepository,
  }) : super(CashClosingInitial());

  Future<void> submitCashClosing({
    required double todaySales,
    required double todayPayments,
    required double todayExpenses,
    required double physicalCashCounted,
    required String notes,
    double openingBalance = 1000.00,
  }) async {
    if (state is CashClosingSubmitting) return;
    emit(CashClosingSubmitting());

    try {
      final expectedClosing =
          openingBalance + todayPayments - todayExpenses;

      final closing = CashClosing(
        id: 'closing_${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime.now(),
        openingBalance: openingBalance,
        totalSalesInvoices: todaySales,
        totalReceiptsCollected: todayPayments,
        totalExpenses: todayExpenses,
        closingBalance: physicalCashCounted,
        notes: notes,
        isPendingSync: true,
      );

      await salesRepository.saveLocalCashClosing(closing);

      // Generate sync packet
      final syncItem = SyncQueueItem(
        id: closing.id,
        type: 'expense',
        payload: {
          'amount': closing.reportedDifference.abs(),
          'category': 'Miscellaneous',
          'description':
              'Daily Cash Closing: counted: $physicalCashCounted, expected: $expectedClosing. Difference: ${closing.reportedDifference.toStringAsFixed(2)}. Notes: $notes',
          'date': closing.date.toIso8601String().split('T')[0],
          'isPendingSync': true,
        },
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await salesRepository.enqueueSyncItem(syncItem);

      // Trigger background sync
      unawaited(syncRepository.triggerSync());

      emit(CashClosingSuccess(closing));
    } catch (e) {
      emit(CashClosingFailure(userFacingMessage(e)));
    }
  }
}
