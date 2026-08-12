import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/thermal_paper_size.dart';
import '../../../domain/utils/amount_in_words.dart';

/// Shared ESC/POS layout helpers for 2" / 4" thermal tickets.
class EscPosTicketBuilder {
  EscPosTicketBuilder({
    required this.generator,
    required this.paperSize,
  }) : columns = paperSize.columns;

  final Generator generator;
  final ThermalPaperSize paperSize;
  final int columns;

  static final DateFormat ticketDateFormat = DateFormat('dd-MM-yyyy');
  static final DateFormat dateOnlyFormat = DateFormat('dd MMM yyyy');

  /// Item table cell widths (shared by header + rows).
  static const int slW = 3;
  static const int qtyW = 7;
  static const int amountW = 10;
  // |Sl|Item|Qty|Amount| → 5 pipe characters
  static const int _pipeCount = 5;

  int get nameW => columns - slW - qtyW - amountW - _pipeCount;

  /// Maps app paper size to esc_pos_utils [PaperSize].
  ///
  /// Layout width is driven by [ThermalPaperSize.columns] (4" = 64, 2" = 32).
  /// The library has no 112mm profile; 4" uses the widest stock option (mm80)
  /// for Generator image/row math only.
  static PaperSize toEscPosPaperSize(ThermalPaperSize size) {
    return switch (size) {
      ThermalPaperSize.inch2 => PaperSize.mm58,
      ThermalPaperSize.inch4 => PaperSize.mm80,
    };
  }

  /// Sanitizes text for Latin-1 thermal printers (common POS firmware).
  static String sanitize(String input) {
    return input
        .replaceAll('₹', 'Rs')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('•', '*')
        .replaceAll(RegExp(r'[^\x20-\x7E\n]'), '?');
  }

  /// Currency symbol + amount with a space (`AED 12.50`).
  String money(num amount, String symbol) {
    final cleanSymbol = sanitize(symbol).trim();
    final value = amount.toStringAsFixed(2);
    if (cleanSymbol.isEmpty) return value;
    return '$cleanSymbol $value';
  }

  /// Amount only for item table cells (no currency symbol).
  String amountOnly(num amount) => amount.toStringAsFixed(2);

  String truncate(String text, int max) {
    final clean = sanitize(text);
    if (max <= 0) return '';
    if (clean.length <= max) return clean;
    if (max <= 1) return clean.substring(0, max);
    return '${clean.substring(0, max - 1)}.';
  }

  /// Word-aware wrap; hard-breaks tokens longer than [width].
  static List<String> wrapText(String text, int width) {
    final clean = sanitize(text).trim();
    if (width <= 0) return clean.isEmpty ? const [] : [clean];
    if (clean.isEmpty) return const [];
    if (clean.length <= width) return [clean];

    final lines = <String>[];
    final words = clean.split(RegExp(r'\s+'));
    var current = StringBuffer();

    void flush() {
      if (current.isEmpty) return;
      lines.add(current.toString());
      current = StringBuffer();
    }

    for (final word in words) {
      if (word.length > width) {
        flush();
        var remaining = word;
        while (remaining.length > width) {
          lines.add(remaining.substring(0, width));
          remaining = remaining.substring(width);
        }
        if (remaining.isNotEmpty) current.write(remaining);
        continue;
      }

      if (current.isEmpty) {
        current.write(word);
      } else if (current.length + 1 + word.length <= width) {
        current.write(' $word');
      } else {
        flush();
        current.write(word);
      }
    }
    flush();
    return lines;
  }

  List<int> reset() => generator.reset();

  List<int> feed([int n = 2]) => generator.feed(n);

  List<int> cut() {
    // Prefer feed over hard cut — many mobile printers lack a cutter.
    return generator.feed(3);
  }

  List<int> divider() {
    final line = List.filled(columns, '-').join();
    return generator.text(line);
  }

  List<int> doubleDivider() {
    final line = List.filled(columns, '=').join();
    return generator.text(line);
  }

