import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  
  const accountsUrl = 'https://accounts.zoho.com/oauth/v2/token';
  const apiUrl = 'https://www.zohoapis.com/books/v3';
  
  const clientId = '1000.45EI6FPO004OW9W6BTB7TUJ9L0C0YP';
  const clientSecret = '1d829f7ee3e1eb7debe6ed370ccc87ab45e7b36103';
  const organizationId = '783019958';
  const refreshToken = '1000.ccb7c895a473ba5569c55565c0aed87d.c2f3a5530356193d39a19c511efed856';

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
      print('Access Token obtained: ${accessToken.substring(0, 10)}... (truncated)');

      print('\n=== STEP 2: Fetching Organization Details ===');
      dio.options.baseUrl = apiUrl;
      dio.options.headers['Authorization'] = 'Zoho-oauthtoken $accessToken';
      dio.options.headers['JSONString'] = 'true';
      dio.options.queryParameters['organization_id'] = organizationId;

      final orgResponse = await dio.get('/organizations/$organizationId');
      
      if (orgResponse.statusCode == 200) {
        final org = orgResponse.data['organization'];
        print('SUCCESS! Retrieved Organization Info:');
        print('-----------------------------------------');
        print('Organization ID  : ${org['organization_id']}');
        print('Name             : ${org['name']}');
        print('Currency Code    : ${org['currency_code']}');
        print('Currency Symbol  : ${org['currency_symbol']}');
        print('Time Zone        : ${org['time_zone']}');
        print('Fiscal Year Start: ${org['fiscal_year_start_month']}');
        print('-----------------------------------------');
      } else {
        print('Failed fetching organization: ${orgResponse.statusCode} - ${orgResponse.statusMessage}');
      }
    } else {
      print('Failed refreshing access token: ${tokenResponse.statusCode} - ${tokenResponse.statusMessage}');
    }
  } catch (e) {
    print('ERROR encountered: $e');
  }
}
