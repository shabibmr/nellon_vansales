import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/expense_entry_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../ui/core/utils/error_mapper.dart';
import 'expense_log_state.dart';

class ExpenseLogCubit extends Cubit<ExpenseLogState> {
  final SalesRepository salesRepository;
  final SyncRepository syncRepository;

  ExpenseLogCubit({
    required this.salesRepository,
    required this.syncRepository,
  }) : super(ExpenseLogInitial());

  Future<void> submitExpense({
    required double amount,
    required String category,
    required String description,
    String? receiptImagePath,
  }) async {
    if (state is ExpenseLogSubmitting) return;
    emit(ExpenseLogSubmitting());

    try {
      final tempId = 'temp_exp_${DateTime.now().millisecondsSinceEpoch}';
      final expense = ExpenseEntry(
        id: tempId,
        date: DateTime.now(),
        lines: [
          ExpenseLineItem(
            category: category,
            amount: amount,
            description: description,
          ),
        ],
        receiptImagePath: receiptImagePath,
        isPendingSync: true,
      );

      // Save local
      await salesRepository.saveLocalExpense(expense);

      // Enqueue sync item
      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'expense',
        payload: ExpenseEntryModel.fromDomain(expense).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await salesRepository.enqueueSyncItem(syncItem);

      // Trigger background sync
      unawaited(syncRepository.triggerSync());

      emit(ExpenseLogSuccess(expense));
    } catch (e) {
      emit(ExpenseLogFailure(userFacingMessage(e)));
    }
  }
}
