import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/ui/features/sync/bloc/masters_sync_state.dart';
import 'package:van_sales/ui/features/sync/widgets/masters_sync_card_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpList(WidgetTester tester, MastersSyncState state) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MastersSyncCardList(
              state: state,
              isDark: false,
              syncedCount: state.syncedTypes.length,
              totalCount: MasterType.values.length,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows Hive record counts after a type has been synced',
      (tester) async {
    await pumpList(
      tester,
      MastersSyncState(
        syncedTypes: {MasterType.customers, MasterType.items},
        recordCounts: {
          MasterType.customers: 12,
          MasterType.items: 1,
        },
      ),
    );

    expect(find.text('12 records'), findsOneWidget);
    expect(find.text('1 record'), findsOneWidget);
    expect(find.text('Contacts, balances & credit limits'), findsNothing);
  });

  testWidgets('shows zero Hive records after an empty successful sync',
      (tester) async {
    await pumpList(
      tester,
      const MastersSyncState(
        syncedTypes: {MasterType.taxes},
        recordCounts: {MasterType.taxes: 0},
      ),
    );

    expect(find.text('0 records'), findsOneWidget);
  });

  testWidgets('keeps the type description when no Hive count is available',
      (tester) async {
    await pumpList(tester, const MastersSyncState());

    expect(find.text('Contacts, balances & credit limits'), findsOneWidget);
    expect(find.textContaining('record'), findsNothing);
  });
}
