import '../models/sales_return_model.dart';

/// Pure helpers for credit-note create / apply. No Dio.
class SalesReturnSync {
  const SalesReturnSync._();

  /// Permanent Zoho credit-note id stamped after a successful create.
  ///
  /// Ignores `creditnote_id` — [SalesReturnModel.toJson] stores the local
  /// id under that key.
  static String? existingRemoteId(Map<String, dynamic> raw) {
    final id = raw['zoho_credit_note_id']?.toString() ?? '';
    if (id.isEmpty || id.startsWith('temp_')) return null;
    return id;
  }

  /// Invoice id shared by every line, or null when lines disagree / are empty.
  static String? sharedInvoiceId(Map<String, dynamic> raw) {
    final lines = raw['line_items'];
    if (lines is! List || lines.isEmpty) return null;
    String? shared;
    for (final line in lines) {
      if (line is! Map) return null;
      final id = line['invoice_id']?.toString() ?? '';
      if (id.isEmpty || id.startsWith('temp_')) return null;
      if (shared == null) {
        shared = id;
      } else if (shared != id) {
        return null;
      }
    }
    return shared;
  }

  /// Apply-credit rows grouped by invoice, using domain line totals.
  static List<Map<String, dynamic>> applyInvoices(Map<String, dynamic> raw) {
    final ret = SalesReturnModel.fromJson(raw);
    final byInvoice = <String, double>{};
    for (final line in ret.items) {
      final id = line.invoiceId;
      if (id == null || id.isEmpty || id.startsWith('temp_')) continue;
      byInvoice[id] = (byInvoice[id] ?? 0) + line.total;
    }
    return [
      for (final e in byInvoice.entries)
        if (e.value > 0)
          {'invoice_id': e.key, 'amount_applied': e.value},
    ];
  }

  /// True when the create/GET envelope already used the credit (query
  /// `invoice_id` applies at create) so a follow-up apply would fail.
  static bool alreadyApplied(
    Map<String, dynamic>? creditnote,
    List<Map<String, dynamic>> wanted,
  ) {
    if (creditnote == null || wanted.isEmpty) return false;
    final balance = (creditnote['balance'] as num?)?.toDouble();
    if (balance != null && balance == 0) return true;
    final credited = creditnote['invoices_credited'];
    if (credited is! List || credited.isEmpty) return false;
    final creditedIds = <String>{};
    for (final row in credited) {
      if (row is! Map) continue;
      final id = row['invoice_id']?.toString() ?? '';
      if (id.isNotEmpty) creditedIds.add(id);
    }
    return wanted.every((w) => creditedIds.contains(w['invoice_id']));
  }

  /// Zoho apply errors that mean the credit is already on the invoice.
  static bool isAlreadyAppliedError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('already applied') ||
        message.contains('already been applied') ||
        message.contains('no unused') ||
        message.contains('unused credit') ||
        (message.contains('credits available') && message.contains('0'));
  }
}
