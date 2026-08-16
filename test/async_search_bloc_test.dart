import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/repositories/item_repository.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/ui/core/bloc/async_search_bloc.dart';
import 'package:van_sales/ui/core/bloc/async_search_event.dart';
import 'package:van_sales/ui/core/bloc/async_search_state.dart';

class FakeSalesRepository implements CustomerRepository, ItemRepository {
  List<Customer> customers = [];
  List<Item> items = [];

  @override
  List<Customer> getCustomers() => customers;

  @override
  List<Item> getItems() => items;

  @override
  Future<void> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {}

  @override
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) async {}

  @override
  Future<void> pushCustomerContactFieldsRemote(
    String customerId, {
    String? phone,
    String? trn,
  }) async {}

  @override
  Future<void> saveCustomers(List<Customer> customers) async {}

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {}


  @override
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(Item item) async => (item: item, offlineFallback: false);

  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(Customer customer) async => (customer: customer, offlineFallback: false);
  @override
  Future<CustomerLedger> fetchCustomerLedger(
    String customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) => throw UnimplementedError();

  @override
  Customer? getCustomerById(String id) => null;

  @override
  Future<void> pushCustomerGpsRemote(
    String customerId,
    double latitude,
    double longitude,
  ) => throw UnimplementedError();
}

void main() {
  group('AsyncSearchBloc', () {
    late FakeSalesRepository repo;
    late AsyncSearchBloc bloc;

    const appleCustomer = Customer(
      id: 'cust_1',
      name: 'Apple Shop',
      companyName: 'Apple Retail',
      email: '',
      phone: '555-0100',
      address: '',
      outstandingBalance: 0,
      creditLimit: 0,
      routeId: 'route_1',
      sequence: 1,
    );

    const bananaCustomer = Customer(
      id: 'cust_2',
      name: 'Banana Mart',
      companyName: 'Banana Co',
      email: '',
      phone: '555-0200',
      address: '',
      outstandingBalance: 0,
      creditLimit: 0,
      routeId: 'route_1',
      sequence: 2,
    );

    const milkItem = Item(
      id: 'item_1',
      name: 'Milk',
      sku: 'MLK-001',
      rate: 10,
      stock: 50,
      description: '',
      taxName: 'No Tax',
      taxPercentage: 0,
    );

    const breadItem = Item(
      id: 'item_2',
      name: 'Bread',
      sku: 'BRD-001',
      rate: 5,
      stock: 20,
      description: '',
      taxName: 'No Tax',
      taxPercentage: 0,
    );

    setUp(() {
      repo = FakeSalesRepository()
        ..customers = [appleCustomer, bananaCustomer]
        ..items = [milkItem, breadItem];
      bloc = AsyncSearchBloc(customerRepository: repo, itemRepository: repo);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('initial state is idle with customers search type', () {
      expect(bloc.state.searchType, SearchType.customers);
      expect(bloc.state.status, AsyncSearchStatus.idle);
      expect(bloc.state.query, '');
      expect(bloc.state.customerResults, isEmpty);
      expect(bloc.state.itemResults, isEmpty);
    });

    test('empty query resets to idle', () async {
      bloc.add(const SearchQueryChanged('apple'));
      await bloc.stream.firstWhere((s) => s.status == AsyncSearchStatus.loading);

      bloc.add(const SearchQueryChanged(''));
      final idle = await bloc.stream.firstWhere(
        (s) => s.status == AsyncSearchStatus.idle,
      );

      expect(idle.query, '');
      expect(idle.customerResults, isEmpty);
    });

    test('debounced customer search returns matching results', () async {
      bloc.add(const SearchQueryChanged('apple'));

      final loading = await bloc.stream.firstWhere(
        (s) => s.status == AsyncSearchStatus.loading,
      );
      expect(loading.query, 'apple');

      final results = await bloc.stream.firstWhere(
        (s) => s.status == AsyncSearchStatus.results,
      );

      expect(results.customerResults.length, 1);
      expect(results.customerResults.first.name, 'Apple Shop');
    });

    test('debounced search with no matches emits empty status', () async {
      bloc.add(const SearchQueryChanged('zzzz'));

      final empty = await bloc.stream.firstWhere(
        (s) => s.status == AsyncSearchStatus.empty,
      );

      expect(empty.customerResults, isEmpty);
      expect(empty.query, 'zzzz');
    });

    test('rapid typing only applies the last debounced query', () async {
      bloc.add(const SearchQueryChanged('apple'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      bloc.add(const SearchQueryChanged('banana'));

      final results = await bloc.stream.firstWhere(
        (s) =>
            s.status == AsyncSearchStatus.results &&
            s.customerResults.isNotEmpty,
      );

      expect(results.customerResults.length, 1);
      expect(results.customerResults.first.name, 'Banana Mart');
      expect(
        results.customerResults.any((c) => c.name == 'Apple Shop'),
        isFalse,
      );
    });

    test('search type change clears query and results', () async {
      bloc.add(const SearchQueryChanged('apple'));
      await bloc.stream.firstWhere((s) => s.status == AsyncSearchStatus.results);

      bloc.add(const SearchTypeChanged(SearchType.items));

      final reset = await bloc.stream.firstWhere(
        (s) => s.searchType == SearchType.items && s.status == AsyncSearchStatus.idle,
      );

      expect(reset.query, '');
      expect(reset.customerResults, isEmpty);
      expect(reset.itemResults, isEmpty);
    });

    test('item search matches name and sku', () async {
      bloc.add(const SearchTypeChanged(SearchType.items));
      await bloc.stream.firstWhere((s) => s.searchType == SearchType.items);

      bloc.add(const SearchQueryChanged('BRD'));

      final results = await bloc.stream.firstWhere(
        (s) => s.status == AsyncSearchStatus.results,
      );

      expect(results.itemResults.length, 1);
      expect(results.itemResults.first.sku, 'BRD-001');
    });

    test('SearchCleared resets to idle', () async {
      bloc.add(const SearchQueryChanged('apple'));
      await bloc.stream.firstWhere((s) => s.status == AsyncSearchStatus.results);

      bloc.add(const SearchCleared());

      final cleared = await bloc.stream.firstWhere(
        (s) => s.status == AsyncSearchStatus.idle,
      );

      expect(cleared.query, '');
      expect(cleared.customerResults, isEmpty);
    });

    test('customer phone match uses raw query casing', () async {
      repo.customers = [
        appleCustomer.copyWith(phone: '555-APPLE'),
      ];

      bloc.add(const SearchQueryChanged('APPLE'));

      final results = await bloc.stream.firstWhere(
        (s) => s.status == AsyncSearchStatus.results,
      );

      expect(results.customerResults.length, 1);
    });
  });
}