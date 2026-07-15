import 'package:dio/dio.dart';
import 'package:van_sales/data/models/organization_model.dart';
import 'package:van_sales/data/models/warehouse_model.dart';
import 'package:van_sales/data/models/payment_account_model.dart';
import 'package:van_sales/data/models/tax_model.dart';
import 'package:van_sales/data/models/expense_account_model.dart';
import 'package:van_sales/data/models/item_model.dart';
import 'package:van_sales/data/models/customer_model.dart';
import 'package:van_sales/data/models/salesperson_model.dart';

void main() async {
  final dio = Dio();

  const accountsUrl = 'https://accounts.zoho.com/oauth/v2/token';
  const apiUrl = 'https://www.zohoapis.com/books/v3';

  const clientId = '1000.45EI6FPO004OW9W6BTB7TUJ9L0C0YP';
  const clientSecret = '1d829f7ee3e1eb7debe6ed370ccc87ab45e7b36103';
  const organizationId = '783019958';
  const refreshToken =
      '1000.ccb7c895a473ba5569c55565c0aed87d.c2f3a5530356193d39a19c511efed856';

  print('=== STEP 1: Refreshing Access Token ===');
  try {
    final tokenResponse = await Dio().post(
      accountsUrl,
      queryParameters: {
        'refresh_token': refreshToken,
        'client_id': clientId,
        'client_secret': clientSecret,
        'grant_type': 'refresh_token',
      },
    );

    if (tokenResponse.statusCode == 200) {
      final accessToken = tokenResponse.data['access_token'];
      print('Access Token obtained.');

      dio.options.baseUrl = apiUrl;
      dio.options.headers['Authorization'] = 'Zoho-oauthtoken $accessToken';
      dio.options.headers['JSONString'] = 'true';
      dio.options.queryParameters['organization_id'] = organizationId;

      // 1. Organization
      try {
        final res = await dio.get('/organizations/$organizationId');
        final model = OrganizationModel.fromJson(res.data['organization']);
        print('OrganizationModel parsed successfully: id=${model.id}, name=${model.name}');
      } catch (e, stack) {
        print('ERROR parsing OrganizationModel: $e\n$stack');
      }

      // 2. Warehouses
      try {
        final res = await dio.get('/locations');
        final list = (res.data['locations'] as List? ?? []);
        for (var i = 0; i < list.length; i++) {
          final model = WarehouseModel.fromJson(Map<String, dynamic>.from(list[i]));
        }
        print('WarehouseModel parsed successfully for ${list.length} locations');
      } catch (e, stack) {
        print('ERROR parsing WarehouseModel: $e\n$stack');
      }

      // 3. Payment Accounts
      try {
        final res = await dio.get('/bankaccounts');
        final list = (res.data['bankaccounts'] as List? ?? []);
        for (var i = 0; i < list.length; i++) {
          final model = PaymentAccountModel.fromJson(Map<String, dynamic>.from(list[i]));
        }
        print('PaymentAccountModel parsed successfully for ${list.length} bankaccounts');
      } catch (e, stack) {
        print('ERROR parsing PaymentAccountModel: $e\n$stack');
      }

      // 4. Taxes
      try {
        final res = await dio.get('/settings/taxes');
        final list = (res.data['taxes'] as List? ?? []);
        for (var i = 0; i < list.length; i++) {
          final model = TaxModel.fromJson(Map<String, dynamic>.from(list[i]));
        }
        print('TaxModel parsed successfully for ${list.length} taxes');
      } catch (e, stack) {
        print('ERROR parsing TaxModel: $e\n$stack');
      }

      // 5. Expense Accounts
      try {
        final res = await dio.get('/chartofaccounts', queryParameters: {'filter_by': 'AccountType.Expense'});
        final list = (res.data['chartofaccounts'] as List? ?? []);
        for (var i = 0; i < list.length; i++) {
          final model = ExpenseAccountModel.fromJson(Map<String, dynamic>.from(list[i]));
        }
        print('ExpenseAccountModel parsed successfully for ${list.length} accounts');
      } catch (e, stack) {
        print('ERROR parsing ExpenseAccountModel: $e\n$stack');
      }

      // 6. Items
      try {
        final res = await dio.get('/items');
        final list = (res.data['items'] as List? ?? []);
        for (var i = 0; i < list.length; i++) {
          final model = ItemModel.fromJson(Map<String, dynamic>.from(list[i]));
        }
        print('ItemModel parsed successfully for ${list.length} items');
      } catch (e, stack) {
        print('ERROR parsing ItemModel: $e\n$stack');
      }

      // 7. Customers
      try {
        final res = await dio.get('/contacts', queryParameters: {'contact_type': 'customer', 'per_page': 200});
        final list = (res.data['contacts'] as List? ?? []);
        for (var i = 0; i < list.length; i++) {
          final raw = Map<String, dynamic>.from(list[i]);
          try {
            final model = CustomerModel.fromJson(raw);
          } catch (e) {
            print('Fail on customer index $i: ID=${raw['contact_id']}, Name=${raw['contact_name']}, limit=${raw['customer_credit_limit']} (${raw['customer_credit_limit']?.runtimeType}), credit_limit=${raw['credit_limit']} (${raw['credit_limit']?.runtimeType})');
            rethrow;
          }
        }
        print('CustomerModel parsed successfully for ${list.length} customers');
      } catch (e, stack) {
        print('ERROR parsing CustomerModel: $e\n$stack');
      }

      // 8. Salespersons
      try {
        final res = await dio.get('/salespersons');
        final list = (res.data['data'] ?? res.data['salespersons'] ?? []) as List;
        for (var i = 0; i < list.length; i++) {
          final model = SalespersonModel.fromJson(Map<String, dynamic>.from(list[i]));
        }
        print('SalespersonModel parsed successfully for ${list.length} salespersons');
      } catch (e, stack) {
        print('ERROR parsing SalespersonModel: $e\n$stack');
      }
    } else {
      print('Failed refreshing access token: ${tokenResponse.statusCode}');
    }
  } catch (e) {
    print('ERROR: $e');
  }
}
