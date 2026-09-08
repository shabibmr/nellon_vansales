import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/models/organization.dart';
import '../../../../domain/models/print_settings.dart';
import '../../../../domain/models/salesperson.dart';
import 'shared_pdf_template.dart';

/// PDF template for generating professional Expense Voucher documents.
class ExpensePdfTemplate {
  static pw.Document generate(
    ExpenseEntry expense,
    Organization org, {
    Salesperson? salesperson,
    String? supervisorPhone = PrintSettings.fallbackSupervisorPhone,
    String? companyPhone,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    pw.ImageProvider? logoImage,
  }) {
    final pdf = pw.Document();
    final currencySymbol = org.currencySymbol;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            // Letterhead Header
            SharedPdfTemplate.buildHeader(
              org: org,
              voucherTitle: 'Expense Voucher',
              voucherNumber: expense.id,
              date: expense.date,
              logoImage: logoImage,
              companyPhone: companyPhone,
            ),
            pw.SizedBox(height: 16),

            // Billing Parties Grid (From and To)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: 'Charged By (Company)',
              companyName: org.name,
              companyPhone: companyPhone ?? org.phone,
              companyAddress: org.address,
              companyTrn: org.trn,
              companyDetails: 'On-Route Operating Expense',
              billToLabel: 'Disbursed To / Payee',
              clientName: (salesperson != null && salesperson.name.trim().isNotEmpty)
                  ? '${salesperson.name} (Driver/Salesperson)'
                  : 'Operational Expense / Driver',
              clientEmail: salesperson?.email,
              clientPhone: salesperson?.phone,
              clientAddress: 'Logged during route delivery services',
            ),
            pw.SizedBox(height: 20),

            // Expense Metadata
            SharedPdfTemplate.buildInfoPanel([
              const PdfInfoEntry('Voucher Type', 'Route Fleet Expense'),
              PdfInfoEntry(
                'Total Disbursed',
                '$currencySymbol${expense.amount.toStringAsFixed(2)}',
                alignment: pw.CrossAxisAlignment.end,
                valueColor: SharedPdfTemplate.primaryRed,
              ),
            ]),
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
                  color: SharedPdfTemplate.primaryRed,
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
                    color: SharedPdfTemplate.primaryRed,
                  ),
                  children: [
                    SharedPdfTemplate.buildTableHeader('#', alignLeft: true),
                    SharedPdfTemplate.buildTableHeader(
                      'Category',
                      alignLeft: true,
                    ),
                    SharedPdfTemplate.buildTableHeader(
                      'Description / Justification',
                      alignLeft: true,
                    ),
                    SharedPdfTemplate.buildTableHeader('Amount'),
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
                      SharedPdfTemplate.buildTableCell('${i + 1}'),
                      SharedPdfTemplate.buildTableCell(
                        expense.lines[i].category,
                        alignLeft: true,
                      ),
                      SharedPdfTemplate.buildTableCell(
                        expense.lines[i].description,
                        alignLeft: true,
                        isSubText: true,
                      ),
                      SharedPdfTemplate.buildTableCell(
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
                SharedPdfTemplate.buildTotalsCard(
                  width: 200,
                  rows: const [],
                  grandTotalLabel: 'Total Claim',
                  grandTotalValue:
                      '$currencySymbol${expense.amount.toStringAsFixed(2)}',
                  grandTotalLabelFontSize: 10,
                  grandTotalValueFontSize: 12,
                ),
              ],
            ),
          ];
        },
        footer: (context) => SharedPdfTemplate.buildFooter(
          context,
          salesperson: salesperson,
          supervisorPhone: supervisorPhone,
        ),
      ),
    );

    return pdf;
  }
}
