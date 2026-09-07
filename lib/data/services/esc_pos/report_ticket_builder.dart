import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/organization.dart';
import '../../../domain/models/thermal_paper_size.dart';
import '../../../domain/models/thermal_ticket_preview.dart';
import 'esc_pos_ticket_builder.dart';

/// Builds ESC/POS command bytes and previews for all tabular and summary reports
/// on 4-inch (~110-112mm / 64 cols) and 2-inch (~58mm / 32 cols) thermal rolls.
///
/// Tailored for van sales report slips:
/// - Company header without TRN (TRN is reserved for official tax vouchers).
/// - Dynamic multi-column pipe grid with SKU-code filtered out.
/// - 'Generated' timestamp positioned at the bottom in the footer section.
class ReportTicketBuilder {
  static final DateFormat generatedDateFormat =
      DateFormat('dd-MMM-yyyy hh:mm a');

  /// Builds ESC/POS binary command bytes for printing the report.
  static Future<List<int>> build({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required Organization org,
    required ThermalPaperSize paperSize,
    String? subtitle,
    String? dateRangeText,
    Map<String, String>? summaryStats,
    String? salespersonName,
    String? salespersonPhone,
    DateTime? generatedAt,
  }) async {
    final composed = await _compose(
      title: title,
      headers: headers,
      rows: rows,
      org: org,
      paperSize: paperSize,
      subtitle: subtitle,
      dateRangeText: dateRangeText,
      summaryStats: summaryStats,
      salespersonName: salespersonName,
      salespersonPhone: salespersonPhone,
      generatedAt: generatedAt,
    );
    return composed.bytes;
  }

  /// Builds an on-screen preview of the thermal ticket.
  static Future<ThermalTicketPreview> buildPreview({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required Organization org,
    required ThermalPaperSize paperSize,
    String? subtitle,
    String? dateRangeText,
    Map<String, String>? summaryStats,
    String? salespersonName,
    String? salespersonPhone,
    DateTime? generatedAt,
  }) async {
    final composed = await _compose(
      title: title,
      headers: headers,
      rows: rows,
      org: org,
      paperSize: paperSize,
      subtitle: subtitle,
      dateRangeText: dateRangeText,
      summaryStats: summaryStats,
      salespersonName: salespersonName,
      salespersonPhone: salespersonPhone,
      generatedAt: generatedAt,
    );
    return composed.preview;
  }

  static Future<({List<int> bytes, ThermalTicketPreview preview})> _compose({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required Organization org,
    required ThermalPaperSize paperSize,
    String? subtitle,
    String? dateRangeText,
    Map<String, String>? summaryStats,
    String? salespersonName,
    String? salespersonPhone,
    DateTime? generatedAt,
  }) async {
    final profile = await CapabilityProfile.load();
    final escPaper = EscPosTicketBuilder.toEscPosPaperSize(paperSize);
    final generator = Generator(escPaper, profile);
    final b = EscPosTicketBuilder(generator: generator, paperSize: paperSize);

    final bytes = <int>[];
    bytes.addAll(b.reset());

    // 1. Company Letterhead (NO TRN for reports)
    bytes.addAll(b.doubleDivider());
    final nameCols = (b.columns / 2).floor().clamp(8, b.columns);
    for (final line in EscPosTicketBuilder.wrapText(org.name.toUpperCase(), nameCols)) {
      bytes.addAll(
        b.center(line, width: PosTextSize.size2, height: PosTextSize.size2),
      );
    }

    final address = org.address.trim();
    if (address.isNotEmpty) {
      for (final line in EscPosTicketBuilder.wrapText(address, b.columns)) {
        bytes.addAll(b.center(line));
      }
    }
    final phone = org.phone.trim();
    if (phone.isNotEmpty) {
      bytes.addAll(b.center('Phone: ${b.truncate(phone, b.columns - 7)}'));
    }

    // 2. Report Title & Filter Period
    bytes.addAll(b.divider());
    bytes.addAll(
      b.center(title.toUpperCase(), bold: true, underline: true),
    );
    if (subtitle != null && subtitle.trim().isNotEmpty) {
      bytes.addAll(b.center(subtitle.trim()));
    }
    if (dateRangeText != null && dateRangeText.trim().isNotEmpty) {
      bytes.addAll(b.left('Period: ${dateRangeText.trim()}'));
    }

    // 3. Summary KPI Block (if available)
    if (summaryStats != null && summaryStats.isNotEmpty) {
      bytes.addAll(b.divider());
      bytes.addAll(b.left('SUMMARY:', bold: true));
      for (final entry in summaryStats.entries) {
        bytes.addAll(b.leftRight(entry.key, entry.value));
      }
    }

    // 4. Dynamic Column Grid (filter out SKU column)
    final skuIndices = <int>{};
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();
      if (h == 'sku' || h == 'sku code' || h == 'sku-code' || h == 'sku_code') {
        skuIndices.add(i);
      }
    }

    final filteredHeaders = <String>[];
    for (var i = 0; i < headers.length; i++) {
      if (!skuIndices.contains(i)) {
        filteredHeaders.add(headers[i]);
      }
    }

