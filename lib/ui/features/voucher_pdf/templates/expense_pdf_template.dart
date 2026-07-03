import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/models/organization.dart';
import 'shared_pdf_template.dart';

/// PDF template for generating professional Expense Voucher documents.
class ExpensePdfTemplate {
  static pw.Document generate(ExpenseEntry expense, Organization? org) {
    final pdf = pw.Document();
    final companyName = org?.name ?? 'Van Sales Pro';
    final currencySymbol = org?.currencySymbol ?? '₹';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            // Letterhead Header
            SharedPdfTemplate.buildHeader(
              org: org,
              voucherTitle: 'Expense Voucher',
              voucherNumber: expense.id,
              date: expense.date,
            ),
            pw.SizedBox(height: 16),

            // Billing Parties Grid (From and To)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: 'Charged By (Company)',
              companyName: companyName,
              companyDetails: 'On-Route Operating Expense\nTax-Deductible Log',
              billToLabel: 'Disbursed To / Vendor',
              clientName: 'Operational Expense / Driver',
              clientEmail: '',
              clientPhone: '',
              clientAddress: 'Logged during route delivery services',
            ),
            pw.SizedBox(height: 20),

            // Expense Metadata
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: SharedPdfTemplate.lightGreyBackground,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(
                  color: SharedPdfTemplate.borderSlate,
                  width: 1,
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'VOUCHER TYPE',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Route Fleet Expense',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateText,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'TOTAL DISBURSED',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '$currencySymbol${expense.amount.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.primaryIndigo,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Expense Lines Section Title
            SharedPdfTemplate.buildSectionTitle('Expense Line Items'),

            // Dynamic Expense Items Table
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: SharedPdfTemplate.borderSlate,
                  width: 0.5,
                ),
                bottom: pw.BorderSide(
                  color: SharedPdfTemplate.primaryIndigo,
                  width: 1,
                ),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.8), // S.No
                1: pw.FlexColumnWidth(2.5), // Category
                2: pw.FlexColumnWidth(3.0), // Description
                3: pw.FlexColumnWidth(1.5), // Amount
              },
              children: [
                // Header Row
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: SharedPdfTemplate.primaryIndigo,
                  ),
                  children: [
                    _buildTableHeader('#', alignLeft: true),
                    _buildTableHeader('Category', alignLeft: true),
                    _buildTableHeader(
                      'Description / Justification',
                      alignLeft: true,
                    ),
                    _buildTableHeader('Amount'),
                  ],
                ),
                // Item Rows
                for (int i = 0; i < expense.lines.length; i++) ...[
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i % 2 == 0
                          ? PdfColors.white
                          : SharedPdfTemplate.lightGreyBackground,
                    ),
                    children: [
                      _buildTableCell('${i + 1}'),
                      _buildTableCell(
                        expense.lines[i].category,
                        alignLeft: true,
                      ),
                      _buildTableCell(
                        expense.lines[i].description,
                        alignLeft: true,
                        isSubText: true,
                      ),
                      _buildTableCell(
                        '$currencySymbol${expense.lines[i].amount.toStringAsFixed(2)}',
                        isBold: true,
                      ),
                    ],
                  ),
                ],
              ],
            ),
            pw.SizedBox(height: 20),

            // Summary Totals
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'METADATA & APPROVAL',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        expense.receiptImagePath != null
                            ? 'Receipt Photo attached locally at device: ${expense.receiptImagePath}'
                            : 'No physical photo attachment registered.',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          color: SharedPdfTemplate.slateText,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 32),
                pw.Container(
                  width: 200,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: SharedPdfTemplate.lightGreyBackground,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(12),
                    ),
                    border: pw.Border.all(
                      color: SharedPdfTemplate.borderSlate,
                      width: 1,
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Total Claim',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateText,
                        ),
                      ),
                      pw.Text(
                        '$currencySymbol${expense.amount.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.primaryIndigo,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ];
        },
        footer: SharedPdfTemplate.buildFooter,
      ),
    );

    return pdf;
  }

  static pw.Widget _buildTableHeader(String text, {bool alignLeft = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.right,
      ),
    );
  }

  static pw.Widget _buildTableCell(
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
          color: SharedPdfTemplate.slateText,
          fontSize: isSubText ? 8.5 : 9,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.right,
      ),
    );
  }
}
