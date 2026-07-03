import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/organization.dart';
import '../../../../domain/models/customer.dart';
import 'shared_pdf_template.dart';

/// PDF template for generating professional Payment Receipt documents.
class ReceiptPdfTemplate {
  static pw.Document generate(
    ReceiptVoucher receipt,
    Organization? org,
    Customer? customer,
  ) {
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
              voucherTitle: 'Payment Receipt',
              voucherNumber: receipt.paymentNumber,
              date: receipt.date,
            ),
            pw.SizedBox(height: 16),

            // Billing Parties Grid (From and To)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: 'Received By (Merchant)',
              companyName: companyName,
              companyDetails: 'On-Route Delivery Van\nTax Registered Vendor',
              billToLabel: 'Payer (Customer)',
              clientName: receipt.customerName,
              clientEmail: customer?.email,
              clientPhone: customer?.phone,
              clientAddress: customer?.address ?? 'No physical address listed',
            ),
            pw.SizedBox(height: 20),

            // Payment Metadata Panel
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
                        'PAYMENT MODE',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        receipt.paymentMode.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateText,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'REFERENCE / TRAN ID',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        receipt.referenceNumber.isNotEmpty
                            ? receipt.referenceNumber
                            : 'N/A',
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
                        'TOTAL RECEIVED',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '$currencySymbol${receipt.amount.toStringAsFixed(2)}',
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
                    color: SharedPdfTemplate.primaryIndigo,
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
                      color: SharedPdfTemplate.primaryIndigo,
                    ),
                    children: [
                      _buildTableHeader('#', alignLeft: true),
                      _buildTableHeader(
                        'Target Invoice Reference',
                        alignLeft: true,
                      ),
                      _buildTableHeader('Amount Applied'),
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
                        _buildTableCell('${i + 1}'),
                        _buildTableCell(
                          receipt.allocations[i].invoiceNumber,
                          alignLeft: true,
                        ),
                        _buildTableCell(
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
                pw.Container(
                  width: 250,
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
                  child: pw.Column(
                    children: [
                      _buildSummaryRow(
                        'Total Allocated',
                        '$currencySymbol${receipt.totalAllocated.toStringAsFixed(2)}',
                      ),
                      pw.SizedBox(height: 4),
                      _buildSummaryRow(
                        'Unallocated General Credit',
                        '$currencySymbol${receipt.unallocatedAmount.toStringAsFixed(2)}',
                      ),
                      pw.SizedBox(height: 6),
                      pw.Divider(
                        color: SharedPdfTemplate.borderSlate,
                        thickness: 1,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Grand Total Received',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: SharedPdfTemplate.slateText,
                            ),
                          ),
                          pw.Text(
                            '$currencySymbol${receipt.amount.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: SharedPdfTemplate.primaryIndigo,
                            ),
                          ),
                        ],
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
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: SharedPdfTemplate.slateText,
          fontSize: 9,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.right,
      ),
    );
  }

  static pw.Widget _buildSummaryRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 9,
            color: SharedPdfTemplate.slateTextSecondary,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: SharedPdfTemplate.slateText,
          ),
        ),
      ],
    );
  }
}