  List<int> center(
    String text, {
    bool bold = false,
    bool underline = false,
    bool reverse = false,
    PosTextSize width = PosTextSize.size1,
    PosTextSize height = PosTextSize.size1,
  }) {
    return generator.text(
      sanitize(text),
      styles: PosStyles(
        align: PosAlign.center,
        bold: bold,
        underline: underline,
        reverse: reverse,
        width: width,
        height: height,
      ),
    );
  }

  List<int> left(
    String text, {
    bool bold = false,
    bool underline = false,
    bool reverse = false,
    PosTextSize width = PosTextSize.size1,
    PosTextSize height = PosTextSize.size1,
  }) {
    return generator.text(
      sanitize(text),
      styles: PosStyles(
        align: PosAlign.left,
        bold: bold,
        underline: underline,
        reverse: reverse,
        width: width,
        height: height,
      ),
    );
  }

  List<int> leftRight(
    String leftText,
    String rightText, {
    bool bold = false,
    bool underline = false,
    bool reverse = false,
    PosTextSize width = PosTextSize.size1,
    PosTextSize height = PosTextSize.size1,
    /// When double-width, usable character columns are roughly half.
    int? layoutColumns,
  }) {
    final leftClean = sanitize(leftText);
    final rightClean = sanitize(rightText);
    final cols = layoutColumns ?? columns;
    final gap = cols - leftClean.length - rightClean.length;
    final line = gap >= 1
        ? '$leftClean${' ' * gap}$rightClean'
        : truncate(
            '$leftClean $rightClean',
            cols,
          );
    return generator.text(
      line,
      styles: PosStyles(
        align: PosAlign.left,
        bold: bold,
        underline: underline,
        reverse: reverse,
        width: width,
        height: height,
      ),
    );
  }

  /// Company letterhead + voucher title + No/Date meta line.
  List<int> header({
    required String orgName,
    String orgAddress = '',
    String orgPhone = '',
    String orgTrn = '',
    required String voucherTitle,
    required String voucherNumber,
    required DateTime date,
  }) {
    final bytes = <int>[];
    bytes.addAll(doubleDivider());
    bytes.addAll(
      center(
        orgName.toUpperCase(),
        bold: true,
        width: PosTextSize.size1,
        height: PosTextSize.size2,
      ),
    );

    final address = orgAddress.trim();
    if (address.isNotEmpty) {
      for (final line in wrapText(address, columns)) {
        bytes.addAll(center(line));
      }
    }
    final phone = orgPhone.trim();
    if (phone.isNotEmpty) {
      bytes.addAll(center('Phone: ${truncate(phone, columns - 7)}'));
    }
    final trn = orgTrn.trim();
    if (trn.isNotEmpty) {
      bytes.addAll(center('TRN: ${truncate(trn, columns - 5)}'));
    }

    bytes.addAll(divider());
    bytes.addAll(
      center(
        voucherTitle.toUpperCase(),
        bold: true,
        underline: true,
      ),
    );
    bytes.addAll(
      leftRight(
        'No: ${sanitize(voucherNumber)}',
        'Date: ${ticketDateFormat.format(date)}',
      ),
    );
    return bytes;
  }

  List<int> customerBlock({
    required String name,
    String? phone,
    String? address,
    String? trn,
  }) {
    final bytes = <int>[];
    bytes.addAll(divider());

    final nameLines = wrapText('Customer: ${sanitize(name)}', columns);
    for (var i = 0; i < nameLines.length; i++) {
      bytes.addAll(left(nameLines[i], bold: i == 0));
    }

    if (phone != null && phone.trim().isNotEmpty) {
      bytes.addAll(left('Phone: ${truncate(phone, columns - 7)}'));
    }

    final addr = address?.trim() ?? '';
    if (addr.isNotEmpty) {
      final wrapped = wrapText(addr, columns - 9);
      if (wrapped.isNotEmpty) {
        bytes.addAll(left('Address: ${wrapped.first}'));
        for (var i = 1; i < wrapped.length; i++) {
          bytes.addAll(left(wrapped[i]));
        }
      }
    }

    final customerTrn = trn?.trim() ?? '';
    if (customerTrn.isNotEmpty) {
      bytes.addAll(left('TRN: ${truncate(customerTrn, columns - 5)}'));
    }
    return bytes;
  }

