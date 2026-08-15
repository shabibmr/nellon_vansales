import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/thermal_paper_size.dart';
import '../../../domain/models/thermal_ticket_preview.dart';
import '../../../domain/utils/amount_in_words.dart';

/// Shared ESC/POS layout helpers for 2" / 4" thermal tickets.
class EscPosTicketBuilder {
  EscPosTicketBuilder({required this.generator, required this.paperSize})
    : columns = paperSize.columns;

  final Generator generator;
  final ThermalPaperSize paperSize;
  final int columns;

  /// Printed line units so far (double-height text counts as 2).
  int _lineUnits = 0;

  /// Visual stand-in for bytes emitted by [center], [left], [leftRight], and dividers.
  final List<ThermalPreviewLine> previewLines = [];

  /// Visible for tests and tail-padding math.
  int get lineUnits => _lineUnits;

  /// Appends [other]'s recorded preview lines (used when a tail builder is merged).
  void absorbPreviewFrom(EscPosTicketBuilder other) {
    previewLines.addAll(other.previewLines);
  }

  ThermalTicketPreview toPreview() {
    return ThermalTicketPreview(
      paperSize: paperSize,
      lines: List.unmodifiable(previewLines),
    );
  }

  void _recordPreview(
    String text, {
    bool bold = false,
    bool underline = false,
    bool reverse = false,
    bool center = false,
    PosTextSize width = PosTextSize.size1,
    PosTextSize height = PosTextSize.size1,
  }) {
    previewLines.add(
      ThermalPreviewLine(
        text: text,
        bold: bold,
        underline: underline,
        reverse: reverse,
        center: center,
        widthMultiplier: width.value,
        heightMultiplier: height.value,
      ),
    );
  }

  /// Minimum ticket length. ESC/POS default line spacing after reset is 1/6".
  static const double minLengthInches = 8;

  /// Default ESC/POS line spacing: ESC 2 = 1/6 inch.
  static const int linesPerInch = 6;

  static int get minLineUnits => (minLengthInches * linesPerInch).round();

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

  /// Empty table rows needed so [usedUnits] + [remainingUnits] + pad >= [minLineUnits].
  static int emptyRowsForMinLength({
    required int usedUnits,
    required int remainingUnits,
    int minLineUnits = -1,
  }) {
    final target = minLineUnits < 0
        ? EscPosTicketBuilder.minLineUnits
        : minLineUnits;
    final need = target - usedUnits - remainingUnits;
    return need > 0 ? need : 0;
  }

  void _countLine({PosTextSize height = PosTextSize.size1}) {
    _lineUnits += height.value;
  }

  List<int> reset() => generator.reset();

  List<int> feed([int n = 2]) {
    _lineUnits += n;
    return generator.feed(n);
  }

  List<int> cut() {
    // Prefer feed over hard cut — many mobile printers lack a cutter.
    return feed(3);
  }

  List<int> divider() => _ruleLine('-');

  List<int> doubleDivider() => _ruleLine('=');

  /// Horizontal rule for Nigachi / ESC/POS firmware that drops a full-width
  /// run of `-` or `=` when it is sent through [Generator.text].
  ///
  /// `text()` always prefixes `ESC $` (absolute position) using the library's
  /// mm80 profile (48 Font A columns / 576 dots). On a 4" 64-column printer
  /// that command plus a solid `-`/`=` line is discarded — individual hyphens
  /// in invoice numbers still print, which matches the field tickets.
  /// Sending the glyphs as a left-aligned raw line avoids that path.
  List<int> _ruleLine(String ch) {
    _countLine();
    final glyph = ch.isEmpty ? '-' : ch[0];
    final line = List.filled(columns, glyph).join();
    _recordPreview(line);
    return [
      ...generator.setStyles(const PosStyles(align: PosAlign.left)),
      ...line.codeUnits,
      0x0A,
    ];
  }

  List<int> center(
    String text, {
    bool bold = false,
    bool underline = false,
    bool reverse = false,
    PosTextSize width = PosTextSize.size1,
    PosTextSize height = PosTextSize.size1,
  }) {
    final clean = sanitize(text);
    _countLine(height: height);
    _recordPreview(
      clean,
      bold: bold,
      underline: underline,
      reverse: reverse,
      center: true,
      width: width,
      height: height,
    );
    return generator.text(
      clean,
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
    final clean = sanitize(text);
    _countLine(height: height);
    _recordPreview(
      clean,
      bold: bold,
      underline: underline,
      reverse: reverse,
      width: width,
      height: height,
    );
    return generator.text(
      clean,
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
        : truncate('$leftClean $rightClean', cols);
    _countLine(height: height);
    _recordPreview(
      line,
      bold: bold,
      underline: underline,
      reverse: reverse,
      width: width,
      height: height,
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
    // Double-width halves usable columns; wrap so 2" tickets still fit.
    final nameCols = (columns / 2).floor().clamp(8, columns);
    for (final line in wrapText(orgName.toUpperCase(), nameCols)) {
      bytes.addAll(
        center(line, width: PosTextSize.size2, height: PosTextSize.size2),
      );
    }

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
      center(voucherTitle.toUpperCase(), bold: true, underline: true),
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

    // Always print Phone / TRN labels so empty values still occupy a line.
    bytes.addAll(left('Phone: ${truncate(phone?.trim() ?? '', columns - 7)}'));

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

    bytes.addAll(left('TRN: ${truncate(trn?.trim() ?? '', columns - 5)}'));
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
        _pipeRow(sl: 'Sl', name: 'Item', qty: 'Qty', amount: 'Amount'),
        bold: true,
      ),
    );
    bytes.addAll(divider());
    return bytes;
  }

  /// One blank item-table row (`|   | … |       |          |`).
  List<int> emptyItemRow() {
    return left(_pipeRow(sl: '', name: '', qty: '', amount: ''));
  }

  List<int> blankLine() => left('');

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
    String taxLabel = 'VAT @ 5%',
  }) {
    final bytes = <int>[];
    bytes.addAll(divider());
    if (subTotal != null) {
      bytes.addAll(leftRight('Subtotal', money(subTotal, symbol)));
    }
    if (taxTotal != null && taxTotal != 0) {
      bytes.addAll(leftRight(taxLabel, money(taxTotal, symbol)));
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

    bytes.addAll(
      amountInWordsBlock(
        total: total,
        symbol: symbol,
        currencyCode: currencyCode,
      ),
    );
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

  static const String supervisorContact = 'Suneer (Supervisor) : +971501880810';

  List<int> footer({String? salespersonName, String? salespersonPhone}) {
    final bytes = <int>[];
    bytes.addAll(divider());
    final name = salespersonName?.trim() ?? '';
    final phone = salespersonPhone?.trim() ?? '';
    final salesmanRole = name.isEmpty
        ? '( Salesman ) :'
        : '$name ( Salesman ) :';
    final salesmanLine = phone.isEmpty ? salesmanRole : '$salesmanRole $phone';
    bytes.addAll(left(truncate(salesmanLine, columns)));
    bytes.addAll(left(truncate(supervisorContact, columns)));
    bytes.addAll(center('Thank you'));
    bytes.addAll(doubleDivider());
    bytes.addAll(cut());
    return bytes;
  }
}