    final filteredRows = rows.map((r) {
      final clean = <String>[];
      for (var i = 0; i < r.length; i++) {
        if (!skuIndices.contains(i)) {
          clean.add(r[i]);
        }
      }
      return clean;
    }).toList();

    // Determine column widths
    final colWidths = _calculateColumnWidths(
      columns: b.columns,
      headers: filteredHeaders,
      rows: filteredRows,
    );

    // Render Table Header
    bytes.addAll(b.divider());
    bytes.addAll(
      b.left(
        _formatRow(
          values: ['#', ...filteredHeaders],
          widths: colWidths,
        ),
        bold: true,
      ),
    );
    bytes.addAll(b.divider());

    // Render Data Rows
    for (var r = 0; r < filteredRows.length; r++) {
      final rowData = filteredRows[r];
      final serial = '${r + 1}';
      final primaryText = rowData.isNotEmpty ? rowData.first : '';
      final otherValues = rowData.length > 1 ? rowData.sublist(1) : <String>[];

      final primaryWidth = colWidths.length > 1 ? colWidths[1] : 20;
      final wrappedPrimary = EscPosTicketBuilder.wrapText(
        primaryText,
        primaryWidth,
      );
      final primaryLines =
          wrappedPrimary.isEmpty ? <String>[''] : wrappedPrimary;

      for (var lineIdx = 0; lineIdx < primaryLines.length; lineIdx++) {
        final isFirstLine = lineIdx == 0;
        final currentValues = <String>[
          isFirstLine ? serial : '',
          primaryLines[lineIdx],
          ...otherValues.map((v) => isFirstLine ? v : ''),
        ];

        bytes.addAll(
          b.left(
            _formatRow(values: currentValues, widths: colWidths),
          ),
        );
      }
    }

    // 5. Tail Padding & Footer (Generated timestamp at bottom)
    final timestamp = generatedDateFormat.format(generatedAt ?? DateTime.now());

    bytes.addAll(
      _padToMinLength(
        b,
        buildTail: (tail) {
          final after = <int>[];
          after.addAll(tail.divider());
          after.addAll(tail.left('Generated: $timestamp'));
          after.addAll(
            tail.footer(
              salespersonName: salespersonName,
              salespersonPhone: salespersonPhone,
            ),
          );
          return after;
        },
      ),
    );

    return (bytes: bytes, preview: b.toPreview());
  }

  /// Calculates column character widths dynamically fitting available columns.
  static List<int> _calculateColumnWidths({
    required int columns,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    // Total table columns = Serial + data columns
    final totalCols = headers.length + 1;
    if (totalCols <= 1) return [columns - 2];

    const slWidth = 3;
    final pipeCount = totalCols + 1;

    // Allocate widths for trailing columns (numeric / short values)
    final otherWidths = <int>[];
    for (var i = 1; i < headers.length; i++) {
      var maxDataLen = headers[i].length;
      for (final r in rows) {
        if (i < r.length && r[i].length > maxDataLen) {
          maxDataLen = r[i].length;
        }
      }
      // Target 6..12 chars per numeric column
      final target = maxDataLen.clamp(6, 12).toInt();
      otherWidths.add(target);
    }

    final usedByOthers =
        slWidth + otherWidths.fold<int>(0, (sum, w) => sum + w) + pipeCount;
    var primaryWidth = columns - usedByOthers;

    // Ensure primary column has at least 10 chars
    if (primaryWidth < 10) {
      primaryWidth = 10;
      // Shrink trailing columns proportionally if needed
      for (var i = 0; i < otherWidths.length; i++) {
        if (otherWidths[i] > 6) {
          otherWidths[i] = 6;
        }
      }
    }

    return [slWidth, primaryWidth, ...otherWidths];
  }

  static String _formatRow({
    required List<String> values,
    required List<int> widths,
  }) {
    final buffer = StringBuffer('|');
    for (var i = 0; i < widths.length; i++) {
      final w = widths[i];
      final val = i < values.length ? values[i] : '';
      final isNumeric = i != 1; // Primary description is column 1 (left-aligned)
      final truncated = EscPosTicketBuilder.sanitize(val);
      final cell = truncated.length > w ? truncated.substring(0, w) : truncated;
      if (isNumeric) {
        buffer.write(cell.padLeft(w));
      } else {
        buffer.write(cell.padRight(w));
      }
      buffer.write('|');
    }
    return buffer.toString();
  }

  static List<int> _padToMinLength(
    EscPosTicketBuilder b, {
    required List<int> Function(EscPosTicketBuilder tail) buildTail,
  }) {
    final tailProbe = EscPosTicketBuilder(
      generator: b.generator,
      paperSize: b.paperSize,
    );
    buildTail(tailProbe);
    final neededBlanks =
        EscPosTicketBuilder.minLineUnits - b.lineUnits - tailProbe.lineUnits;

    final bytes = <int>[];
    for (var i = 0; i < neededBlanks; i++) {
      bytes.addAll(b.blankLine());
    }

    final tail = EscPosTicketBuilder(
      generator: b.generator,
      paperSize: b.paperSize,
    );
    final tailBytes = buildTail(tail);
    b.absorbPreviewFrom(tail);
    bytes.addAll(tailBytes);
    return bytes;
  }
}
