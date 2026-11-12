import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/organization_model.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/ui/core/cubit/organization_cubit.dart';
import 'package:van_sales/ui/core/extensions/org_context_extension.dart';
import 'package:van_sales/domain/utils/money_math.dart';
import 'package:van_sales/ui/core/utils/currency.dart';
import 'package:van_sales/ui/core/widgets/app_currency_text.dart';

class _FakeHiveDb extends Fake implements HiveDatabaseService {
  OrganizationModel? org;
  @override
  OrganizationModel? getOrganization() => org;
}

void main() {
  group('formatCurrency utility', () {
    test('formatCurrency with no decimals follows MoneyScale (default 2)', () {
      expect(formatCurrency(12.3456, 'KWD'), 'KWD12.35');
      expect(formatCurrency(5.1, 'KD '), 'KD 5.10');
      expect(formatMoneyNumber(5.1), '5.10');
      MoneyScale.use(3);
      expect(formatCurrency(12.3456, 'KWD'), 'KWD12.346');
      expect(formatMoneyNumber(12.3456), '12.346');
      MoneyScale.use(2);
    });

    test('formatCurrency defaults to 2 decimals when symbol is AED', () {
      expect(formatCurrency(12.3456, 'AED'), 'AED12.35');
      expect(formatCurrency(5.1, 'AED '), 'AED 5.10');
    });

    test('formatCurrency respects explicit decimals parameter', () {
      expect(formatCurrency(12.3456, 'KWD', decimals: 2), 'KWD12.35');
      expect(formatCurrency(12.3456, 'AED', decimals: 4), 'AED12.3456');
      expect(formatCurrency(12.3456, 'AED', decimals: 0), 'AED12');
    });
  });

  group('OrganizationCubit currency decimal places and formatCurrency', () {
    test('defaults to 2 decimals when no organization is cached', () {
      final db = _FakeHiveDb()..org = null;
      final cubit = OrganizationCubit(db);

      expect(cubit.currencyDecimalPlaces, 2);
      expect(cubit.currencySymbol, '');
      expect(cubit.formatCurrency(25.5), '25.50');
    });

    test('uses ISO 3 decimals when KWD JSON omits precision', () {
      final db = _FakeHiveDb()
        ..org = OrganizationModel.fromJson({
          'organization_id': 'kwd-1',
          'name': 'Kuwait Branch',
          'currency_code': 'KWD',
          'currency_symbol': 'KD ',
          'fiscal_year_start_month': 'january',
          'time_zone': 'Asia/Kuwait',
        });
      final cubit = OrganizationCubit(db);

      expect(cubit.currencyDecimalPlaces, 3);
      expect(cubit.currencySymbol, 'KD ');
      expect(cubit.formatCurrency(25.5), 'KD 25.500');
      expect(cubit.formatCurrency(25.5556), 'KD 25.556');
    });

    test('uses explicit currencyDecimalPlaces from the organization', () {
      final db = _FakeHiveDb()
        ..org = const OrganizationModel(
          id: 'kwd-1',
          name: 'Kuwait Branch',
          currencyCode: 'KWD',
          currencySymbol: 'KD ',
          fiscalYearStartMonth: 'january',
          timeZone: 'Asia/Kuwait',
          currencyDecimalPlaces: 3,
        );
      final cubit = OrganizationCubit(db);

      expect(cubit.currencyDecimalPlaces, 3);
      expect(cubit.formatCurrency(25.5), 'KD 25.500');
      expect(cubit.formatCurrency(25.5556), 'KD 25.556');
    });

    test('returns 2 decimals when organization currency is AED', () {
      final db = _FakeHiveDb()
        ..org = const OrganizationModel(
          id: 'aed-1',
          name: 'Dubai Branch',
          currencyCode: 'AED',
          currencySymbol: 'AED ',
          fiscalYearStartMonth: 'january',
          timeZone: 'Asia/Dubai',
        );
      final cubit = OrganizationCubit(db);

      expect(cubit.currencyDecimalPlaces, 2);
      expect(cubit.currencySymbol, 'AED ');
      expect(cubit.formatCurrency(25.5), 'AED 25.50');
    });
  });

  group('AppCurrencyText widget', () {
    testWidgets('renders fallback formatting without OrganizationCubit in tree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCurrencyText(amount: 45.678),
          ),
        ),
      );

      expect(find.text('45.68'), findsOneWidget);
    });

    testWidgets('reads KWD symbol and 3 decimals from OrganizationCubit',
        (tester) async {
      final db = _FakeHiveDb()
        ..org = const OrganizationModel(
          id: 'kwd-1',
          name: 'Kuwait Org',
          currencyCode: 'KWD',
          currencySymbol: 'KD ',
          fiscalYearStartMonth: 'january',
          timeZone: 'Asia/Kuwait',
          currencyDecimalPlaces: 3,
        );
      final cubit = OrganizationCubit(db);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: AppCurrencyText(amount: 12.3456),
            ),
          ),
        ),
      );

      expect(find.text('KD 12.346'), findsOneWidget);
    });

    testWidgets('reads AED symbol and 2 decimals from OrganizationCubit',
        (tester) async {
      final db = _FakeHiveDb()
        ..org = const OrganizationModel(
          id: 'aed-1',
          name: 'UAE Org',
          currencyCode: 'AED',
          currencySymbol: 'AED ',
          fiscalYearStartMonth: 'january',
          timeZone: 'Asia/Dubai',
        );
      final cubit = OrganizationCubit(db);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: AppCurrencyText(amount: 12.3456),
            ),
          ),
        ),
      );

      expect(find.text('AED 12.35'), findsOneWidget);
    });

    testWidgets('supports showSymbol: false, prefix, suffix, and explicit overrides',
        (tester) async {
      final db = _FakeHiveDb()
        ..org = const OrganizationModel(
          id: 'kwd-1',
          name: 'Kuwait Org',
          currencyCode: 'KWD',
          currencySymbol: 'KD ',
          fiscalYearStartMonth: 'january',
          timeZone: 'Asia/Kuwait',
          currencyDecimalPlaces: 3,
        );
      final cubit = OrganizationCubit(db);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: Column(
                children: [
                  AppCurrencyText(
                    amount: 50.123,
                    showSymbol: false,
                  ),
                  AppCurrencyText(
                    amount: 100.5,
                    prefix: 'Total Due: ',
                    suffix: ' (net)',
                  ),
                  AppCurrencyText(
                    amount: 75.12345,
                    decimals: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // showSymbol: false with KWD 3 decimals -> 50.123
      expect(find.text('50.123'), findsOneWidget);
      // prefix and suffix
      expect(find.text('Total Due: KD 100.500 (net)'), findsOneWidget);
      // explicit decimals override
      expect(find.text('KD 75.1235'), findsOneWidget);
    });

    testWidgets('context.formatCurrency extension formats properly',
        (tester) async {
      final db = _FakeHiveDb()
        ..org = const OrganizationModel(
          id: 'kwd-1',
          name: 'Kuwait Org',
          currencyCode: 'KWD',
          currencySymbol: 'KD ',
          fiscalYearStartMonth: 'january',
          timeZone: 'Asia/Kuwait',
          currencyDecimalPlaces: 3,
        );
      final cubit = OrganizationCubit(db);

      late String formattedFromContext;

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: Builder(
              builder: (context) {
                formattedFromContext = context.formatCurrency(88.9);
                return Text(formattedFromContext);
              },
            ),
          ),
        ),
      );

      expect(formattedFromContext, 'KD 88.900');
      expect(find.text('KD 88.900'), findsOneWidget);
    });
  });
}
