import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/organization.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/print_settings.dart';
import '../../../../domain/models/salesperson.dart';
import 'shared_pdf_template.dart';

/// PDF template for generating professional Payment Receipt documents.
class ReceiptPdfTemplate {
  static pw.Document generate(
    ReceiptVoucher receipt,
    Organization org,
    Customer? customer, {
    Salesperson? salesperson,
    String? supervisorPhone = PrintSettings.fallbackSupervisorPhone,
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
              voucherTitle: 'Payment Receipt',
              voucherNumber: receipt.paymentNumber,
              date: receipt.date,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 16),

            // Billing Parties Grid (From and To)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: 'Received By (Merchant)',
              companyName: org.name,
              companyPhone: org.phone,
              companyAddress: org.address,
              companyTrn: org.trn,
              companyDetails: 'On-Route Delivery Van',
              billToLabel: 'Payer (Customer)',
              clientName: receipt.customerName,
              clientTrn: customer?.trn,
              clientEmail: customer?.email,
              clientPhone: customer?.phone,
              clientAddress: customer?.address ?? 'No physical address listed',
            ),
            pw.SizedBox(height: 20),

            // Payment Metadata Panel
            SharedPdfTemplate.buildInfoPanel([
              PdfInfoEntry('Payment Mode', receipt.paymentMode.toUpperCase()),
              PdfInfoEntry(
                'Reference / Tran ID',
                receipt.referenceNumber.isNotEmpty
                    ? receipt.referenceNumber
                    : 'N/A',
                alignment: pw.CrossAxisAlignment.center,
              ),
              PdfInfoEntry(
                'Total Received',
                '$currencySymbol${receipt.amount.toStringAsFixed(2)}',
                alignment: pw.CrossAxisAlignment.end,
                valueColor: SharedPdfTemplate.primaryRed,
              ),
            ]),
            pw.SizedBox(height: 20),

            // Allocations Section
            SharedPdfTemplate.buildSectionTitle('Payment Allocations'),

            if (receipt.allocations.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                width: double.infinity,
                decoration: pw.BoxDecoration(
                  color: SharedPdfTemplate.lightGreyBackground,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                ),
                child: pw.Text(
                  'No outstanding invoices were allocated. This amount is fully available as a general customer deposit credit.',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: SharedPdfTemplate.slateTextSecondary,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              )
            else ...[
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
                  1: pw.FlexColumnWidth(3.0), // Invoice No
                  2: pw.FlexColumnWidth(1.5), // Amount Settled
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
                        'Target Invoice Reference',
                        alignLeft: true,
                      ),
                      SharedPdfTemplate.buildTableHeader('Amount Applied'),
                    ],
                  ),
                  // Allocation Rows
                  for (int i = 0; i < receipt.allocations.length; i++) ...[
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: i % 2 == 0
                            ? PdfColors.white
                            : SharedPdfTemplate.lightGreyBackground,
                      ),
                      children: [
                        SharedPdfTemplate.buildTableCell('${i + 1}'),
                        SharedPdfTemplate.buildTableCell(
                          receipt.allocations[i].invoiceNumber,
                          alignLeft: true,
                        ),
                        SharedPdfTemplate.buildTableCell(
                          '$currencySymbol${receipt.allocations[i].amountApplied.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
            pw.SizedBox(height: 20),

            // Summary Totals
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                SharedPdfTemplate.buildTotalsCard(
                  width: 250,
                  rows: [
                    SharedPdfTemplate.buildSummaryRow(
                      'Total Allocated',
                      '$currencySymbol${receipt.totalAllocated.toStringAsFixed(2)}',
                    ),
                    pw.SizedBox(height: 4),
                    SharedPdfTemplate.buildSummaryRow(
                      'Unallocated General Credit',
                      '$currencySymbol${receipt.unallocatedAmount.toStringAsFixed(2)}',
                    ),
                  ],
                  grandTotalLabel: 'Grand Total Received',
                  grandTotalValue:
                      '$currencySymbol${receipt.amount.toStringAsFixed(2)}',
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
