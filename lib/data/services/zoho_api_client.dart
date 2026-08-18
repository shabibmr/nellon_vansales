import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'app_logger.dart';
import 'debug_file_logger.dart';
import 'error_classification.dart';
import 'firebase_telemetry.dart';
import 'hive_database_service.dart';
import 'sales_return_sync.dart';
import 'zoho_payload_mapper.dart';
import '../../domain/models/tax.dart';
import '../../domain/utils/json_read.dart';
import '../../domain/utils/server_config_rules.dart';

/// REST API Client that coordinates direct HTTPS calls to Zoho Books v3 APIs.
///
/// Payload shaping ([ZohoPayloadMapper], location inject, expense account
/// resolve) always runs, then `_dio.get/post/put` hits live Zoho. Callers
/// parse `response.data['contact'|'invoice'|…]`.
class ZohoApiClient {
  final Dio _dio = Dio();
  final HiveDatabaseService _dbService;

  // Zoho OAuth 2.0 credentials. Start empty; ServerConfigCubit injects
  // Firestore `server_config/zoho` (and the secure-storage cache) at runtime.
  final String _accountsUrl = 'https://accounts.zoho.com/oauth/v2/token';
  final String _apiUrl = 'https://www.zohoapis.com/books/v3';

  String _clientId = '';
  String _clientSecret = '';
  String _refreshToken = '';
  String _organizationId = '';

  /// True when client id, secret, and refresh token are all present.
  bool get hasCredentials =>
      _clientId.trim().isNotEmpty &&
      _clientSecret.trim().isNotEmpty &&
      _refreshToken.trim().isNotEmpty;

  /// When true, ignore the Hive access-token cache and refresh.
  bool _accessTokenInvalidated = false;

  /// Updates Zoho OAuth integration credentials on the fly (called upon loading server config).
  ///
  /// Empty values are ignored, keeping the current (working) values — an
  /// incomplete remote config must never wipe usable credentials.
  /// [organizationId] is optional and updated independently of the OAuth
  /// triple, since older Firestore docs won't carry it.
  ///
  /// Changing the OAuth triple drops the cached access token so a client
  /// rotation takes effect immediately, not after the previous token expires.
  void updateCredentials({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
    String organizationId = '',
  }) {
    final nextId = clientId.trim();
    final nextSecret = clientSecret.trim();
    final nextRefresh = refreshToken.trim();
    DebugFileLogger.log(
      '[ZohoApiClient] 🔑 updateCredentials called: '
      'clientId="$nextId", clientSecret="$nextSecret", '
      'refreshToken="$nextRefresh", organizationId="${organizationId.trim()}"',
    );
    if (nextId.isNotEmpty && nextSecret.isNotEmpty && nextRefresh.isNotEmpty) {
      final changed =
          nextId != _clientId ||
          nextSecret != _clientSecret ||
          nextRefresh != _refreshToken;
      _clientId = nextId;
      _clientSecret = nextSecret;
      _refreshToken = nextRefresh;
      DebugFileLogger.log(
        '[ZohoApiClient] ✅ OAuth triple ACCEPTED (changed=$changed).',
      );
      if (changed) {
        _accessTokenInvalidated = true;
        unawaited(_clearCachedAccessToken());
        DebugFileLogger.log(
          '[ZohoApiClient] ♻️ Credentials changed — cached access token invalidated and cleared.',
        );
      }
    } else {
      DebugFileLogger.log(
        '[ZohoApiClient] ⚠️ OAuth triple REJECTED (kept previous values) — '
        'clientId.isEmpty=${nextId.isEmpty}, '
        'clientSecret.isEmpty=${nextSecret.isEmpty}, '
        'refreshToken.isEmpty=${nextRefresh.isEmpty}',
      );
    }
    if (organizationId.trim().isNotEmpty) {
      _organizationId = organizationId.trim();
      DebugFileLogger.log('[ZohoApiClient] 🏢 organizationId updated: "$_organizationId"');
    } else {
      DebugFileLogger.log('[ZohoApiClient] ⚠️ organizationId empty — kept previous value "$_organizationId"');
    }
  }

  Future<void> _clearCachedAccessToken() async {
    await _dbService.setOauthAccessToken(null);
    await _dbService.setOauthTokenExpiry(null);
  }

  /// Instantiates a new [ZohoApiClient].
  ///
  /// Configures connect/receive timeouts and an auth interceptor that
  /// attaches the OAuth header and retries on 401.
  ZohoApiClient({
    required HiveDatabaseService dbService, // ignore: prefer_initializing_formals
  }) : _dbService = dbService {
    _dio.options.baseUrl = _apiUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);

    // Added first so it runs *after* the 401-retry interceptor on errors.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException error, handler) {
          DebugFileLogger.log(
            '[ZohoApiClient] ❌ Telemetry-interceptor error: '
            'url="${error.requestOptions.baseUrl}${error.requestOptions.path}", '
            'statusCode=${error.response?.statusCode}, '
            'responseData=${error.response?.data}, '
            'error=${error.error}',
          );
          unawaited(FirebaseTelemetry.reportZohoApiFailure(error));
          handler.next(error);
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final String accessToken;
          final tokenSourceBefore = _accessTokenInvalidated
              ? 'forced-refresh'
              : (_dbService.oauthAccessToken == null
                    ? 'no-cache'
                    : 'cache-or-refresh');
          try {
            accessToken = await _getOrRefreshAccessToken();
          } on Exception catch (e) {
            DebugFileLogger.log(
              '[ZohoApiClient] ❌ onRequest: failed to obtain access token for '
              '"${options.baseUrl}${options.path}": $e',
            );
            // Fail the request with the real auth error instead of sending
            // an unauthenticated call that dies as an opaque 401.
            return handler.reject(
              DioException(
                requestOptions: options,
                error: e,
                message: 'Zoho authentication failed: $e',
              ),
            );
          }
          options.headers['Authorization'] = 'Zoho-oauthtoken $accessToken';
          options.headers['JSONString'] = 'true';
          options.queryParameters['organization_id'] = _organizationId;
          DebugFileLogger.log(
            '[ZohoApiClient] 🌐 Outgoing request: '
            '${options.method} "${options.baseUrl}${options.path}", '
            'queryParameters=${options.queryParameters}, '
            'tokenSource=$tokenSourceBefore, '
            'accessTokenLength=${accessToken.length}',
          );
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            DebugFileLogger.log(
              '[ZohoApiClient] 🔁 401 received for '
              '"${error.requestOptions.baseUrl}${error.requestOptions.path}" '
              '— forcing access-token refresh and retrying.',
            );
            // Force refresh token on 401 Unauthorized
            final String newAccessToken;
            try {
              newAccessToken = await _refreshAccessToken(force: true);
            } on Exception catch (e) {
              DebugFileLogger.log(
                '[ZohoApiClient] ❌ 401-retry: forced refresh FAILED: $e — surfacing original 401.',
              );
              // Refresh failed — surface the original 401.
              return handler.next(error);
            }
            final requestOptions = error.requestOptions;
            requestOptions.headers['Authorization'] =
                'Zoho-oauthtoken $newAccessToken';

