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
  ///
  /// When `tax_id` is allowed but only present on nested `item` /
  /// `invoiceLineItem.item`, it is lifted onto the cleaned line (UAE orgs
  /// require tax_id — tax_percentage alone yields EXEMPT).
  static List<Map<String, dynamic>> _cleanLineItems(
    dynamic rawLines,
    List<String> allowedKeys,
  ) {
    if (rawLines is! List) return const [];
    final allowTaxId = allowedKeys.contains('tax_id');
    return rawLines.whereType<Map<dynamic, dynamic>>().map((line) {
      final map = Map<String, dynamic>.from(line);
      final cleaned = <String, dynamic>{};
      for (final key in allowedKeys) {
        if (map.containsKey(key) && map[key] != null) {
          cleaned[key] = map[key];
        }
      }
      if (allowTaxId) {
        final existing = cleaned['tax_id']?.toString() ?? '';
        if (existing.isEmpty) {
          final lifted = _extractNestedTaxId(map);
          if (lifted != null) cleaned['tax_id'] = lifted;
        }
      }
      return cleaned;
    }).toList();
  }

  /// Reads tax_id from nested local payload shapes (item / invoiceLineItem).
  static String? _extractNestedTaxId(Map<dynamic, dynamic> map) {
    String? from(dynamic node) {
      if (node is! Map) return null;
      final id = (node['tax_id'] ?? node['taxId'])?.toString();
      if (id != null && id.isNotEmpty) return id;
      return null;
    }

    final direct = from(map);
    if (direct != null) return direct;
    final fromItem = from(map['item']);
    if (fromItem != null) return fromItem;
    final invLine = map['invoiceLineItem'];
    if (invLine is Map) {
      final fromInv = from(invLine);
      if (fromInv != null) return fromInv;
      return from(invLine['item']);
    }
    return null;
  }

  /// Fills missing line `tax_id` values using [resolveTaxId].
  ///
  /// UAE: lines without `tax_id` post as **EXEMPT** regardless of customer
  /// `tax_treatment` (`vat_registered` / `vat_not_registered`). Van sales
  /// must send Standard Rate (or the item's explicit tax_id) so unregistered
  /// customers are still charged VAT.
  ///
  /// [resolveTaxId] receives the line's `tax_percentage` (nullable; may be 0
  /// when unset) and must return a Zoho tax_id or null. Callers should treat
  /// null/0% as "use default Standard Rate", not Zero Rate, unless the line
  /// already carries an explicit tax_id.
  static Map<String, dynamic> withResolvedLineTaxIds(
    Map<String, dynamic> payload, {
    required String? Function(double? taxPercentage) resolveTaxId,
  }) {
    final rawLines = payload['line_items'];
    if (rawLines is! List) return payload;
    final lines = rawLines.map((line) {
      if (line is! Map) return line;
      final m = Map<String, dynamic>.from(line);
      final existing = m['tax_id']?.toString() ?? '';
      if (existing.isNotEmpty) return m;
      final pctRaw = m['tax_percentage'];
      final pct = pctRaw is num ? pctRaw.toDouble() : null;
      final resolved = resolveTaxId(pct);
      if (resolved != null && resolved.isNotEmpty) {
        m['tax_id'] = resolved;
      }
      // Never forward exemption markers — whitelist builders omit them, but
      // stored queue maps must not reintroduce EXEMPT via residual keys.
      m.remove('tax_exemption_id');
      m.remove('tax_exemption_code');
      return m;
    }).toList();
    return {...payload, 'line_items': lines};
  }

  // --- Contact / Customer (POST /contacts) ---------------------------------

  /// Whitelists a contact create payload to the Zoho `create-a-contact-request`
  /// schema. Drops local keys (`id`, `contact_id`, `name`, `outstandingBalance`,
  /// `route_id`, `sequence`, `isPendingSync`, root `latitude`/`longitude`) — GPS
  /// travels via `billing_address` (latitude / longitude).
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
      // Option B: header location is the KGT primary business location;
      // salesperson_id identifies who made the sale (see ZohoApiClient
      // _withSalespersonId / _withPrimaryHeaderLocation).
      'salesperson_id',
    ]) {
      _putIfPresent(out, raw, key);
    }
    out['line_items'] = _cleanLineItems(raw['line_items'], const [
      'item_id',
      'quantity',
      'rate',
      'tax_id', // required for UAE VAT; percentage alone → EXEMPT
      'tax_percentage',
      'discount',
      'unit',
      // Multi-UOM: quantity/rate/unit are in the selected unit; the id ties
      // the line to the item's Zoho unit conversion (verified live —
      // /salesorders echoes it back with base_unit + conversion_rate).
      // DTOs omit the key for base-unit lines, so it is only sent when set.
      'unit_conversion_id',
      // Option B: the van (storage location) lives on line items, never the
      // header — this is what actually deducts van stock.
      'location_id',
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
      'salesperson_id',
      // Customer/PO reference from Zoho list/detail (optional on create).
      'reference_number',
    ]) {
      _putIfPresent(out, raw, key);
    }
    out['line_items'] = _cleanLineItems(raw['line_items'], const [
      'item_id',
      'quantity',
      'rate',
      'tax_id', // required for UAE VAT; percentage alone → EXEMPT
      'tax_percentage',
      'discount',
      'unit',
      'unit_conversion_id', // multi-UOM; omitted for base-unit lines
      'location_id', // Option B: van lives on line items, not header
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
      'sales_person_id',
      // Deposit account: the session salesperson's personal cash ledger.
      'account_id',
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
  ///
  /// Local Hive/UI field is `reason` (free-text). Books create schema has
  /// `notes`, not `reason` — map it the same way transfers map `notes` →
  /// `description`. Do not send `reason_for_credit_debit_note` (UAE enum).
  static Map<String, dynamic> zohoCreditNotePayload(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final key in const [
      'customer_id',
      'creditnote_number',
      'date',
      'location_id',
      'salesperson_id',
    ]) {
      _putIfPresent(out, raw, key);
    }
    final reason = raw['reason']?.toString() ?? '';
    if (reason.isNotEmpty) {
      out['notes'] = reason;
    } else {
      _putIfPresent(out, raw, 'notes');
    }
    out['line_items'] = _cleanLineItems(raw['line_items'], const [
      'item_id',
      'quantity',
      'rate',
      'tax_id', // required for UAE VAT; percentage alone → EXEMPT
      'tax_percentage',
      'invoice_id',
      'invoice_item_id',
      'unit',
      'unit_conversion_id', // multi-UOM; omitted for base-unit lines
      'location_id', // Option B: van lives on line items, not header
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
  ///
  /// Optional per-line `tax_id` is forwarded. When any line is taxable,
  /// [isInclusiveTax] should be true so the driver's cash amount is treated
  /// as VAT-inclusive (Zoho splits tax out instead of adding it).
  static Map<String, dynamic> zohoExpensePayload(
    Map<String, dynamic> raw, {
    required List<Map<String, dynamic>> resolvedLines,
    required String paidThroughAccountId,
    bool isInclusiveTax = false,
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
      if (isInclusiveTax) 'is_inclusive_tax': true,
      'line_items': resolvedLines
          .map(
            (l) {
              final line = <String, dynamic>{
                'account_id': l['account_id'],
                'amount': l['amount'],
                if (l['description'] != null &&
                    (l['description'] as String).isNotEmpty)
                  'description': l['description'],
              };
              final taxId = l['tax_id']?.toString() ?? '';
              if (taxId.isNotEmpty) line['tax_id'] = taxId;
              return line;
            },
          )
          .toList(),
    };
    for (final key in const ['date', 'location_id', 'reference_number']) {
      _putIfPresent(out, raw, key);
    }
    return out;
  }

  // --- Stock Transfer (POST books/v3 /transferorders) ----------------------

  /// Whitelists a stock-transfer payload to the Zoho Books v3
  /// `create-a-transfer-order` schema. Maps the model's local `notes` field to
  /// Zoho's `description`, reduces line items to `{item_id, name,
  /// quantity_transfer}`, and drops local keys (`id`, `transfer_order_id`,
  /// `transfer_order_number`, `direction`, `isPendingSync`, `zoho_transfer_id`,
  /// `location_id`) plus the duplicate `line_items[].quantity` and nested
  /// `line_items[].item`.
  ///
  /// Local `TO-TEMP-…` numbers are omitted so Zoho can auto-generate the
  /// series number (sending a temp number returns Books error 4097).
  static Map<String, dynamic> zohoStockTransferPayload(
    Map<String, dynamic> raw,
  ) {
    final out = <String, dynamic>{};
    for (final key in const [
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
    // Multi-UOM note: transfer quantities are ALWAYS converted to the item's
    // base unit before reaching the stored payload (`quantity_transfer` is
    // base-unit), so no unit keys are sent.
    out['line_items'] = _cleanLineItems(raw['line_items'], const [
      'item_id',
      'name',
      'quantity_transfer',
    ]);
    return out;
  }
}
