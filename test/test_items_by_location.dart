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
  const warehouseId = '3331482000177581063';

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

      print('\n=== Fetching Items with location_id=$warehouseId ===');
      try {
        final response = await dio.get('/items', queryParameters: {'location_id': warehouseId});
        print('SUCCESS! statusCode=${response.statusCode}');
        print('Items count: ${(response.data['items'] as List).length}');
      } on DioException catch (de) {
        print('DioException checking /items by location: ${de.response?.statusCode} - ${de.response?.data}');
      } catch (e) {
        print('Error checking /items: $e');
      }
    } else {
      print('Failed refreshing access token: ${tokenResponse.statusCode}');
    }
  } catch (e) {
    print('ERROR: $e');
  }
}