            // Retry the original request
            try {
              final response = await _dio.fetch<dynamic>(requestOptions);
              DebugFileLogger.log(
                '[ZohoApiClient] ✅ 401-retry: retried '
                '"${requestOptions.baseUrl}${requestOptions.path}" succeeded '
                'with statusCode=${response.statusCode}.',
              );
              return handler.resolve(response);
            } on Exception catch (e) {
              DebugFileLogger.log(
                '[ZohoApiClient] ❌ 401-retry: retried request FAILED again: $e',
              );
              return handler.next(error);
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  // --- OAuth 2.0 Handlers ---

  /// Fetches the cached OAuth access token or triggers a refresh workflow if expired.
  ///
  /// Throws if the refresh workflow fails (see [_refreshAccessToken]).
  Future<String> _getOrRefreshAccessToken() async {
    if (!hasCredentials) {
      DebugFileLogger.log(
        '[ZohoApiClient] ❌ _getOrRefreshAccessToken: hasCredentials=false '
        '(clientId.isEmpty=${_clientId.isEmpty}, '
        'clientSecret.isEmpty=${_clientSecret.isEmpty}, '
        'refreshToken.isEmpty=${_refreshToken.isEmpty}) — throwing ZohoNotConfiguredException.',
      );
      throw const ZohoNotConfiguredException();
    }

    if (!_accessTokenInvalidated) {
      final cachedToken = _dbService.oauthAccessToken;
      final expiryMillis = _dbService.oauthTokenExpiry;

      if (cachedToken != null && expiryMillis != null) {
        final nowMillis = DateTime.now().millisecondsSinceEpoch;
        // Use a 60-second buffer to ensure the token doesn't expire mid-request
        if (nowMillis < (expiryMillis - 60000)) {
          DebugFileLogger.log(
            '[ZohoApiClient] 💾 _getOrRefreshAccessToken: using CACHED token, '
            'expiresInMs=${expiryMillis - nowMillis}.',
          );
          return cachedToken;
        }
        DebugFileLogger.log(
          '[ZohoApiClient] ⏰ _getOrRefreshAccessToken: cached token EXPIRED '
          '(nowMillis=$nowMillis, expiryMillis=$expiryMillis) — refreshing.',
        );
      } else {
        DebugFileLogger.log(
          '[ZohoApiClient] 🚫 _getOrRefreshAccessToken: no cached token '
          '(cachedToken==null=${cachedToken == null}, expiryMillis==null=${expiryMillis == null}) — refreshing.',
        );
      }
    } else {
      DebugFileLogger.log(
        '[ZohoApiClient] ♻️ _getOrRefreshAccessToken: token INVALIDATED — forcing refresh.',
      );
    }

    return _refreshAccessToken();
  }

  /// Standard OAuth refresh execution block that obtains a fresh access token from Zoho Accounts.
  ///
  /// Throws an [Exception] describing the failure (bad credentials, revoked
  /// refresh token, network error) instead of silently returning null, so
  /// callers — e.g. the Masters Sync page — can show the real cause rather
  /// than a generic fetch failure.
  Future<String> _refreshAccessToken({bool force = false}) async {
    if (!hasCredentials) {
      DebugFileLogger.log(
        '[ZohoApiClient] ❌ _refreshAccessToken: hasCredentials=false — throwing ZohoNotConfiguredException.',
      );
      throw const ZohoNotConfiguredException();
    }
    final refreshToken = _refreshToken;
    final requestQueryParams = {
      'refresh_token': refreshToken,
      'client_id': _clientId,
      'client_secret': _clientSecret,
      'grant_type': 'refresh_token',
    };
    DebugFileLogger.log(
      '[ZohoApiClient] 📤 _refreshAccessToken: POST "$_accountsUrl" (force=$force), '
      'queryParameters=$requestQueryParams',
    );
    try {
      // Form body (not query string) — same exchange the rest of the app
      // uses after Firestore/secure-storage injects client id, secret, and
      // refresh token into [_refreshToken].
      final response = await Dio().post<dynamic>(
        _accountsUrl,
        data: requestQueryParams,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      DebugFileLogger.log(
        '[ZohoApiClient] 📥 _refreshAccessToken: response statusCode=${response.statusCode}, '
        'body=${response.data}',
      );
      final newAccessToken = response.statusCode == 200
          ? response.data['access_token'] as String?
          : null;
      if (newAccessToken == null) {
        // Zoho returns 200 with an `error` body (e.g. "invalid_code") for
        // bad refresh tokens, so a missing access_token is also a failure.
        DebugFileLogger.log(
          '[ZohoApiClient] ❌ _refreshAccessToken: no access_token in response — '
          'HTTP ${response.statusCode}: ${response.data}',
        );
        throw Exception(
          'HTTP ${response.statusCode}: ${response.data}',
        );
      }

      final expiresInSeconds = response.data['expires_in'] as int? ?? 3600;
      final expiryMillis =
          DateTime.now().millisecondsSinceEpoch + (expiresInSeconds * 1000);

      // Save newAccessToken and expire_in to local database
      await _dbService.setOauthAccessToken(newAccessToken);
      await _dbService.setOauthTokenExpiry(expiryMillis);
      _accessTokenInvalidated = false;

      DebugFileLogger.log(
        '[ZohoApiClient] ✅ _refreshAccessToken: SUCCESS — '
        'accessTokenLength=${newAccessToken.length}, '
        'expiresInSeconds=$expiresInSeconds, expiryMillis=$expiryMillis',
      );

      return newAccessToken;
    } on Exception catch (e, stack) {
      DebugFileLogger.log(
        '[ZohoApiClient] ❌ _refreshAccessToken: EXCEPTION: $e'
        '${e is DioException ? ', responseData=${e.response?.data}, statusCode=${e.response?.statusCode}' : ''}',
      );
      AppLogger.error('ZohoApi', 'OAuth Refresh Error: $e');
      unawaited(
        FirebaseTelemetry.reportZohoApiFailure(
          e,
          stackTrace: stack,
          source: 'oauth_refresh',
        ),
      );
      throw Exception('Zoho OAuth token refresh failed: $e');
    }
  }

  // --- Generic helpers ---

  /// Fetches all pages from a Zoho list endpoint. Returns a single flat list of records.
  /// The records are read from the first list-valued key in the response payload
  /// (e.g. `invoices`, `customerpayments`, `creditnotes`).
  Future<List<Map<String, dynamic>>> _fetchAllPages(
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
      final response = await _dio.get<dynamic>(path, queryParameters: params);
      if (response.statusCode != 200) {
        throw Exception('GET $path failed: ${response.statusCode}');
      }
      var rawData = response.data;
      if (rawData is String) {
        try {
          rawData = jsonDecode(rawData);
        } catch (_) {}
      }
      final data = jsonMap(rawData);
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

  /// Fetches a single contact detail record (opening balance, tax_reg_no).
  Future<Map<String, dynamic>> fetchContactDetail(String contactId) async {
    final response = await _dio.get<dynamic>('/contacts/$contactId');
    if (response.statusCode != 200) {
      throw Exception(
        'GET /contacts/$contactId failed: ${response.statusCode}',
      );
    }
    return jsonMap(response.data is Map ? (response.data as Map)['contact'] : null);
  }

  // --- Zoho Books REST APIs ---

  // 1. Fetch Routes (Simulated since Zoho Books doesn't have a native Route entity, we map to custom Contact Fields)
  Future<List<Map<String, dynamic>>> fetchRoutes() async {
    await Future<void>.delayed(
      const Duration(milliseconds: 600),
    ); // Network latency simulator

    return [
      {
        'id': 'route_north',
        'name': 'North Downtown Sequence',
        'description': 'Servicing supermarkets in the Northern metro corridor',
      },
      {
        'id': 'route_south',
        'name': 'South Retail Hub',
        'description': 'Main shopping sequence along Southern high street',
      },
      {
        'id': 'route_east',
        'name': 'East Coastal Markets',
        'description': 'General stores and bakeries in the Eastern bay area',
      },
    ];
  }

  // 2. Fetch All Customers
  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    try {
      return await _fetchAllPages('/contacts', {'contact_type': 'customer'});
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchCustomers error: $e');
      throw Exception('Failed to fetch customers from Zoho: $e');
    }
  }

  // 3. Fetch Items in Van Warehouse (Zoho Books Locations API)
  Future<List<Map<String, dynamic>>> fetchItems(String warehouseId) async {
    try {
      final queryParams = <String, dynamic>{};
      // Only query by location_id if it is a real numeric Zoho location ID.
      if (warehouseId.isNotEmpty && RegExp(r'^\d+$').hasMatch(warehouseId)) {
        queryParams['location_id'] = warehouseId;
      }

      return await _fetchAllPages('/items', queryParams);
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchItems error: $e');
      throw Exception('Failed to fetch items from Zoho: $e');
    }
  }

  // 3b. Single item detail (GET /items/{id}) — the list endpoint does NOT
  // return `unit_conversions`, so multi-UOM data is fetched per-item on demand
  // (see ItemRepository.resolveItemUnitConversions).
  Future<Map<String, dynamic>> fetchItemDetail(String itemId) async {
    final response = await _dio.get<dynamic>('/items/$itemId');
    if (response.statusCode != 200) {
      throw Exception('GET /items/$itemId failed: ${response.statusCode}');
    }
    return jsonMap(response.data is Map ? (response.data as Map)['item'] : null);
  }

  /// Forces the transaction **header** `location_id` to the org's KGT primary
  /// business location (B4) — overwrites any van id a queue item was stamped
  /// with locally, since Option B keeps vans on line items only, never on
  /// the header.
  Map<String, dynamic> _withPrimaryHeaderLocation(Map<String, dynamic> json) {
    final primaryId = _dbService.primaryWarehouseId;
    if (primaryId != null &&
        primaryId.isNotEmpty &&
        RegExp(r'^\d+$').hasMatch(primaryId)) {
      final updatedJson = Map<String, dynamic>.from(json);
      updatedJson['location_id'] = primaryId;
      return updatedJson;
    }
    return json;
  }

  /// Stamps the session salesperson id onto a transaction header when absent
  /// (B4). Not applicable to `expenses`, which has no salesperson-equivalent
  /// field in the Zoho schema (only `employee_id`, unrelated to van reps).
  /// `customerpayments` has its own differently-named field — see
  /// [_withReceiptSalespersonId].
  Map<String, dynamic> _withSalespersonId(Map<String, dynamic> json) {
    final salespersonId = _dbService.getCurrentSalesperson()?.id;
    if (salespersonId != null &&
        salespersonId.isNotEmpty &&
        json['salesperson_id'] == null) {
      final updatedJson = Map<String, dynamic>.from(json);
      updatedJson['salesperson_id'] = salespersonId;
      return updatedJson;
    }
    return json;
  }

  /// Stamps the session salesperson id onto a customer-payment header when
  /// absent. Verified against the live API: `customerpayments` carries the
  /// salesperson under `sales_person_id` (underscore-separated) — a different
  /// key from `salesperson_id` used by invoices/orders/creditnotes.
  Map<String, dynamic> _withReceiptSalespersonId(Map<String, dynamic> json) {
    final salespersonId = _dbService.getCurrentSalesperson()?.id;
    if (salespersonId != null &&
        salespersonId.isNotEmpty &&
        json['sales_person_id'] == null) {
      final updatedJson = Map<String, dynamic>.from(json);
      updatedJson['sales_person_id'] = salespersonId;
      return updatedJson;
    }
    return json;
  }

  /// Stamps the session van location onto every `line_items` entry when
  /// absent (B4/Option B) — the van, not the KGT primary, is what actually
  /// deducts stock in Zoho. Locally-stored line items carry no `location_id`
  /// at all (`Model.toJson()` never wrote one), so this is where the van id
  /// first enters the payload for invoice/order/credit-note line items.
  Map<String, dynamic> _withVanLineItemLocations(Map<String, dynamic> json) {
    final vanId = _dbService.assignedWarehouseId;
    final rawLines = json['line_items'];
    if (vanId == null ||
        vanId.isEmpty ||
        !RegExp(r'^\d+$').hasMatch(vanId) ||
        rawLines is! List) {
      return json;
    }
    final updatedLines = rawLines.map((line) {
      if (line is! Map) return line;
      final map = Map<String, dynamic>.from(line);
      map['location_id'] ??= vanId;
      return map;
    }).toList();
    return {...json, 'line_items': updatedLines};
  }

  /// Ensures every line has a Zoho `tax_id` before post.
  ///
  /// UAE Books applies customer exemption **EXEMPT** when lines omit `tax_id`
  /// (even if `tax_percentage` is set). That happens for both
  /// `vat_registered` and `vat_not_registered` contacts — unregistered
  /// customers are still taxable (`is_taxable=true`) and must get **Standard
  /// Rate**, not EXEMPT.
  ///
  /// Resolution order per line:
  /// 1. Keep an existing non-empty `tax_id` (item Zero Rate / explicit tax wins).
  /// 2. If `tax_percentage` is positive, match [HiveDatabaseService.getTaxes] by rate.
  /// 3. Otherwise fall back to the **default tax** (Standard Rate 5% in this org).
  ///
  /// Percentage 0 is *not* treated as Zero Rate here: missing tax data on
  /// queued lines usually means "unset", and matching 0% would incorrectly
  /// pick Zero Rate instead of Standard Rate.
  Map<String, dynamic> _withResolvedLineTaxIds(Map<String, dynamic> payload) {
    List<Tax> taxes;
    try {
      taxes = _dbService.getTaxes();
    } on Exception catch (_) {
      return payload;
    }
    if (taxes.isEmpty) return payload;
    return ZohoPayloadMapper.withResolvedLineTaxIds(
      payload,
      resolveTaxId: (pct) {
        if (pct != null && pct > 0) {
          for (final t in taxes) {
            if ((t.percentage - pct).abs() < 0.001) return t.id;
          }
        }
        for (final t in taxes) {
          if (t.isDefault) return t.id;
        }
        // Last resort: first positive-rate tax (Standard Rate style).
        for (final t in taxes) {
          if (t.percentage > 0) return t.id;
        }
        return null;
      },
    );
  }

  // 4. Zoho Books Contacts API: Sync New Customer
  Future<String> syncCustomer(Map<String, dynamic> customerJson) async {
    try {
      final response = await _dio.post<dynamic>(
        '/contacts',
        data: ZohoPayloadMapper.zohoContactPayload(customerJson),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['contact']['contact_id'] as String;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Customer Sync Failed: $e');
    }
  }

  /// Update GPS (latitude/longitude) on an existing Zoho contact via billing_address.
  ///
  /// Uses PUT /contacts/{contactId} sending only the billing_address coordinates
  /// to minimize risk of overwriting other fields.
  /// Returns the contact_id on success.
  Future<String> updateCustomerGps(
    String contactId,
    double latitude,
    double longitude,
  ) async {
    final payload = {
      'billing_address': {
        'latitude': latitude,
        'longitude': longitude,
      },
    };

    try {
      final response = await _dio.put<dynamic>('/contacts/$contactId', data: payload);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data['contact']?['contact_id']?.toString() ?? contactId;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Customer GPS Update Failed: $e');
    }
  }

  /// Update phone and/or TRN on an existing Zoho contact.
  ///
  /// Sends only the fields being filled so other contact data is not overwritten.
  Future<String> updateCustomerContactFields(
    String contactId, {
    String? phone,
    String? trn,
  }) async {
    final payload = <String, dynamic>{};
    if (phone != null) payload['phone'] = phone;
    if (trn != null) payload['tax_reg_no'] = trn;
    if (payload.isEmpty) return contactId;

    try {
      final response = await _dio.put<dynamic>('/contacts/$contactId', data: payload);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data['contact']?['contact_id']?.toString() ?? contactId;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Customer Contact Update Failed: $e');
    }
  }

  // 5. Zoho Books Invoices API: Sync Sales Invoice
  Future<String> syncInvoice(Map<String, dynamic> invoiceJson) async {
    invoiceJson = _withVanLineItemLocations(
      _withSalespersonId(_withPrimaryHeaderLocation(invoiceJson)),
    );
    try {
      final response = await _dio.post<dynamic>(
        '/invoices',
        data: _withResolvedLineTaxIds(
          ZohoPayloadMapper.zohoInvoicePayload(invoiceJson),
        ),
        queryParameters: const {'ignore_auto_number_generation': true},
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['invoice']['invoice_id'] as String;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Invoice Sync Failed: $e');
    }
  }

  // 5b. Zoho Books Sales Orders API: Sync Sales Order
  Future<String> syncSalesOrder(Map<String, dynamic> salesOrderJson) async {
    salesOrderJson = _withVanLineItemLocations(
      _withSalespersonId(_withPrimaryHeaderLocation(salesOrderJson)),
    );
    final payload = _withResolvedLineTaxIds(
      ZohoPayloadMapper.zohoSalesOrderPayload(salesOrderJson),
    );
    // Debug: log exact outbound body so 400s can be matched to Zoho's message.
    AppLogger.debug(
      'ZohoApi',
      'POST /salesorders payload: ${jsonEncode(payload)}',
    );
    try {
      final response = await _dio.post<dynamic>(
        '/salesorders',
        data: payload,
        queryParameters: const {'ignore_auto_number_generation': true},
      );
      AppLogger.debug(
        'ZohoApi',
        'POST /salesorders response ${response.statusCode}: '
        '${jsonEncode(response.data)}',
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['salesorder']['salesorder_id'] as String;
      }
      throw Exception(
        'HTTP ${response.statusCode} body=${jsonEncode(response.data)}',
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      final bodyStr = body is String
          ? body
          : (body != null ? jsonEncode(body) : 'null');
      final zohoMessage = zohoMessageFromResponseData(body);
      AppLogger.error(
        'ZohoApi',
        'POST /salesorders failed status=${e.response?.statusCode} '
        'response=$bodyStr payload=${jsonEncode(payload)}',
      );
      // Surface Zoho's message for the queue UI; keep status/body in the
      // exception tail so humanizeSyncError can still parse older shapes.
      throw Exception(
        zohoMessage != null && zohoMessage.isNotEmpty
            ? 'Zoho Books Sales Order Sync Failed: $zohoMessage'
            : 'Zoho Books Sales Order Sync Failed: '
                'status=${e.response?.statusCode} body=$bodyStr',
      );
    } on Exception catch (e) {
      AppLogger.error(
        'ZohoApi',
        'POST /salesorders failed: $e payload=${jsonEncode(payload)}',
      );
      throw Exception('Zoho Books Sales Order Sync Failed: $e');
    }
  }

  // 5c. Zoho Books Sales Orders API: Convert a Sales Order to an Invoice.
  //
  // Atomically creates the invoice in Zoho AND flips the sales order status to
  // "invoiced". Requires the permanent Zoho [salesOrderId]. An empty body
  // converts the whole order. Returns the new invoice's `invoice_id`.
  Future<String> convertSalesOrderToInvoice(
    String salesOrderId, [
    Map<String, dynamic>? body,
  ]) async {
    if (body != null) {
      body = _withVanLineItemLocations(
        _withSalespersonId(_withPrimaryHeaderLocation(body)),
      );
    }
    try {
      final response = await _dio.post<dynamic>(
        '/salesorders/$salesOrderId/converttoinvoice',
        data: body ?? {},
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['invoice']['invoice_id'] as String;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Sales Order Conversion Failed: $e');
    }
  }

  /// `{'salesperson_id': id}` for the bound session salesperson, or `{}`
  /// when no session is bound — list fetchers fall back to unfiltered pulls
  /// in that case rather than returning nothing.
  ///
  /// Use only on modules that expose native `salesperson_id` (invoices, sales
  /// orders, credit notes, open invoices). Customer payments and expenses do
  /// **not** — see [_receiptSeriesReferenceFilterParams] /
  /// [_paidThroughAccountFilterParams].
  Map<String, dynamic> _salespersonFilterParams() {
    final id = _dbService.getCurrentSalesperson()?.id;
    return (id != null && id.isNotEmpty) ? {'salesperson_id': id} : {};
  }

  /// Client-side re-check of [_salespersonFilterParams], applied after a
  /// server-filtered fetch. Belt-and-suspenders: keeps rows whose
  /// `salesperson_id` is missing (legacy data) or matches the bound
  /// salesperson; drops anything that resolves to someone else's, in case the
  /// server-side filter param isn't fully enforced. No-op (returns [rows]
  /// unchanged) when no salesperson session is bound.
  List<Map<String, dynamic>> _filterBySalesperson(
    List<Map<String, dynamic>> rows,
  ) {
    final salespersonId = _dbService.getCurrentSalesperson()?.id;
    if (salespersonId == null || salespersonId.isEmpty) return rows;
    return rows.where((j) {
      final spId = j['salesperson_id']?.toString();
      return spId == null || spId.isEmpty || spId == salespersonId;
    }).toList();
  }

  /// Scopes customer-payment lists to this salesperson's app-generated series.
  ///
  /// Zoho Payments have no `salesperson_id`; the app stores its offline number
  /// (`{prefix}RCT-#####`) in `reference_number` (B4/B5). Empty prefix → no
  /// filter (same unfiltered fallback as [_salespersonFilterParams]).
  Map<String, dynamic> _receiptSeriesReferenceFilterParams() {
    final prefix = _dbService.voucherPrefix?.trim();
    if (prefix == null || prefix.isEmpty) return {};
    return {'reference_number_startswith': '${prefix}RCT-'};
  }

  /// Scopes expense lists to the session salesperson's personal cash ledger.
  ///
  /// Zoho Expenses have no `salesperson_id`; van expenses are paid through
  /// `cf_cash_account` (`paid_through_account_id`). Documented list filter on
  /// `GET /expenses`. Empty session cash → no filter.
  Map<String, dynamic> _paidThroughAccountFilterParams() {
    final id = _dbService.cashAccountId?.trim();
    return (id != null && id.isNotEmpty)
        ? {'paid_through_account_id': id}
        : {};
  }

  /// `{'date_start': ..., 'date_end': ...}` (yyyy-MM-dd) for whichever bounds
  /// are supplied — omitted params are left out, preserving unfiltered pulls.
  Map<String, dynamic> _dateRangeParams({
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final params = <String, dynamic>{};
    if (startDate != null) {
      params['date_start'] = startDate.toIso8601String().split('T')[0];
    }
    if (endDate != null) {
      params['date_end'] = endDate.toIso8601String().split('T')[0];
    }
    return params;
  }

  // 5d. Zoho Books Sales Orders API: List headers only (paginated).
  // Includes status/total; no line items / no N detail calls. Powers the
  // sales order list page. Reports that need lines use
  // [fetchSalesOrdersWithDetails].
  Future<List<Map<String, dynamic>>> fetchSalesOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final spParams = _salespersonFilterParams();
      final dateParams = _dateRangeParams(
        startDate: startDate,
        endDate: endDate,
      );
      final list = await _fetchAllPages('/salesorders', {
        ...spParams,
        ...dateParams,
      });
      final filtered = _filterBySalesperson(list);
      AppLogger.info(
        'ZohoApi',
        'fetchSalesOrders raw=${list.length} afterSpFilter=${filtered.length} '
        'sp=${spParams['salesperson_id'] ?? '(none)'} '
        'dates=${dateParams['date_start'] ?? '*'}..${dateParams['date_end'] ?? '*'}',
      );
      return filtered;
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchSalesOrders error: $e');
      throw Exception('Failed to fetch sales orders from Zoho: $e');
    }
  }

  // 5d2. Full sales-order list with line items — powers itemwise/order reports.
  Future<List<Map<String, dynamic>>> fetchSalesOrdersWithDetails({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final headers = await fetchSalesOrders(
        startDate: startDate,
        endDate: endDate,
      );
      final details = <Map<String, dynamic>>[];
      for (final header in headers) {
        final id = header['salesorder_id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          details.add(await fetchSalesOrder(id));
        } on Exception catch (e) {
          AppLogger.error('ZohoApi', 'fetchSalesOrder($id) error: $e');
        }
      }
      return _filterBySalesperson(details);
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchSalesOrdersWithDetails error: $e');
      throw Exception('Failed to fetch sales order details from Zoho: $e');
    }
  }

  // 5e. Zoho Books Sales Orders API: Read a single sales order by id.
  Future<Map<String, dynamic>> fetchSalesOrder(String salesOrderId) async {
    try {
      final response = await _dio.get<dynamic>('/salesorders/$salesOrderId');
      if (response.statusCode != 200) {
        throw Exception(
          'GET /salesorders/$salesOrderId failed: ${response.statusCode}',
        );
      }
      return jsonMap(response.data is Map ? (response.data as Map)['salesorder'] : null);
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchSalesOrder error: $e');
      throw Exception('Failed to fetch sales order from Zoho: $e');
    }
  }

  // 5f. Zoho Books Sales Orders API: Update an existing sales order.
  Future<String> updateSalesOrder(
    String salesOrderId,
    Map<String, dynamic> payload,
  ) async {
    payload = _withVanLineItemLocations(
      _withSalespersonId(_withPrimaryHeaderLocation(payload)),
    );
    try {
      final response = await _dio.put<dynamic>(
        '/salesorders/$salesOrderId',
        data: _withResolvedLineTaxIds(
          ZohoPayloadMapper.zohoSalesOrderPayload(payload),
        ),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data['salesorder']['salesorder_id'] as String;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Sales Order Update Failed: $e');
    }
  }

  // 5g. Zoho Books Transfer Orders API: Sync Stock Transfer (Issue to Van / Stock Unloading).
  //
  // Transfers carry explicit from/to location ids in the payload already, so
  // (unlike invoices/orders/receipts) this does NOT run _withPrimaryHeaderLocation.
  // Posted to Books v3 — this org's Inventory account is disabled (HTTP 6018).
  Future<String> syncStockTransfer(Map<String, dynamic> transferJson) async {
    try {
      final response = await _dio.post<dynamic>(
        '/transferorders',
        data: ZohoPayloadMapper.zohoStockTransferPayload(transferJson),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['transfer_order']['transfer_order_id'] as String;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Stock Transfer Sync Failed: $e');
    }
  }

  // 5g-2. Zoho Books Transfer Orders API: Update an existing (still-draft)
  // transfer order. Only valid while Zoho reports status `draft` — the
  // caller is responsible for not calling this once Zoho has moved the
  // transfer past draft.
  Future<String> updateStockTransfer(
    String transferOrderId,
    Map<String, dynamic> transferJson,
  ) async {
    try {
      final response = await _dio.put<dynamic>(
        '/transferorders/$transferOrderId',
        data: {
          ...ZohoPayloadMapper.zohoStockTransferPayload(transferJson),
          // Trust the id passed by the caller (sync_worker reads it from the
          // queue item), not whatever the raw payload's own bookkeeping
          // fields happen to hold — the payload mapper never whitelists
          // transfer_order_id (create must never send it).
          'transfer_order_id': transferOrderId,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data['transfer_order']['transfer_order_id'] as String;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Stock Transfer Update Failed: $e');
    }
  }

  // 5h. Zoho Books Transfer Orders API: List stock transfers (paginated).
  //
  // Issue-to-Van lists pass [toLocationId] (stock into the van).
  // Stock-Unloading lists pass [fromLocationId] (stock out of the van).
  // The history report passes neither and is scoped client-side to the
  // session location on either end.
  //
  // Inventory documents `from_location_id` / `to_location_id` query
  // filters; Books v3 is thinner. Matching client-side predicates still
  // run so an ignored query param cannot leak the other direction.
  Future<List<Map<String, dynamic>>> fetchStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
    String? fromLocationId,
    String? toLocationId,
  }) async {
    try {
      final params = <String, dynamic>{
        ..._dateRangeParams(startDate: startDate, endDate: endDate),
        if (fromLocationId != null && fromLocationId.isNotEmpty)
          'from_location_id': fromLocationId,
        if (toLocationId != null && toLocationId.isNotEmpty)
          'to_location_id': toLocationId,
      };
      final list = await _fetchAllPages('/transferorders', params);

      if (toLocationId != null && toLocationId.isNotEmpty) {
        return list
            .where((j) => j['to_location_id']?.toString() == toLocationId)
            .toList();
      }
      if (fromLocationId != null && fromLocationId.isNotEmpty) {
        return list
            .where((j) => j['from_location_id']?.toString() == fromLocationId)
            .toList();
      }

      // Unfiltered (history report): a van's transfers can appear on either
      // side depending on direction.
      final locationId = _dbService.getCurrentSalesperson()?.locationId;
      if (locationId != null && locationId.isNotEmpty) {
        return list.where((j) {
          final from = j['from_location_id']?.toString();
          final to = j['to_location_id']?.toString();
          if (from == null && to == null) return true;
          return from == locationId || to == locationId;
        }).toList();
      }
      return list;
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchStockTransfers error: $e');
      throw Exception('Failed to fetch stock transfers from Zoho: $e');
    }
  }

  // 6. Zoho Books Customer Payments API: Sync Receipt Voucher
  Future<String> syncReceiptVoucher(Map<String, dynamic> paymentJson) async {
    paymentJson = _withReceiptSalespersonId(
      _withPrimaryHeaderLocation(paymentJson),
    );
    // B4/B5: the app's offline receipt number has no home in Zoho's own
    // `payment_number` series, so it travels as `reference_number`. Deposit
    // account is the session salesperson's personal cash ledger.
    final appNumber = paymentJson['payment_number']?.toString();
    if (appNumber != null && appNumber.isNotEmpty) {
      paymentJson = {...paymentJson, 'reference_number': appNumber};
    }
    final cashAccountId = _dbService.cashAccountId;
    if (cashAccountId != null && cashAccountId.isNotEmpty) {
      paymentJson = {...paymentJson, 'account_id': cashAccountId};
    }
    try {
      final response = await _dio.post<dynamic>(
        '/customerpayments',
        data: ZohoPayloadMapper.zohoReceiptPayload(paymentJson),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['payment']['payment_id'] as String;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Payment Sync Failed: $e');
    }
  }

  // 7. Zoho Books Credit Notes API: Sync Sales Return
  ///
  /// Create-or-skip, then apply credit to the source invoice(s). On retry
  /// after a successful create + failed apply, [creditNoteJson] must already
  /// carry `zoho_credit_note_id` so this does not POST a second credit note.
  /// Stamps that id onto [creditNoteJson] immediately after create.
  Future<String> syncSalesReturn(Map<String, dynamic> creditNoteJson) async {
    creditNoteJson = _withVanLineItemLocations(
      _withSalespersonId(_withPrimaryHeaderLocation(creditNoteJson)),
    );
    try {
      var remoteId = SalesReturnSync.existingRemoteId(creditNoteJson);
      Map<String, dynamic>? createdCreditnote;
      if (remoteId == null) {
        final query = <String, dynamic>{
          'ignore_auto_number_generation': true,
        };
        final invoiceId = SalesReturnSync.sharedInvoiceId(creditNoteJson);
        if (invoiceId != null) query['invoice_id'] = invoiceId;

        final response = await _dio.post<dynamic>(
          '/creditnotes',
          data: _withResolvedLineTaxIds(
            ZohoPayloadMapper.zohoCreditNotePayload(creditNoteJson),
          ),
          queryParameters: query,
        );
        if (response.statusCode != 201 && response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        remoteId = response.data['creditnote']['creditnote_id'] as String;
        creditNoteJson['zoho_credit_note_id'] = remoteId;
        createdCreditnote = response.data['creditnote'] is Map
            ? Map<String, dynamic>.from(response.data['creditnote'] as Map)
            : null;
      }

      await _applyCreditNoteToInvoices(
        remoteId,
        creditNoteJson,
        createdCreditnote: createdCreditnote,
      );
      return remoteId;
    } on Exception catch (e) {
      throw Exception('Zoho Books Credit Note Sync Failed: $e');
    }
  }

  Future<void> _applyCreditNoteToInvoices(
    String creditNoteId,
    Map<String, dynamic> creditNoteJson, {
    Map<String, dynamic>? createdCreditnote,
  }) async {
    final invoices = SalesReturnSync.applyInvoices(creditNoteJson);
    if (invoices.isEmpty) return;
    if (SalesReturnSync.alreadyApplied(createdCreditnote, invoices)) return;
    try {
      final response = await _dio.post<dynamic>(
        '/creditnotes/$creditNoteId/invoices',
        data: {'invoices': invoices},
      );
      if (response.statusCode != 201 && response.statusCode != 200) {
        throw Exception(
          'Apply credit to invoice failed: HTTP ${response.statusCode}',
        );
      }
    } on Exception catch (e) {
      if (SalesReturnSync.isAlreadyAppliedError(e)) return;
      rethrow;
    }
  }

  // 8. Zoho Books Expenses API: Sync Expense Entry
  Future<String> syncExpense(Map<String, dynamic> expenseJson) async {
    expenseJson = _withPrimaryHeaderLocation(expenseJson);
    try {
      // Resolve local category lines into an itemized Zoho expense body with
      // real ledger account IDs and a paid-through (cash) account at the root.
      final zohoExpense = _buildZohoExpensePayload(expenseJson);

      // Multi-part only when a receipt path is present.
      final receiptPath = expenseJson['receiptImagePath']?.toString();
      final dynamic dataPayload;
      if (receiptPath != null && receiptPath.isNotEmpty) {
        dataPayload = FormData.fromMap({
          'JSONString': jsonEncode(zohoExpense),
          'attachment': await MultipartFile.fromFile(
            receiptPath,
            filename: 'receipt.jpg',
          ),
        });
      } else {
        dataPayload = zohoExpense;
      }

      final response = await _dio.post<dynamic>('/expenses', data: dataPayload);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['expense']['expense_id'] as String;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on Exception catch (e) {
      throw Exception('Zoho Books Expense Sync Failed: $e');
    }
  }

  /// Resolves a stored expense map (`lines[]` of category/amount/description)
  /// into an itemized Zoho `/expenses` body via [ZohoPayloadMapper].
  ///
  /// Each line's `category` is mapped to a real Zoho expense ledger `account_id`
  /// from the synced expense accounts; `paid_through_account_id` is the
  /// session salesperson's personal cash ledger (B4) — falling back to the
  /// first cash-type payment account only if the session has none bound (logs
  /// a warning, since that indicates an incomplete profile bind). Throws if
  /// the master account lists are empty so the sync-queue item surfaces as
  /// "Needs Attention" rather than sending an invalid payload.
  Map<String, dynamic> _buildZohoExpensePayload(
    Map<String, dynamic> expenseJson,
  ) {
    final expenseAccounts = _dbService.getExpenseAccounts();
    final paymentAccounts = _dbService.getPaymentAccounts();

    if (expenseAccounts.isEmpty) {
      throw Exception(
        'No expense accounts synced — cannot resolve expense ledger account_id.',
      );
    }

    String accountIdForCategory(String category) {
      final match = expenseAccounts.where((a) => a.category == category);
      return match.isNotEmpty ? match.first.id : expenseAccounts.first.id;
    }

    var paidThroughAccountId = _dbService.cashAccountId;
    if (paidThroughAccountId == null || paidThroughAccountId.isEmpty) {
      if (paymentAccounts.isEmpty) {
        throw Exception(
          'No session cash account bound and no payment accounts synced — '
          'cannot resolve paid_through_account_id.',
        );
      }
      AppLogger.error(
        'ZohoApi',
        'No session cash account bound — falling back to first org cash account for expense paid_through_account_id.',
      );
      final fallback = paymentAccounts.firstWhere(
        (a) => a.accountType == 'cash',
        orElse: () => paymentAccounts.first,
      );
      paidThroughAccountId = fallback.id;
    }

    final rawLines = (expenseJson['lines'] as List?) ?? const <dynamic>[];
    final standardTaxId = _defaultStandardTaxId();
    final resolvedLines = rawLines.whereType<Map<dynamic, dynamic>>().map((line) {
      final map = Map<String, dynamic>.from(line);
      final category = map['category']?.toString() ?? '';
      final resolved = <String, dynamic>{
        'account_id': accountIdForCategory(category),
        'amount': (map['amount'] as num?)?.toDouble() ?? 0.0,
        'description': map['description']?.toString() ?? '',
      };
      if (_expenseCategoryIsTaxable(category) &&
          standardTaxId != null &&
          standardTaxId.isNotEmpty) {
        resolved['tax_id'] = standardTaxId;
      }
      return resolved;
    }).toList();

    final anyTaxable = resolvedLines.any(
      (l) => (l['tax_id']?.toString() ?? '').isNotEmpty,
    );
    return ZohoPayloadMapper.zohoExpensePayload(
      expenseJson,
      resolvedLines: resolvedLines,
      paidThroughAccountId: paidThroughAccountId,
      isInclusiveTax: anyTaxable,
    );
  }

  /// Fuel / Maintenance match live UAE Books (Standard Rate). Tolls and
  /// parking stay EXEMPT by omitting `tax_id`.
  static bool _expenseCategoryIsTaxable(String category) {
    switch (category.trim().toLowerCase()) {
      case 'fuel':
      case 'maintenance':
        return true;
      default:
        return false;
    }
  }

  String? _defaultStandardTaxId() {
    List<Tax> taxes;
    try {
      taxes = _dbService.getTaxes();
    } on Exception catch (_) {
      return null;
    }
    for (final t in taxes) {
      if (t.isDefault) return t.id;
    }
    for (final t in taxes) {
      if (t.percentage > 0) return t.id;
    }
    return null;
  }

  // --- Master Data Fetchers ---

  // 9. Warehouses/Locations (GET /locations)
  Future<List<Map<String, dynamic>>> fetchWarehouses() async {
    try {
      final response = await _dio.get<dynamic>('/locations');
      if (response.statusCode == 200) {
        final list = (response.data['locations'] as List? ?? []);
        final result =
            list.map((w) => Map<String, dynamic>.from(w as Map)).toList();
        AppLogger.info(
          'ZohoApi',
          'fetchWarehouses (locations) fetched ${result.length} records: ${jsonEncode(result)}',
        );
        DebugFileLogger.log(
          '[ZohoApi] fetchWarehouses (locations) fetched ${result.length} records: ${jsonEncode(result)}',
        );
        return result;
      }
      throw Exception(
        'Failed to fetch locations: Server returned status code ${response.statusCode}',
      );
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchWarehouses (locations) error: $e');
      throw Exception('Failed to fetch locations from Zoho: $e');
    }
  }

  // Salespersons (GET /salespersons)
  Future<List<Map<String, dynamic>>> fetchSalespersons() async {
    try {
      final response = await _dio.get<dynamic>('/salespersons');
      if (response.statusCode == 200) {
        // Zoho returns salespersons under `data` (verified against live API).
        final list =
            (response.data['data'] ??
                    response.data['salespersons'] ??
                    <dynamic>[])
                as List;
        final result =
            list.map((s) => Map<String, dynamic>.from(s as Map)).toList();
        AppLogger.info(
          'ZohoApi',
          'fetchSalespersons fetched ${result.length} records: ${jsonEncode(result)}',
        );
        DebugFileLogger.log(
          '[ZohoApi] fetchSalespersons fetched ${result.length} records: ${jsonEncode(result)}',
        );
        return result;
      }
      throw Exception(
        'Failed to fetch salespersons: Server returned status code ${response.statusCode}',
      );
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchSalespersons error: $e');
      throw Exception('Failed to fetch salespersons from Zoho: $e');
    }
  }

  // Salesperson profile module (GET /cm_salesperson_profile — custom module).
  // Primary field `record_name` holds the login phone in E.164; lookups
  // (`cf_salesperson`, `cf_van_location`, `cf_cash_account`) return both the
  // id and a `_formatted` display name. Records list as `status: draft`
  // (Zoho quirk) — callers must NOT filter by record status, only `cf_active`.
  Future<List<Map<String, dynamic>>> fetchSalespersonProfiles() async {
    if (!hasCredentials) {
      throw const ZohoNotConfiguredException();
    }
    if (_organizationId.trim().isEmpty) {
      throw const ZohoNotConfiguredException();
    }

    try {
      // Login bind must use the same OAuth triple the app injected
      // (Firestore `server_config/zoho` / secure cache): client id, secret,
      // and refresh token. Exchange that refresh token, then GET with the
      // access token — do not rely on a possibly stale Hive cache from a
      // previous client. Default list view is not Status.All; records are
      // stored as `status: draft`, so omitting the filter returns zero rows
      // and surfaces as SessionBindFailure.notRegistered. Do not dump the
      // body: jsonEncode of module_records floods logcat / BLASTBufferQueue.
      final accessToken = await _refreshAccessToken(force: true);
      AppLogger.info(
        'ZohoApi',
        'GET /cm_salesperson_profile using app OAuth '
        '(orgId=$_organizationId, refreshTokenLen=${_refreshToken.length})',
      );
      final response = await Dio().get<dynamic>(
        '$_apiUrl/cm_salesperson_profile',
        queryParameters: {
          'organization_id': _organizationId,
          'filter_by': 'Status.All',
          'per_page': 200,
        },
        options: Options(
          headers: {
            'Authorization': 'Zoho-oauthtoken $accessToken',
            'JSONString': 'true',
          },
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        final list =
            (data is Map
                    ? (data['module_records'] ?? data['data'] ?? <dynamic>[])
                    : <dynamic>[])
                as List;
        final pageContext = data is Map ? data['page_context'] : null;
        final appliedFilter = pageContext is Map
            ? pageContext['applied_filter']
            : null;
        final names = <String>[];
        for (final row in list) {
          if (row is Map) {
            names.add('${row['record_name'] ?? ''}');
          }
        }
        AppLogger.info(
          'ZohoApi',
          'GET /cm_salesperson_profile http=${response.statusCode} '
          'applied_filter=$appliedFilter count=${list.length} '
          'record_names=${names.join(',')}',
        );
        return list.map((m) => Map<String, dynamic>.from(m as Map)).toList();
      }
      throw Exception(
        'Failed to fetch salesperson profiles: Server returned status code ${response.statusCode}',
      );
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchSalespersonProfiles error: $e');
      throw Exception('Failed to fetch salesperson profiles from Zoho: $e');
    }
  }

  // Duplicate-proof offline numbering (B5): highest existing document numbers
  // matching a given app-side prefix, used to seed local counters.
  Future<List<String>> fetchDocumentNumbersStartingWith({
    required String endpoint,
    required String startswithParam,
    required String numberKey,
    required String prefix,
  }) async {
    try {
      final records = await _fetchAllPages(endpoint, {startswithParam: prefix});
      return records
          .map((r) => r[numberKey]?.toString())
          .whereType<String>()
          .toList();
    } on Exception catch (e) {
      AppLogger.error(
        'ZohoApi',
        'fetchDocumentNumbersStartingWith($endpoint) error: $e',
      );
      throw Exception('Failed to fetch document numbers from Zoho: $e');
    }
  }

  // 10. Payment Accounts (GET /bankaccounts — bank + cash accounts for receipts)
  Future<List<Map<String, dynamic>>> fetchPaymentAccounts() async {
    try {
      final response = await _dio.get<dynamic>('/bankaccounts');
      if (response.statusCode == 200) {
        final list = (response.data['bankaccounts'] as List? ?? []);
        return list.map((a) => Map<String, dynamic>.from(a as Map)).toList();
      }
      throw Exception(
        'Failed to fetch payment accounts: Server returned status code ${response.statusCode}',
      );
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchPaymentAccounts error: $e');
      throw Exception('Failed to fetch payment accounts from Zoho: $e');
    }
  }

  // 11. Taxes (GET /settings/taxes)
  Future<List<Map<String, dynamic>>> fetchTaxes() async {
    try {
      final response = await _dio.get<dynamic>('/settings/taxes');
      if (response.statusCode == 200) {
        final list = (response.data['taxes'] as List? ?? []);
        return list.map((t) => Map<String, dynamic>.from(t as Map)).toList();
      }
      throw Exception(
        'Failed to fetch taxes: Server returned status code ${response.statusCode}',
      );
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchTaxes error: $e');
      throw Exception('Failed to fetch taxes from Zoho: $e');
    }
  }

  // 12. Expense Accounts (GET /chartofaccounts?filter_by=AccountType.Expense)
  Future<List<Map<String, dynamic>>> fetchExpenseAccounts() async {
    try {
      final response = await _dio.get<dynamic>(
        '/chartofaccounts',
        queryParameters: {'filter_by': 'AccountType.Expense'},
      );
      if (response.statusCode == 200) {
        final list = (response.data['chartofaccounts'] as List? ?? []);
        return list.map((a) => Map<String, dynamic>.from(a as Map)).toList();
      }
      throw Exception(
        'Failed to fetch expense accounts: Server returned status code ${response.statusCode}',
      );
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchExpenseAccounts error: $e');
      throw Exception('Failed to fetch expense accounts from Zoho: $e');
    }
  }

  // 13. Organization (GET /organizations/{org_id})
  Future<Map<String, dynamic>?> fetchOrganization() async {
    try {
      final response = await _dio.get<dynamic>('/organizations/$_organizationId');
      if (response.statusCode == 200) {
        final org = response.data['organization'];
        if (org != null) return Map<String, dynamic>.from(org as Map);
      }
      throw Exception(
        'Failed to fetch organization: Server returned status code ${response.statusCode}',
      );
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchOrganization error: $e');
      throw Exception('Failed to fetch organization from Zoho: $e');
    }
  }

  // 14. Customer Statement — composed locally from primary records.
  //
  // Zoho Books does not expose a JSON ledger endpoint. We build it Option-A style:
  //   1) Fetch contact detail (for opening_balance_amount)
  //   2) Fetch all invoices, customer payments, and credit notes for this contact
  //   3) Opening = contact.opening_balance + Σ(invoices before from) − Σ(payments+credit_notes before from)
  //   4) Merge in-period rows, sort by date, compute running balance
  //   5) Return the same JSON shape that CustomerLedger.fromJson consumes
  Future<Map<String, dynamic>> fetchCustomerStatement(
    String contactId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final from = startDate ?? DateTime(DateTime.now().year, 1, 1);
      final to = endDate ?? DateTime.now();

      final results = await Future.wait([
        fetchContactDetail(contactId),
        _fetchAllPages('/invoices', {'customer_id': contactId}),
        _fetchAllPages('/customerpayments', {'customer_id': contactId}),
        _fetchAllPages('/creditnotes', {'customer_id': contactId}),
      ]);

      final contact = results[0] as Map<String, dynamic>;
      final invoices = results[1] as List<Map<String, dynamic>>;
      final payments = results[2] as List<Map<String, dynamic>>;
      final creditNotes = results[3] as List<Map<String, dynamic>>;

      final contactName =
          (contact['contact_name'] ?? contact['company_name'] ?? '') as String;
      final baseOpening = jsonDouble(contact['opening_balance_amount']);

      DateTime parseDate(String? s) =>
          s == null || s.isEmpty ? DateTime(1970) : DateTime.parse(s);

      bool before(DateTime d) =>
          d.isBefore(DateTime(from.year, from.month, from.day));
      bool inRange(DateTime d) {
        final f = DateTime(from.year, from.month, from.day);
        final t = DateTime(to.year, to.month, to.day, 23, 59, 59);
        return !d.isBefore(f) && !d.isAfter(t);
      }

      // Compute opening balance: contact's books-start opening + everything before `from`.
      double opening = baseOpening;
      for (final inv in invoices) {
        final d = parseDate(inv['date'] as String?);
        if (before(d)) opening += jsonDouble(inv['total']);
      }
      for (final pay in payments) {
        final d = parseDate(pay['date'] as String?);
        if (before(d)) opening -= jsonDouble(pay['amount']);
      }
      for (final cn in creditNotes) {
        final d = parseDate(cn['date'] as String?);
        if (before(d)) opening -= jsonDouble(cn['total']);
      }

      // Build in-period rows.
      final rows = <Map<String, dynamic>>[];
      for (final inv in invoices) {
        final d = parseDate(inv['date'] as String?);
        if (!inRange(d)) continue;
        final number = (inv['invoice_number'] ?? '') as String;
        rows.add({
          'transaction_id': inv['invoice_id'] ?? '',
          'transaction_number': number,
          'date': inv['date'],
          'transaction_type': 'invoice',
          'debit': (inv['total'] ?? 0).toDouble(),
          'credit': 0.0,
          'description': 'Sales Invoice $number'.trim(),
          '_sort': d.millisecondsSinceEpoch,
        });
      }
      for (final pay in payments) {
        final d = parseDate(pay['date'] as String?);
        if (!inRange(d)) continue;
        final number = (pay['payment_number'] ?? '') as String;
        final mode = (pay['payment_mode'] ?? '') as String;
        rows.add({
          'transaction_id': pay['payment_id'] ?? '',
          'transaction_number': number,
          'date': pay['date'],
          'transaction_type': 'payment',
          'debit': 0.0,
          'credit': (pay['amount'] ?? 0).toDouble(),
          'description': mode.isEmpty
              ? 'Payment Received'
              : 'Payment Received — $mode',
          '_sort': d.millisecondsSinceEpoch,
        });
      }
      for (final cn in creditNotes) {
        final d = parseDate(cn['date'] as String?);
        if (!inRange(d)) continue;
        final number = (cn['creditnote_number'] ?? '') as String;
        rows.add({
          'transaction_id': cn['creditnote_id'] ?? '',
          'transaction_number': number,
          'date': cn['date'],
          'transaction_type': 'credit_note',
          'debit': 0.0,
          'credit': (cn['total'] ?? 0).toDouble(),
          'description': 'Credit Note $number'.trim(),
          '_sort': d.millisecondsSinceEpoch,
        });
      }

      rows.sort((a, b) => (a['_sort'] as int).compareTo(b['_sort'] as int));

      // Running balance
      double running = opening;
      for (final r in rows) {
        running += (r['debit'] as double) - (r['credit'] as double);
        r['balance'] = running;
        r.remove('_sort');
      }

      return {
        'contact_id': contactId,
        'contact_name': contactName,
        'opening_balance': opening,
        'closing_balance': running,
        'transactions': rows,
      };
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchCustomerStatement error: $e');
      throw Exception('Failed to fetch customer statement from Zoho: $e');
    }
  }

  // 15. Open Invoices (GET /invoices?filter_by=Status.All) — live fetch only
  // (not part of master sync). Optional [customerId] scopes the list for
  // receipt allocation so we don't pull every open invoice in the org.
  //
  // Zoho's `status` field is a literal enum (unpaid/overdue/partially_paid/
  // paid/void/draft/...) — filtering the request to status=unpaid server-side
  // silently dropped every overdue or partially-paid invoice, which in
  // practice is most of a customer's real outstanding balance. Fetch
  // everything via Status.All and filter client-side on outstanding balance
  // instead, so all collectible invoices surface regardless of status label.
  Future<List<Map<String, dynamic>>> fetchOpenInvoices({
    String? customerId,
  }) async {
    try {
      final params = <String, dynamic>{
        'filter_by': 'Status.All',
        ..._salespersonFilterParams(),
      };
      if (customerId != null &&
          customerId.isNotEmpty &&
          !customerId.startsWith('temp_')) {
        params['customer_id'] = customerId;
      }
      final all = await _fetchAllPages('/invoices', params);
      return all.where((inv) {
        final status = (inv['status'] ?? '').toString().toLowerCase();
        if (status == 'draft' || status == 'void') return false;
        final rawBalance = inv['balance'];
        final balance = rawBalance is num
            ? rawBalance.toDouble()
            : double.tryParse(rawBalance?.toString() ?? '') ?? 0.0;
        return balance > 0;
      }).toList();
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchOpenInvoices error: $e');
      throw Exception('Failed to fetch open invoices from Zoho: $e');
    }
  }

  // 16. Single invoice detail (GET /invoices/{id}) — the list endpoint only
  // returns invoice headers, so line items must be fetched per-invoice.
  Future<Map<String, dynamic>> fetchInvoiceDetail(String invoiceId) async {
    final response = await _dio.get<dynamic>('/invoices/$invoiceId');
    if (response.statusCode != 200) {
      throw Exception(
        'GET /invoices/$invoiceId failed: ${response.statusCode}',
      );
    }
    return jsonMap(response.data is Map ? (response.data as Map)['invoice'] : null);
  }

  // 16b. Invoice list headers only (GET /invoices) — powers the sales invoice
  // list page. Includes status/total; no line items / no N detail calls.
  Future<List<Map<String, dynamic>>> fetchInvoiceHeaders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final headers = await _fetchAllPages('/invoices', {
        ..._salespersonFilterParams(),
        ..._dateRangeParams(startDate: startDate, endDate: endDate),
      });
      return _filterBySalesperson(headers);
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchInvoiceHeaders error: $e');
      throw Exception('Failed to fetch invoice list from Zoho: $e');
    }
  }

  // 17. Full invoice list with line items — powers reports that need lines
  // (Item Sales, customer sales summaries, transactions summary). Not used
  // by the sales invoice list page (see [fetchInvoiceHeaders]).
  Future<List<Map<String, dynamic>>> fetchInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final headers = await fetchInvoiceHeaders(
        startDate: startDate,
        endDate: endDate,
      );
      final details = <Map<String, dynamic>>[];
      for (final header in headers) {
        final id = header['invoice_id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          details.add(await fetchInvoiceDetail(id));
        } on Exception catch (e) {
          // Skip invoices whose detail fails to load rather than failing the whole report.
          AppLogger.error('ZohoApi', 'fetchInvoiceDetail($id) error: $e');
        }
      }
      return _filterBySalesperson(details);
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchInvoices error: $e');
      throw Exception('Failed to fetch invoices from Zoho: $e');
    }
  }

  // 18. Single expense detail (GET /expenses/{id}) — the list endpoint only
  // returns expense headers, so itemized line items must be fetched per-expense.
  Future<Map<String, dynamic>> fetchExpenseDetail(String expenseId) async {
    final response = await _dio.get<dynamic>('/expenses/$expenseId');
    if (response.statusCode != 200) {
      throw Exception(
        'GET /expenses/$expenseId failed: ${response.statusCode}',
      );
    }
    return jsonMap(response.data is Map ? (response.data as Map)['expense'] : null);
  }

  // 18b. Expense list headers only (GET /expenses) — powers the expense list
  // page. Includes total/account_name/description; no N detail calls.
  // Scoped to the session cash ledger via paid_through_account_id.
  Future<List<Map<String, dynamic>>> fetchExpenseHeaders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      return await _fetchAllPages('/expenses', {
        ..._paidThroughAccountFilterParams(),
        ..._dateRangeParams(startDate: startDate, endDate: endDate),
      });
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchExpenseHeaders error: $e');
      throw Exception('Failed to fetch expense list from Zoho: $e');
    }
  }

  // 19. Full expense list with itemized line items — powers Expense Summary
  // and Transactions Summary reports (not the expense list page).
  Future<List<Map<String, dynamic>>> fetchExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final headers = await fetchExpenseHeaders(
        startDate: startDate,
        endDate: endDate,
      );
      final details = <Map<String, dynamic>>[];
      for (final header in headers) {
        final id = header['expense_id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          details.add(await fetchExpenseDetail(id));
        } on Exception catch (e) {
          // Skip expenses whose detail fails to load rather than failing the whole report.
          AppLogger.error('ZohoApi', 'fetchExpenseDetail($id) error: $e');
        }
      }
      return details;
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchExpenses error: $e');
      throw Exception('Failed to fetch expenses from Zoho: $e');
    }
  }

  // 20. Single customer-payment detail (GET /customerpayments/{id}).
  Future<Map<String, dynamic>> fetchReceiptDetail(String paymentId) async {
    final response = await _dio.get<dynamic>('/customerpayments/$paymentId');
    if (response.statusCode != 200) {
      throw Exception(
        'GET /customerpayments/$paymentId failed: ${response.statusCode}',
      );
    }
    return jsonMap(response.data is Map ? (response.data as Map)['payment'] : null);
  }

  // 20b. Full customer-payment (receipt) list — powers the Receipt list page,
  // Invoice Receipts Summary and Transactions Summary reports.
  // Scoped via reference_number_startswith = {prefix}RCT- (app series lives
  // in reference_number; Zoho payments have no salesperson_id).
  Future<List<Map<String, dynamic>>> fetchReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      return await _fetchAllPages('/customerpayments', {
        ..._receiptSeriesReferenceFilterParams(),
        ..._dateRangeParams(startDate: startDate, endDate: endDate),
      });
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchReceipts error: $e');
      throw Exception('Failed to fetch receipts from Zoho: $e');
    }
  }

