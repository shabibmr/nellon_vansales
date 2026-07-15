import 'package:dio/dio.dart';
import 'package:van_sales/data/models/item_model.dart';
import 'package:van_sales/data/models/customer_model.dart';

Future<List<Map<String, dynamic>>> fetchAllPages(
  Dio dio,
  String path,
  Map<String, dynamic> baseParams,
) async {
  final all = <Map<String, dynamic>>[];
  var page = 1;
  while (true) {
    final params = <String, dynamic>{
      ...baseParams,
      'per_page': 200,
      'page': page,
    };
    print('Fetching page $page of $path...');
    final response = await dio.get(path, queryParameters: params);
    if (response.statusCode != 200) {
      throw Exception('GET $path failed: ${response.statusCode}');
    }
    final data = response.data as Map<String, dynamic>;
    List<dynamic>? listVal;
    for (final v in data.values) {
      if (v is List) {
        listVal = v;
        break;
      }
    }
    if (listVal != null) {
      all.addAll(listVal.map((e) => Map<String, dynamic>.from(e as Map)));
    }
    final pageContext = data['page_context'] as Map?;
    final hasMore = pageContext?['has_more_page'] == true;
    if (!hasMore) break;
    page += 1;
  }
  return all;
}

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

      // 1. All Items
      try {
        final list = await fetchAllPages(dio, '/items', {});
        print('Total items fetched: ${list.length}');
        for (var i = 0; i < list.length; i++) {
          try {
            ItemModel.fromJson(Map<String, dynamic>.from(list[i]));
          } catch (e) {
            print('Fail parsing item at index $i: ${list[i]}');
            rethrow;
          }
        }
        print('All items parsed successfully.');
      } catch (e, stack) {
        print('ERROR on items: $e\n$stack');
      }

      // 2. All Customers
      try {
        final list = await fetchAllPages(dio, '/contacts', {'contact_type': 'customer'});
        print('Total customers fetched: ${list.length}');
        for (var i = 0; i < list.length; i++) {
          try {
            CustomerModel.fromJson(Map<String, dynamic>.from(list[i]));
          } catch (e) {
            print('Fail parsing customer at index $i: ${list[i]}');
            rethrow;
          }
        }
        print('All customers parsed successfully.');
      } catch (e, stack) {
        print('ERROR on customers: $e\n$stack');
      }
    } else {
      print('Failed refreshing access token: ${tokenResponse.statusCode}');
    }
  } catch (e) {
    print('ERROR: $e');
  }
}
