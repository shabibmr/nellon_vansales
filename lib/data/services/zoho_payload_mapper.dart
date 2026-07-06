/// Pure map→map transforms that turn locally-stored transaction payloads
/// (the dual-purpose `Model.toJson()` output persisted in the Hive sync queue)
/// into clean request bodies that match the official Zoho REST schemas.
///
/// Why this exists: each `Model.toJson()` doubles as the queue-storage format
/// AND the API body, so it carries local-only bookkeeping keys (`id`,
/// `isPendingSync`, `customer_name`, …) plus fully-nested `item` objects needed
/// to round-trip via `fromJson`. Those must stay in storage but must NOT be sent
/// to Zoho. Rather than mutate `toJson()` (which would break local persistence),
/// every `syncX` method in [ZohoApiClient] runs the stored map through the
/// matching whitelist builder here immediately before posting.
///
/// These functions are intentionally free of Flutter/Dio dependencies so they
/// can be unit-tested in isolation against real `Model.toJson()` fixtures.
class ZohoPayloadMapper {
  const ZohoPayloadMapper._();

  /// Copies [key] from [src] into [dst] only when present and non-null.
  static void _putIfPresent(
    Map<String, dynamic> dst,
    Map<String, dynamic> src,
    String key,
  ) {
    if (src.containsKey(key) && src[key] != null) {
      dst[key] = src[key];
    }
  }

  /// Reduces a stored `line_items` array to the whitelisted primitive keys,
  /// dropping nested `item`/`invoiceLineItem` objects and duplicate keys.
  static List<Map<String, dynamic>> _cleanLineItems(
    dynamic rawLines,
    List<String> allowedKeys,
  ) {
    if (rawLines is! List) return const [];
    return rawLines.whereType<Map>().map((line) {
      final map = Map<String, dynamic>.from(line);
      final cleaned = <String, dynamic>{};
      for (final key in allowedKeys) {
        if (map.containsKey(key) && map[key] != null) {
          cleaned[key] = map[key];
        }
      }
      return cleaned;
    }).toList();
  }

  // --- Contact / Customer (POST /contacts) ---------------------------------

