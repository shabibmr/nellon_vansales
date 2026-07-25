import 'dart:async';

import 'app_logger.dart';
import 'hive_database_service.dart';
import 'zoho_api_client.dart';

/// Per-transaction-type offline document number tag + Zoho seed-query params (B5).
enum DocType {
  invoice('INV'),
  salesOrder('SO'),
  receipt('RCT'),
  creditNote('CN');

  /// Short tag embedded in the number, e.g. `SHB-INV-00001`.
  final String tag;

  const DocType(this.tag);
}

/// Generates duplicate-proof, per-salesperson offline document numbers
/// (`<prefix><TAG>-#####`, B5) and seeds each type's counter from the higher
/// of Zoho's existing numbers and the local queue/history.
///
/// Counters are monotonic — [seedCounters] only ever raises a counter, never
/// lowers it, so an offline device never regresses below numbers it already
/// issued.
class DocumentNumberService {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  DocumentNumberService({
    required HiveDatabaseService dbService,
    required ZohoApiClient apiClient,
  })  : _dbService = dbService,
        _apiClient = apiClient;

  /// Serializes counter read-increment-write across concurrent callers within
  /// this isolate (bloc saves can race). Each call chains onto the tail of
  /// the previous one so only one read-increment-write is in flight at a time.
  Future<dynamic> _tail = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // Advance the chain even when [action] fails so later callers are not
    // blocked; the original [result] still surfaces the error to its awaiter.
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Returns the next document number for [type] and persists the
  /// incremented counter, e.g. `'SHB-INV-00001'`.
  ///
  /// Throws [StateError] when the session has no `voucher_prefix` — this
  /// must fail loudly rather than emit an unprefixed, org-collision-prone
  /// number.
  Future<String> nextNumber(DocType type) {
    return _synchronized(() async {
      final prefix = _requiredPrefix();
      final current = _dbService.getDocCounter(type.tag) ?? 1;
      await _dbService.setDocCounter(type.tag, current + 1);
      return _format(prefix, type, current);
    });
  }

  /// Re-seeds [type] from Zoho (duplicate-collision recovery path) and
  /// returns a fresh number one past the new maximum.
  Future<String> reseedAndNext(DocType type) {
    return _synchronized(() async {
      final prefix = _requiredPrefix();
      final zohoMax = await _zohoMaxCounter(type, prefix);
      final localMax = _localMaxCounter(type, prefix);
      final next = [
        zohoMax,
        localMax,
        _dbService.getDocCounter(type.tag) ?? 1,
      ].reduce((a, b) => a > b ? a : b);
      await _dbService.setDocCounter(type.tag, next + 1);
      return _format(prefix, type, next);
    });
  }

  /// Seeds every type's counter as `max(Zoho, local queue, local history) + 1`.
  ///
  /// Monotonic — never lowers a persisted counter. Safe to call when offline:
  /// the Zoho leg is best-effort per type and failures are swallowed, keeping
  /// whatever counter is already persisted (a fresh install offline before
  /// the first seed starts counters at 1; the sync-time duplicate-rejection
  /// retry is the backstop).
  Future<void> seedCounters() async {
    // Fully defensive: unawaited from SyncWorker after a clean sync batch, so
    // any failure (missing Hive session, offline Zoho, uninitialized test fakes)
    // must never surface as an uncaught async error.
    try {
      final prefix = _dbService.voucherPrefix;
      if (prefix == null || prefix.isEmpty) return;

      for (final type in DocType.values) {
        try {
          final zohoMax = await _zohoMaxCounter(type, prefix);
          final localMax = _localMaxCounter(type, prefix);
          final candidate = (zohoMax > localMax ? zohoMax : localMax) + 1;
          final existing = _dbService.getDocCounter(type.tag) ?? 1;
          if (candidate > existing) {
            await _dbService.setDocCounter(type.tag, candidate);
          }
        } catch (e) {
          AppLogger.error(
            'DocumentNumberService',
            'Seed failed for ${type.tag}: $e',
          );
        }
      }
    } catch (e) {
      AppLogger.error('DocumentNumberService', 'seedCounters aborted: $e');
    }
  }

