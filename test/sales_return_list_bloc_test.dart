import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/repositories/sales_return_repository.dart';
import 'package:van_sales/ui/features/sales_return/bloc/sales_return_list_bloc.dart';
import 'package:van_sales/ui/features/sales_return/bloc/sales_return_list_event.dart';

/// Minimal fake: return list methods only; others noSuchMethod.
class FakeSalesRepository implements SalesReturnRepository {
  List<SalesReturn> returns = [];

  @override
  List<SalesReturn> getLocalReturns() => List.of(returns);

  @override
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      List.of(returns);

  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {
    returns.add(salesReturn);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (invocation.isGetter) return null;
    if (name.contains('List') ||
        name.contains('getLocal') ||
        name.contains('getCustomers') ||
        name.contains('getItems') ||
        name.contains('getRoutes') ||
        name.contains('getSync') ||
        name.contains('getOpen') ||
        name.contains('getWarehouses')) {
      return [];
    }
    if (name.contains('hasPending')) return false;
    return Future.value();
  }
}

void main() {
  late FakeSalesRepository salesRepo;
  late SalesReturnListBloc bloc;

  setUp(() {
    salesRepo = FakeSalesRepository();
    bloc = SalesReturnListBloc(salesReturnRepository: salesRepo);
  });

  tearDown(() async => bloc.close());

  test('LoadReturns fetches remote returns for active filter', () async {
    salesRepo.returns = [
      SalesReturn(
        id: 'ret_1',
        creditNoteNumber: 'CN-001',
        customerId: 'cust_1',
        customerName: 'Acme',
        date: DateTime.now(),
        reason: 'Damaged packaging',
        items: const [],
      ),
    ];

    bloc.add(const LoadReturns());
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.returns, hasLength(1));
    expect(bloc.state.returns.single.creditNoteNumber, 'CN-001');
  });
}