  /// Whitelists a contact create payload to the Zoho `create-a-contact-request`
  /// schema. Drops local keys (`id`, `contact_id`, `name`, `outstandingBalance`,
  /// `route_id`, `sequence`, `isPendingSync`, root `latitude`/`longitude`) — GPS
  /// still travels via `custom_fields` (cf_latitude / cf_longitude).
  static Map<String, dynamic> zohoContactPayload(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final key in const [
      'contact_name',
      'company_name',
      'email',
      'phone',
      'billing_address',
      'credit_limit',
      'custom_fields',
    ]) {
      _putIfPresent(out, raw, key);
    }
    return out;
  }

  // --- Sales Invoice (POST /invoices) --------------------------------------

  /// Whitelists an invoice create payload to `create-an-invoice-request`.
  /// Drops `id`, `invoice_id`, `customer_name`, `isPendingSync`, `round_off`,
  /// and the nested `line_items[].item` object.
  static Map<String, dynamic> zohoInvoicePayload(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final key in const [
      'customer_id',
      'invoice_number',
      'date',
      'due_date',
      'notes',
      'location_id',
    ]) {
      _putIfPresent(out, raw, key);
    }
    out['line_items'] = _cleanLineItems(raw['line_items'], const [
      'item_id',
      'quantity',
      'rate',
      'tax_percentage',
      'discount',
    ]);
    return out;
  }

  // --- Sales Order (POST/PUT /salesorders) ---------------------------------

  /// Whitelists a sales-order create/update payload to
  /// `create-a-sales-order-request`. Drops `id`, `salesorder_id`,
  /// `customer_name`, `isPendingSync`, `round_off`, `status`,
  /// `converted_invoice_number`, `zoho_order_id`, and `line_items[].item`.
  static Map<String, dynamic> zohoSalesOrderPayload(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final key in const [
      'customer_id',
      'salesorder_number',
      'date',
      'shipment_date',
      'notes',
      'location_id',
    ]) {
      _putIfPresent(out, raw, key);
    }
    out['line_items'] = _cleanLineItems(raw['line_items'], const [
      'item_id',
      'quantity',
      'rate',
      'tax_percentage',
      'discount',
    ]);
    return out;
  }

  // --- Customer Payment / Receipt (POST /customerpayments) -----------------

  /// Whitelists a receipt payload to `create-a-payment-request`. Drops `id`,
  /// `payment_id`, `payment_number`, `customer_name`, `isPendingSync`, and the
  /// non-standard `invoices[].invoice_number`.
  static Map<String, dynamic> zohoReceiptPayload(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final key in const [
      'customer_id',
      'payment_mode',
      'amount',
      'date',
      'reference_number',
      'location_id',
    ]) {
      _putIfPresent(out, raw, key);
    }
    out['invoices'] = _cleanLineItems(raw['invoices'], const [
      'invoice_id',
      'amount_applied',
    ]);
    return out;
  }

  // --- Credit Note / Sales Return (POST /creditnotes) ----------------------

  /// Whitelists a credit-note payload to `create-a-credit-note-request`. Drops
  /// `id`, `creditnote_id`, `customer_name`, `isPendingSync`, and the nested
  /// `line_items[].invoice_number` / `line_items[].invoiceLineItem`.
  static Map<String, dynamic> zohoCreditNotePayload(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final key in const [
      'customer_id',
      'creditnote_number',
      'date',
      'location_id',
      'reason',
    ]) {
      _putIfPresent(out, raw, key);
    }
    out['line_items'] = _cleanLineItems(raw['line_items'], const [
      'item_id',
      'quantity',
      'rate',
      'invoice_id',
    ]);
    return out;
  }

  // --- Expense (POST /expenses) --------------------------------------------

  /// Builds an itemized Zoho expense body from the stored expense map.
  ///
  /// The van app models an expense as multiple category lines; Zoho's
  /// `create-an-expense-request` requires root `date`, `account_id`, `amount`,
  /// `paid_through_account_id` and supports an optional itemized `line_items`
  /// array. [resolvedLines] carries each line already resolved to a real Zoho
  /// `account_id` (see [ZohoApiClient.syncExpense]); [paidThroughAccountId] is
  /// the deposit/cash account the expense was paid from.
  ///
  /// Root `account_id` is set to the first line's account as a schema satisfier
  /// while the per-line accounts drive the actual itemized posting.
  static Map<String, dynamic> zohoExpensePayload(
    Map<String, dynamic> raw, {
    required List<Map<String, dynamic>> resolvedLines,
    required String paidThroughAccountId,
  }) {
    final total = resolvedLines.fold<double>(
      0.0,
      (sum, l) => sum + ((l['amount'] as num?)?.toDouble() ?? 0.0),
    );
    final out = <String, dynamic>{
      'paid_through_account_id': paidThroughAccountId,
      'amount': total,
      if (resolvedLines.isNotEmpty)
        'account_id': resolvedLines.first['account_id'],
      'line_items': resolvedLines
          .map(
            (l) => <String, dynamic>{
              'account_id': l['account_id'],
              'amount': l['amount'],
              if (l['description'] != null &&
                  (l['description'] as String).isNotEmpty)
                'description': l['description'],
            },
          )
          .toList(),
    };
    for (final key in const ['date', 'location_id', 'reference_number']) {
      _putIfPresent(out, raw, key);
    }
    return out;
  }

  // --- Stock Transfer (POST inventory /transferorders) ---------------------

  /// Whitelists a stock-transfer payload to the Zoho **Inventory**
  /// `create-a-transfer-order` schema. Maps the model's local `notes` field to
  /// Zoho's `description`, reduces line items to `{item_id, name,
  /// quantity_transfer}`, and drops local keys (`id`, `transfer_order_id`,
  /// `direction`, `isPendingSync`, `zoho_transfer_id`, `location_id`) plus the
  /// duplicate `line_items[].quantity` and nested `line_items[].item`.
  static Map<String, dynamic> zohoStockTransferPayload(
    Map<String, dynamic> raw,
  ) {
    final out = <String, dynamic>{};
    for (final key in const [
      'transfer_order_number',
      'date',
      'from_location_id',
      'to_location_id',
    ]) {
      _putIfPresent(out, raw, key);
    }
    // Zoho expects `description`; the local model stores the remark under `notes`.
    if (raw['notes'] != null && (raw['notes'] as String).isNotEmpty) {
      out['description'] = raw['notes'];
    }
    out['line_items'] = _cleanLineItems(raw['line_items'], const [
      'item_id',
      'name',
      'quantity_transfer',
    ]);
    return out;
  }
}
