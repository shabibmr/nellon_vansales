import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../../../domain/models/organization.dart';

/// A single label/value entry rendered inside [SharedPdfTemplate.buildInfoPanel].
class PdfInfoEntry {
  final String label;
  final String value;
  final pw.CrossAxisAlignment alignment;
  final PdfColor? valueColor;

  const PdfInfoEntry(
    this.label,
    this.value, {
    this.alignment = pw.CrossAxisAlignment.start,
    this.valueColor,
  });
}

/// Centralized Design System and layout utilities for PDF generation.
///
/// Implements HSL-tailored professional color schemes, standard margins, and modular
/// reusable blocks (Headers, Footers, Info Cards) matching the application's look and feel.
class SharedPdfTemplate {
  // Premium Theme Color Palette
  static final PdfColor primaryIndigo = const PdfColor.fromInt(0xFF4F46E5);
  static final PdfColor primaryLightIndigo = const PdfColor.fromInt(0xFFEEF2FF);
  static final PdfColor slateText = const PdfColor.fromInt(0xFF0F172A);
  static final PdfColor slateTextSecondary = const PdfColor.fromInt(0xFF64748B);
  static final PdfColor borderSlate = const PdfColor.fromInt(0xFFE2E8F0);
  static final PdfColor alertAmber = const PdfColor.fromInt(0xFFF59E0B);
  static final PdfColor successEmerald = const PdfColor.fromInt(0xFF10B981);
  static final PdfColor lightGreyBackground = const PdfColor.fromInt(0xFFF8FAFC);

  // Formatting helpers
  static final DateFormat dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat dateOnlyFormat = DateFormat('dd MMM yyyy');

  /// Common corporate grid header with billing enforcer typography and vibrant accents.
  static pw.Widget buildHeader({
    required Organization org,
    required String voucherTitle,
    required String voucherNumber,
    required DateTime date,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 24),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Letterhead Logo & Title Row
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    org.name.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryIndigo,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'On-The-Road Smart Invoicing Module',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.normal,
                      color: slateTextSecondary,
                    ),
                  ),
                  pw.Text(
                    'Zone: ${org.timeZone}',
                    style: pw.TextStyle(fontSize: 9, color: slateTextSecondary),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: primaryLightIndigo,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                    ),
                    child: pw.Text(
                      voucherTitle.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryIndigo,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Text(
                        'Voucher #: ',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: slateTextSecondary,
                        ),
                      ),
                      pw.Text(
                        voucherNumber,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: slateText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          // Accent colored thick divider line
          pw.Container(
            height: 4,
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [primaryIndigo, successEmerald],
                begin: pw.Alignment.centerLeft,
                end: pw.Alignment.centerRight,
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          ),
          pw.SizedBox(height: 12),
          // Sub-metadata block
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Issued: ${dateFormat.format(date)}',
                style: pw.TextStyle(fontSize: 10, color: slateText),
              ),
              pw.Text(
                'Status: CONFIRMED',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: successEmerald,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compact Section Title helper
  static pw.Widget buildSectionTitle(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: primaryIndigo,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Container(height: 1, color: borderSlate),
        ],
      ),
    );
  }

  /// Grid detail panel for general company & customer layout columns.
  static pw.Widget buildClientGrid({
    required String billToLabel,
    required String clientName,
    required String? clientEmail,
    required String? clientPhone,
    required String? clientAddress,
    required String billFromLabel,
    required String companyName,
    String? companyDetails,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Billed From (Company)
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                billFromLabel.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: slateTextSecondary,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: slateText,
                ),
              ),
              if (companyDetails != null) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  companyDetails,
                  style: pw.TextStyle(fontSize: 9, color: slateTextSecondary),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        // Billed To (Client / Supplier)
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                billToLabel.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: slateTextSecondary,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                clientName,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: slateText,
                ),
              ),
              if (clientPhone != null && clientPhone.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'Phone: $clientPhone',
                  style: pw.TextStyle(fontSize: 9, color: slateText),
                ),
              ],
              if (clientEmail != null && clientEmail.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'Email: $clientEmail',
                  style: pw.TextStyle(fontSize: 9, color: slateText),
                ),
              ],
              if (clientAddress != null && clientAddress.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'Address: $clientAddress',
                  style: pw.TextStyle(fontSize: 9, color: slateTextSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Bordered metadata strip showing 2-3 label/value columns
  /// (e.g. due date + payment method, or voucher type + total).
  static pw.Widget buildInfoPanel(
    List<PdfInfoEntry> entries, {
    PdfColor? background,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: background ?? lightGreyBackground,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: borderSlate, width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: entries
            .map(
              (e) => pw.Column(
                crossAxisAlignment: e.alignment,
                children: [
                  pw.Text(
                    e.label.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: slateTextSecondary,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    e.value,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: e.valueColor ?? slateText,
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  /// Table header cell used for the first row of every line-item table.
  static pw.Widget buildTableHeader(String text, {bool alignLeft = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        text,
        style: const pw.TextStyle(
          color: PdfColors.white,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.right,
      ),
    );
  }

  /// Standard body cell used for every line-item table row.
  static pw.Widget buildTableCell(
    String text, {
    bool alignLeft = false,
    bool isBold = false,
    bool isSubText = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: isSubText ? slateTextSecondary : slateText,
          fontSize: isSubText ? 8.5 : 9,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.right,
      ),
    );
  }

  /// Label/value row used inside [buildTotalsCard].
  static pw.Widget buildSummaryRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 9, color: slateTextSecondary),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: slateText,
          ),
        ),
      ],
    );
  }

  /// Bordered totals card: zero or more [buildSummaryRow] rows, an optional
  /// divider (shown only when [rows] is non-empty), then a bold grand total row.
  static pw.Widget buildTotalsCard({
    required List<pw.Widget> rows,
    required String grandTotalLabel,
    required String grandTotalValue,
    double width = 220,
    double grandTotalLabelFontSize = 11,
    double grandTotalValueFontSize = 13,
  }) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: lightGreyBackground,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: borderSlate, width: 1),
      ),
      child: pw.Column(
        children: [
          ...rows,
          if (rows.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Divider(color: borderSlate, thickness: 1),
            pw.SizedBox(height: 6),
          ],
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                grandTotalLabel,
                style: pw.TextStyle(
                  fontSize: grandTotalLabelFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: slateText,
                ),
              ),
              pw.Text(
                grandTotalValue,
                style: pw.TextStyle(
                  fontSize: grandTotalValueFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryIndigo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Multi-page footer showing legal taglines and standard page numbering bounds.
  static pw.Widget buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 24),
      child: pw.Column(
        children: [
          pw.Divider(color: borderSlate, thickness: 1),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'This is a computer-generated official billing document.',
                style: pw.TextStyle(fontSize: 8, color: slateTextSecondary),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: slateText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
