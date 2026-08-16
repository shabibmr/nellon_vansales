import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/document_number_service.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/repositories/invoice_repository.dart';
import 'package:van_sales/domain/repositories/sales_order_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/ui/features/sales_invoice/bloc/sales_invoice_list_bloc.dart';
import 'package:van_sales/ui/features/sales_invoice/bloc/sales_invoice_list_event.dart';
import 'package:van_sales/ui/features/sales_invoice/bloc/sales_invoice_list_state.dart';

/// Minimal recording repo: only invoice list methods are real; others noSuchMethod.
class RecordingSalesRepository
    implements InvoiceRepository, SalesOrderRepository {
  final List<({DateTime? start, DateTime? end})> fetchCalls = [];
  List<SalesInvoice> remoteInvoices = [];
  List<SalesInvoice> localInvoices = [];
  Object? fetchFailure;
  final List<Future<List<SalesInvoice>>> responseQueue = [];

  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    fetchCalls.add((start: startDate, end: endDate));
    if (responseQueue.isNotEmpty) {
      return responseQueue.removeAt(0);
    }
    if (fetchFailure != null) throw fetchFailure!;
    return List.of(remoteInvoices);
  }

  @override
  List<SalesInvoice> getLocalInvoices() => List.of(localInvoices);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('get') ||
        name.contains('has') ||
        name.contains('Id') ||
        name.contains('activeRoute')) {
      return null;
    }
    if (invocation.isGetter) return null;
    if (invocation.typeArguments.isNotEmpty ||
        name.contains('List') ||
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
    if (name.contains('isSyncing')) return false;
    return Future.value();
  }
}

class FakeSyncRepository implements SyncRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      if (invocation.memberName.toString().contains('Stream')) {
        return const Stream.empty();
      }
      if (invocation.memberName.toString().contains('isSyncing')) {
        return false;
      }
      return null;
    }
    if (invocation.memberName.toString().contains('getSyncQueue')) {
      return <dynamic>[];
    }
    if (invocation.memberName.toString().contains('hasCore')) return true;
    return Future.value();
  }
}

class FakeDocumentNumberService implements DocumentNumberService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value('INV-00001');
}

SalesInvoice _inv(String id, DateTime date) => SalesInvoice(
      id: id,
      invoiceNumber: 'INV-$id',
      customerId: 'cust_1',
      customerName: 'Acme',
      date: date,
      dueDate: date,
      items: const [],
      notes: '',
      listedTotal: 100,
    );

void main() {
  late RecordingSalesRepository repo;
  late FakeSyncRepository syncRepo;
  late SalesInvoiceListBloc bloc;

  setUp(() {
    repo = RecordingSalesRepository();
    syncRepo = FakeSyncRepository();
    bloc = SalesInvoiceListBloc(
      invoiceRepository: repo,
      salesOrderRepository: repo,
      syncRepository: syncRepo,
      documentNumberService: FakeDocumentNumberService(),
    );
  });

  tearDown(() async => bloc.close());

  test('LoadInvoices fetches remote with default today filter', () async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    repo.remoteInvoices = [_inv('1', today)];

    bloc.add(const LoadInvoices());
    await bloc.stream.firstWhere(
      (s) => s.status == SalesInvoiceListStatus.success,
    );

    expect(repo.fetchCalls, hasLength(1));
    expect(bloc.state.invoices, hasLength(1));
    expect(bloc.state.status, SalesInvoiceListStatus.success);
    expect(bloc.state.errorMessage, isNull);
  });

  test('fetch failure falls back to local invoices with humanized error',
      () async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    repo.fetchFailure = Exception('connection reset');
    repo.localInvoices = [_inv('local', today)];

    bloc.add(const LoadInvoices());
    await bloc.stream.firstWhere(
      (s) => s.status == SalesInvoiceListStatus.failure,
    );

    expect(bloc.state.invoices.map((i) => i.id), ['local']);
    expect(bloc.state.status, SalesInvoiceListStatus.failure);
    expect(bloc.state.errorMessage, isNotNull);
  });

  test('stale concurrent fetch does not overwrite newer results', () async {
    final startA = DateTime(2026, 1, 1);
    final endA = DateTime(2026, 1, 31);
    final startB = DateTime(2026, 6, 1);
    final endB = DateTime(2026, 6, 30);

    final slowA = Completer<List<SalesInvoice>>();
    final fastB = Completer<List<SalesInvoice>>();
    repo.responseQueue.addAll([slowA.future, fastB.future]);

    bloc.add(SetDateFilter(startDate: startA, endDate: endA));
    await Future<void>.delayed(Duration.zero);
    bloc.add(SetDateFilter(startDate: startB, endDate: endB));
    await Future<void>.delayed(Duration.zero);

    fastB.complete([_inv('june', startB)]);
    await bloc.stream.firstWhere(
      (s) =>
          s.status == SalesInvoiceListStatus.success &&
          s.invoices.any((i) => i.id == 'june'),
    );

    slowA.complete([_inv('jan', startA)]);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.startDate, startB);
    expect(bloc.state.endDate, endB);
    expect(bloc.state.invoices.map((i) => i.id), ['june']);
    expect(bloc.state.status, SalesInvoiceListStatus.success);
    expect(bloc.state.isLoading, isFalse);
  });
}
