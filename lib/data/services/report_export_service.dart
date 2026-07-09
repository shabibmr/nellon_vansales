import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Shares/prints tabular report data (headers + rows of plain strings) as
/// CSV (opens directly in Excel/Sheets), PDF, or through the system print
/// dialog. Every report page owns its own aggregation; this service only
/// turns the resulting rows into a file so all reports export identically.
class ReportExportService {
  ReportExportService._();

  static String _fileSafe(String title) =>
      title.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

  static String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static Future<void> exportCsv(
    String title,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_csvField).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_csvField).join(','));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileSafe(title)}.csv');
    await file.writeAsString(buffer.toString(), flush: true);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: title),
    );
  }

  static Future<Uint8List> _buildPdfBytes(
    String title,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Header(level: 0, text: title),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> exportPdf(
    String title,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final bytes = await _buildPdfBytes(title, headers, rows);
    await Printing.sharePdf(bytes: bytes, filename: '${_fileSafe(title)}.pdf');
  }

  static Future<void> printReport(
    String title,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    await Printing.layoutPdf(
      onLayout: (_) => _buildPdfBytes(title, headers, rows),
      name: title,
    );
  }
}
