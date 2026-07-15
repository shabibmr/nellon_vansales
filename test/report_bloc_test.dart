import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/features/reports/bloc/report_bloc.dart';
import 'package:van_sales/ui/features/reports/bloc/report_event.dart';

void main() {
  group('ReportBloc Tests', () {
    late List<String> localCache;
    late List<String> remoteLive;
    late bool remoteShouldFail;
    late int remoteCallCount;

    setUp(() {
      localCache = ['cached_row_1', 'cached_row_2'];
      remoteLive = ['live_row_1', 'live_row_2', 'live_row_3'];
      remoteShouldFail = false;
      remoteCallCount = 0;
    });

    ReportBloc<String> createBloc({Duration? fetchDelay}) {
      return ReportBloc<String>(
        getLocal: () => localCache,
        fetchRemote: () async {
          if (fetchDelay != null) {
            await Future.delayed(fetchDelay);
          }
          remoteCallCount++;
          if (remoteShouldFail) {
            throw Exception('Network failed');
          }
          return remoteLive;
        },
        initialSortField: 'name',
        initialSortAscending: true,
      );
    }

    test('Initial state seeds with cached rows and isLoading = true, then refreshes successfully', () async {
      final bloc = createBloc();

      // Initial state (before any events finish processing)
      expect(bloc.state.isLoading, true);
      expect(bloc.state.rows, localCache);
      expect(bloc.state.sortField, 'name');
      expect(bloc.state.sortAscending, true);
      expect(bloc.state.isLiveData, false);
      expect(bloc.state.error, isNull);
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      expect(bloc.state.startDate, today);
      expect(bloc.state.endDate, today);

      // Wait for the automatic RefreshReport to complete
      await bloc.stream.firstWhere((state) => !state.isLoading);

      expect(bloc.state.isLoading, false);
      expect(bloc.state.rows, remoteLive);
      expect(bloc.state.isLiveData, true);
      expect(bloc.state.error, isNull);
      expect(remoteCallCount, 1);

      await bloc.close();
    });

    test('On remote fetch failure, keeps cached rows and sets error message', () async {
      remoteShouldFail = true;
      final bloc = createBloc();

      // Wait for the automatic RefreshReport to fail
      await bloc.stream.firstWhere((state) => !state.isLoading);

      expect(bloc.state.isLoading, false);
      // Keeps cache
      expect(bloc.state.rows, localCache);
      expect(bloc.state.isLiveData, false);
      expect(bloc.state.error, contains('Network failed'));
      expect(remoteCallCount, 1);

      await bloc.close();
    });

    test('Refresh while already loading is a no-op (reentrancy guard)', () async {
      final bloc = createBloc(fetchDelay: const Duration(milliseconds: 50));

      // Fire another refresh immediately while the initial one is loading
      bloc.add(const RefreshReport());
      bloc.add(const RefreshReport());

      await bloc.stream.firstWhere((state) => !state.isLoading);

      // Should only have called remote once
      expect(remoteCallCount, 1);

      await bloc.close();
    });

    test('SetDateRange updates state date filters without touching rows source', () async {
      final bloc = createBloc();
      await bloc.stream.firstWhere((state) => !state.isLoading);

      final start = DateTime(2026, 7, 1);
      final end = DateTime(2026, 7, 15);

      final future = bloc.stream.first;
      bloc.add(SetDateRange(start, end));
      final nextState = await future;

      expect(nextState.startDate, start);
      expect(nextState.endDate, end);
      expect(nextState.rows, remoteLive); // unchanged
      expect(remoteCallCount, 1); // no extra fetch

      // Clear dates
      final future2 = bloc.stream.first;
      bloc.add(const SetDateRange(null, null));
      final clearedState = await future2;

      expect(clearedState.startDate, isNull);
      expect(clearedState.endDate, isNull);

      await bloc.close();
    });

    test('SetSort updates sort state', () async {
      final bloc = createBloc();
      await bloc.stream.firstWhere((state) => !state.isLoading);

      // Set new field: sortField should change and sortAscending should default to true (or what we set)
      var future = bloc.stream.first;
      bloc.add(const SetSort('qty'));
      var nextState = await future;

      expect(nextState.sortField, 'qty');
      expect(nextState.sortAscending, true);

      // Toggling same field: sortAscending flips to false
      future = bloc.stream.first;
      bloc.add(const SetSort('qty'));
      nextState = await future;

      expect(nextState.sortField, 'qty');
      expect(nextState.sortAscending, false);

      // Toggling again: flips back to true
      future = bloc.stream.first;
      bloc.add(const SetSort('qty'));
      nextState = await future;

      expect(nextState.sortField, 'qty');
      expect(nextState.sortAscending, true);

      // Set different ascending directly
      future = bloc.stream.first;
      bloc.add(const SetSort('qty', ascending: false));
      nextState = await future;

      expect(nextState.sortField, 'qty');
      expect(nextState.sortAscending, false);

      await bloc.close();
    });
  });
}
