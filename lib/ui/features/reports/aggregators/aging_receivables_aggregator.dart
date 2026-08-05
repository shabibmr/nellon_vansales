import '../../../../domain/models/open_invoice.dart';

/// Aging bucket boundaries (in days outstanding since invoice date).
enum AgingBucket { d0_15, d15_30, d30_60, d60plus }

extension AgingBucketLabel on AgingBucket {
  String get label {
    switch (this) {
      case AgingBucket.d0_15:
        return '0-15';
      case AgingBucket.d15_30:
        return '15-30';
      case AgingBucket.d30_60:
        return '30-60';
      case AgingBucket.d60plus:
        return '>60';
    }
  }
}

/// Per-customer aggregation of outstanding balances split into aging buckets.
class AgingRow {
  final String customerId;
  final String customerName;
  final Map<AgingBucket, double> buckets;

  AgingRow({
    required this.customerId,
    required this.customerName,
    Map<AgingBucket, double>? buckets,
  }) : buckets = buckets ??
            {
              AgingBucket.d0_15: 0.0,
              AgingBucket.d15_30: 0.0,
              AgingBucket.d30_60: 0.0,
              AgingBucket.d60plus: 0.0,
            };

  double amount(AgingBucket b) => buckets[b] ?? 0.0;

  double get total => buckets.values.fold(0.0, (sum, v) => sum + v);
}

/// Available sort fields for the aging receivables report.
enum AgingSortField { name, total }

/// Typed payload for the aging report containing invoices and customer name mappings.
class AgingReportData {
  final List<OpenInvoice> invoices;
  final Map<String, String> customerNames;

  const AgingReportData({
    required this.invoices,
    required this.customerNames,
  });
}

/// Pure, framework-agnostic aggregator for computing aging receivables report data.
class AgingReceivablesAggregator {
  /// Buckets every outstanding invoice by age, aggregates per customer, and sorts output rows.
  static List<AgingRow> aggregate({
    required List<OpenInvoice> openInvoices,
    required Map<String, String> customerNames,
    DateTime? asOfDate,
    AgingSortField sortField = AgingSortField.total,
    bool sortAscending = false,
  }) {
    final today = asOfDate ?? DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final map = <String, AgingRow>{};

    for (final inv in openInvoices) {
      if (inv.balance <= 0) continue;

      final invDay = DateTime(inv.date.year, inv.date.month, inv.date.day);
      final days = todayDay.difference(invDay).inDays;

      final AgingBucket bucket;
      if (days <= 15) {
        bucket = AgingBucket.d0_15;
      } else if (days <= 30) {
        bucket = AgingBucket.d15_30;
      } else if (days <= 60) {
        bucket = AgingBucket.d30_60;
      } else {
        bucket = AgingBucket.d60plus;
      }

      final row = map.putIfAbsent(
        inv.customerId,
        () => AgingRow(
          customerId: inv.customerId,
          customerName: customerNames[inv.customerId] ?? inv.customerId,
        ),
      );
      row.buckets[bucket] = row.amount(bucket) + inv.balance;
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case AgingSortField.name:
          cmp = a.customerName.toLowerCase().compareTo(
            b.customerName.toLowerCase(),
          );
          break;
        case AgingSortField.total:
          cmp = a.total.compareTo(b.total);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }

  /// Filters [rows] by checking if [query] matches customer name or customer ID.
  static List<AgingRow> filter(List<AgingRow> rows, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where(
          (r) =>
              r.customerName.toLowerCase().contains(q) ||
              r.customerId.toLowerCase().contains(q),
        )
        .toList();
  }
}
