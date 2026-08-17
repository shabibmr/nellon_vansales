import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/bloc/list_load_status.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_list_state.dart';

void main() {
  test('ExpenseListState copyWith maps isLoading onto ListLoadStatus', () {
    const initial = ExpenseListState();
    expect(initial.status, ListLoadStatus.initial);
    expect(initial.isLoading, isFalse);

    final loading = initial.copyWith(isLoading: true);
    expect(loading.status, ListLoadStatus.loading);
    expect(loading.isLoading, isTrue);

    final ok = loading.copyWith(isLoading: false);
    expect(ok.status, ListLoadStatus.success);

    final failed = loading.copyWith(
      isLoading: false,
      errorMessage: 'boom',
    );
    expect(failed.status, ListLoadStatus.failure);
    expect(failed.isLoading, isFalse);
  });
}
