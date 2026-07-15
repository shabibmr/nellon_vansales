import 'package:dio/dio.dart';

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

      final endpoints = {
        'Organization': '/organizations/$organizationId',
        'Warehouses (Locations)': '/locations',
        'Payment Accounts': '/bankaccounts',
        'Taxes': '/settings/taxes',
        'Expense Accounts': '/chartofaccounts?filter_by=AccountType.Expense',
        'Items': '/items',
        'Customers': '/contacts?contact_type=customer',
        'Salespersons': '/salespersons',
        'Salesperson Location Mappings': '/cm_salesperson_location',
      };

      for (final entry in endpoints.entries) {
        print('\n=== Fetching ${entry.key} (${entry.value}) ===');
        try {
          final response = await dio.get(entry.value);
          print('SUCCESS [${response.statusCode}]');
          final data = response.data;
          if (data is Map) {
            print('Root keys: ${data.keys.toList()}');
            // Print some samples or specific nested keys
            for (final key in data.keys) {
              if (data[key] is List) {
                final list = data[key] as List;
                print('List "$key" length: ${list.length}');
                if (list.isNotEmpty) {
                  print('Sample item keys from "$key": ${list.first.keys.toList()}');
                  print('Sample item content: ${list.first}');
                }
              } else if (data[key] is Map) {
                print('Map "$key" keys: ${data[key].keys.toList()}');
              } else {
                print('Value "$key": ${data[key]}');
              }
            }
          } else {
            print('Response data is not a Map: $data');
          }
        } on DioException catch (de) {
          print('DioException checking ${entry.key}: ${de.response?.statusCode} - ${de.response?.data}');
        } catch (e) {
          print('Error checking ${entry.key}: $e');
        }
      }
    } else {
      print('Failed refreshing access token: ${tokenResponse.statusCode} - ${tokenResponse.statusMessage}');
    }
  } catch (e) {
    print('ERROR: $e');
  }
}