  // 21. Single credit-note detail (GET /creditnotes/{id}) — the list endpoint
  // only returns headers, so line items must be fetched per-credit-note.
  Future<Map<String, dynamic>> fetchSalesReturnDetail(
    String creditNoteId,
  ) async {
    final response = await _dio.get<dynamic>('/creditnotes/$creditNoteId');
    if (response.statusCode != 200) {
      throw Exception(
        'GET /creditnotes/$creditNoteId failed: ${response.statusCode}',
      );
    }
    return jsonMap(response.data is Map ? (response.data as Map)['creditnote'] : null);
  }

  // 21b. Sales-return list headers only (GET /creditnotes) — powers the
  // sales return list page. Includes total; no line items / no N detail calls.
  Future<List<Map<String, dynamic>>> fetchSalesReturnHeaders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final headers = await _fetchAllPages('/creditnotes', {
        ..._salespersonFilterParams(),
        ..._dateRangeParams(startDate: startDate, endDate: endDate),
      });
      return _filterSalesReturnsByLocation(headers);
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchSalesReturnHeaders error: $e');
      throw Exception('Failed to fetch sales return list from Zoho: $e');
    }
  }

  // 22. Full sales-return (credit note) list with line items — powers the
  // Sales Returns reports (not the list page). Location is applied after
  // detail load so list-header rows missing `location_id` are not dropped early.
  Future<List<Map<String, dynamic>>> fetchSalesReturns({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final headers = await _fetchAllPages('/creditnotes', {
        ..._salespersonFilterParams(),
        ..._dateRangeParams(startDate: startDate, endDate: endDate),
      });
      final details = <Map<String, dynamic>>[];
      for (final header in headers) {
        final id = header['creditnote_id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          details.add(await fetchSalesReturnDetail(id));
        } on Exception catch (e) {
          // Skip returns whose detail fails to load rather than failing the whole report.
          AppLogger.error(
            'ZohoApi',
            'fetchSalesReturnDetail($id) error: $e',
          );
        }
      }
      return _filterSalesReturnsByLocation(details);
    } on Exception catch (e) {
      AppLogger.error('ZohoApi', 'fetchSalesReturns error: $e');
      throw Exception('Failed to fetch sales returns from Zoho: $e');
    }
  }

  List<Map<String, dynamic>> _filterSalesReturnsByLocation(
    List<Map<String, dynamic>> rows,
  ) {
    final locationId = _dbService.getCurrentSalesperson()?.locationId;
    if (locationId == null || locationId.isEmpty) return rows;
    return rows.where((j) {
      final locId = j['location_id']?.toString();
      return locId == null || locId.isEmpty || locId == locationId;
    }).toList();
  }
}