  String _pipeRow({
    required String sl,
    required String name,
    required String qty,
    required String amount,
  }) {
    final nw = nameW < 1 ? 1 : nameW;
    final slCell = truncate(sl, slW).padLeft(slW);
    final nameCell = truncate(name, nw).padRight(nw);
    final qtyCell = truncate(qty, qtyW).padLeft(qtyW);
    final amountCell = truncate(amount, amountW).padLeft(amountW);
    return '|$slCell|$nameCell|$qtyCell|$amountCell|';
  }

  List<int> itemTableHeader() {
    final bytes = <int>[];
    bytes.addAll(divider());
    bytes.addAll(
      left(
        _pipeRow(
          sl: 'Sl',
          name: 'Item',
          qty: 'Qty',
          amount: 'Amount',
        ),
        bold: true,
      ),
    );
    bytes.addAll(divider());
    return bytes;
  }

  List<int> itemRow({
    required int serial,
    required String name,
    required num qty,
    required String amountText,
    String uom = '',
  }) {
    final nw = nameW < 1 ? 1 : nameW;
    final bytes = <int>[];
    final nameLines = wrapText(name, nw);
    final lines = nameLines.isEmpty ? <String>[''] : nameLines;

    final qtyNum = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    final unit = uom.trim();
    final qtyText = unit.isEmpty ? qtyNum : '$qtyNum $unit';

    for (var i = 0; i < lines.length; i++) {
      final isFirst = i == 0;
      bytes.addAll(
        left(
          _pipeRow(
            sl: isFirst ? serial.toString() : '',
            name: lines[i],
            qty: isFirst ? qtyText : '',
            amount: isFirst ? amountText : '',
          ),
        ),
      );
    }
    return bytes;
  }

  List<int> totalsBlock({
    required String symbol,
    String? currencyCode,
    double? subTotal,
    double? taxTotal,
    double? discountTotal,
    required double total,
    double? roundOff,
  }) {
    final bytes = <int>[];
    bytes.addAll(divider());
    if (subTotal != null) {
      bytes.addAll(leftRight('Subtotal', money(subTotal, symbol)));
    }
    if (taxTotal != null && taxTotal != 0) {
      bytes.addAll(leftRight('Tax', money(taxTotal, symbol)));
    }
    if (discountTotal != null && discountTotal != 0) {
      bytes.addAll(leftRight('Discount', money(discountTotal, symbol)));
    }
    if (roundOff != null && roundOff != 0) {
      bytes.addAll(leftRight('Round off', money(roundOff, symbol)));
    }

    // Bold + double-height TOTAL (no reverse). Double-width halves
    // usable columns, so lay out for ~columns/2.
    final totalCols = (columns / 2).floor().clamp(16, columns);
    bytes.addAll(
      leftRight(
        'TOTAL',
        money(total, symbol),
        bold: true,
        width: PosTextSize.size2,
        height: PosTextSize.size2,
        layoutColumns: totalCols,
      ),
    );

    bytes.addAll(amountInWordsBlock(
      total: total,
      symbol: symbol,
      currencyCode: currencyCode,
    ));
    return bytes;
  }

  /// Prints amount-in-words lines (wrapped).
  List<int> amountInWordsBlock({
    required num total,
    required String symbol,
    String? currencyCode,
  }) {
    final bytes = <int>[];
    bytes.addAll(divider());
    final unit = currencyUnitName(
      (currencyCode != null && currencyCode.trim().isNotEmpty)
          ? currencyCode
          : symbol,
    );
    final words = amountInWords(total, currencyName: unit);
    bytes.addAll(left('In words:', bold: true));
    for (final line in wrapText(words, columns)) {
      bytes.addAll(left(line));
    }
    return bytes;
  }

  List<int> footer({String? salespersonName}) {
    final bytes = <int>[];
    bytes.addAll(divider());
    if (salespersonName != null && salespersonName.trim().isNotEmpty) {
      bytes.addAll(
        left('Salesperson: ${truncate(salespersonName, columns - 13)}'),
      );
    }
    bytes.addAll(center('Thank you'));
    bytes.addAll(doubleDivider());
    bytes.addAll(cut());
    return bytes;
  }
}
