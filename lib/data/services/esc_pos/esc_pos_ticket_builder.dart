import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/thermal_paper_size.dart';

/// Shared ESC/POS layout helpers for 2" / 4" thermal tickets.
class EscPosTicketBuilder {
  EscPosTicketBuilder({
    required this.generator,
    required this.paperSize,
  }) : columns = paperSize.columns;

  final Generator generator;
  final ThermalPaperSize paperSize;
  final int columns;

  static final DateFormat dateTimeFormat = DateFormat('dd MMM yyyy HH:mm');
  static final DateFormat dateOnlyFormat = DateFormat('dd MMM yyyy');

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

  String money(num amount, String symbol) {
    final cleanSymbol = sanitize(symbol);
    return '$cleanSymbol${amount.toStringAsFixed(2)}';
  }

  String truncate(String text, int max) {
    final clean = sanitize(text);
    if (clean.length <= max) return clean;
    if (max <= 1) return clean.substring(0, max);
    return '${clean.substring(0, max - 1)}.';
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
    PosTextSize width = PosTextSize.size1,
    PosTextSize height = PosTextSize.size1,
  }) {
    return generator.text(
      sanitize(text),
      styles: PosStyles(
        align: PosAlign.center,
        bold: bold,
        width: width,
        height: height,
      ),
    );
  }

  List<int> left(String text, {bool bold = false}) {
    return generator.text(
      sanitize(text),
      styles: PosStyles(align: PosAlign.left, bold: bold),
    );
  }

  List<int> leftRight(String leftText, String rightText, {bool bold = false}) {
    final leftClean = sanitize(leftText);
    final rightClean = sanitize(rightText);
    final gap = columns - leftClean.length - rightClean.length;
    final line = gap >= 1
        ? '$leftClean${' ' * gap}$rightClean'
        : truncate(
            '$leftClean $rightClean',
            columns,
          );
    return generator.text(
      line,
      styles: PosStyles(align: PosAlign.left, bold: bold),
    );
  }

  List<int> header({
    required String orgName,
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
    bytes.addAll(center('Van Sales Receipt'));
    bytes.addAll(divider());
    bytes.addAll(leftRight('Type:', voucherTitle, bold: true));
    bytes.addAll(leftRight('No:', voucherNumber));
    bytes.addAll(leftRight('Date:', dateTimeFormat.format(date)));
    return bytes;
  }

  List<int> customerBlock({
    required String name,
    String? phone,
    String? address,
  }) {
    final bytes = <int>[];
    bytes.addAll(divider());
    bytes.addAll(left('Customer: ${truncate(name, columns - 10)}'));
    if (phone != null && phone.trim().isNotEmpty) {
      bytes.addAll(left('Phone: ${truncate(phone, columns - 7)}'));
    }
    if (address != null && address.trim().isNotEmpty) {
      bytes.addAll(left(truncate(address, columns)));
    }
    return bytes;
  }

  List<int> itemTableHeader() {
    final bytes = <int>[];
    bytes.addAll(divider());
    // qty(8) holds "2kg" / "2 Bag"; amount(10) on the right for both widths
    const amountW = 10;
    const qtyW = 8;
    final nameW = columns - amountW - qtyW - 2;
    final header =
        '${'Item'.padRight(nameW)} ${'Qty'.padLeft(qtyW)} ${'Amount'.padLeft(amountW)}';
    bytes.addAll(left(header, bold: true));
    bytes.addAll(divider());
    return bytes;
  }

  List<int> itemRow({
    required String name,
    required num qty,
    required String amountText,
    String uom = '',
  }) {
    const amountW = 10;
    const qtyW = 8;
    final nameW = columns - amountW - qtyW - 2;
    final bytes = <int>[];
    final primary = truncate(name, nameW);
    final qtyNum = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    final unit = uom.trim();
    // Prefer "2kg" compact form; fall back to bare qty when no unit.
    final qtyText = unit.isEmpty
        ? qtyNum
        : truncate('$qtyNum$unit', qtyW);
    final row =
        '${primary.padRight(nameW)} ${qtyText.padLeft(qtyW)} ${amountText.padLeft(amountW)}';
    bytes.addAll(left(row));
    return bytes;
  }

  List<int> totalsBlock({
    required String symbol,
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
    bytes.addAll(leftRight('TOTAL', money(total, symbol), bold: true));
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