  String _requiredPrefix() {
    final prefix = _dbService.voucherPrefix;
    if (prefix == null || prefix.isEmpty) {
      throw StateError(
        'No voucher prefix bound to this session — cannot generate a document number.',
      );
    }
    return prefix;
  }

  String _format(String prefix, DocType type, int counter) {
    return '$prefix${type.tag}-${counter.toString().padLeft(5, '0')}';
  }

  /// Parses the trailing counter out of [number] if it matches
  /// `'<prefix><TAG>-#####'`; returns null for numbers that aren't ours
  /// (e.g. numbers from another salesperson's prefix).
  static int? counterOf(String number, String prefix, DocType type) {
    final expectedPrefix = '$prefix${type.tag}-';
    if (!number.startsWith(expectedPrefix)) return null;
    return int.tryParse(number.substring(expectedPrefix.length));
  }

  Future<int> _zohoMaxCounter(DocType type, String prefix) async {
    final params = _seedParams(type);
    if (params == null) return 0;
    final numbers = await _apiClient.fetchDocumentNumbersStartingWith(
      endpoint: params.endpoint,
      startswithParam: params.startswithParam,
      numberKey: params.numberKey,
      prefix: '$prefix${type.tag}-',
    );
    var max = 0;
    for (final n in numbers) {
      final c = counterOf(n, prefix, type);
      if (c != null && c > max) max = c;
    }
    return max;
  }

  int _localMaxCounter(DocType type, String prefix) {
    var max = 0;
    void consider(String? number) {
      if (number == null) return;
      final c = counterOf(number, prefix, type);
      if (c != null && c > max) max = c;
    }

    for (final item in _dbService.getSyncQueue()) {
      switch (type) {
        case DocType.invoice:
          if (item.type == 'invoice') {
            consider(item.payload['invoice_number']?.toString());
          }
        case DocType.salesOrder:
          if (item.type == 'sales_order') {
            consider(item.payload['salesorder_number']?.toString());
          }
        case DocType.receipt:
          if (item.type == 'receipt') {
            consider(item.payload['payment_number']?.toString());
          }
        case DocType.creditNote:
          if (item.type == 'return') {
            consider(item.payload['creditnote_number']?.toString());
          }
      }
    }

    switch (type) {
      case DocType.invoice:
        for (final inv in _dbService.getLocalInvoices()) {
          consider(inv.invoiceNumber);
        }
      case DocType.salesOrder:
        for (final so in _dbService.getLocalOrders()) {
          consider(so.orderNumber);
        }
      case DocType.receipt:
        for (final r in _dbService.getLocalReceipts()) {
          consider(r.paymentNumber);
        }
      case DocType.creditNote:
        for (final r in _dbService.getLocalReturns()) {
          consider(r.creditNoteNumber);
        }
    }

    return max;
  }

  _SeedParams? _seedParams(DocType type) {
    switch (type) {
      case DocType.invoice:
        return const _SeedParams(
          endpoint: '/invoices',
          startswithParam: 'invoice_number_startswith',
          numberKey: 'invoice_number',
        );
      case DocType.salesOrder:
        return const _SeedParams(
          endpoint: '/salesorders',
          startswithParam: 'salesorder_number_startswith',
          numberKey: 'salesorder_number',
        );
      case DocType.creditNote:
        return const _SeedParams(
          endpoint: '/creditnotes',
          startswithParam: 'creditnote_number_startswith',
          numberKey: 'creditnote_number',
        );
      case DocType.receipt:
        // Receipt app-numbers travel to Zoho as `reference_number` (B4);
        // Zoho's own `payment_number` stays auto-generated.
        return const _SeedParams(
          endpoint: '/customerpayments',
          startswithParam: 'reference_number_startswith',
          numberKey: 'reference_number',
        );
    }
  }
}

class _SeedParams {
  final String endpoint;
  final String startswithParam;
  final String numberKey;

  const _SeedParams({
    required this.endpoint,
    required this.startswithParam,
    required this.numberKey,
  });
}
