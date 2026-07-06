import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/models/organization.dart';
import '../../../../domain/models/customer.dart';
import 'shared_pdf_template.dart';

/// PDF template for generating professional Sales Return (Credit Note) documents.
class SalesReturnPdfTemplate {
  static pw.Document generate(
    SalesReturn returnVoucher,
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
              voucherTitle: 'Credit Note',
              voucherNumber: returnVoucher.creditNoteNumber,
              date: returnVoucher.date,
            ),
            pw.SizedBox(height: 16),

            // Billing Parties Grid (From and To)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: 'Receiver / Merchant',
              companyName: companyName,
              companyDetails: 'On-Route Delivery Van\nTax Registered Vendor',
              billToLabel: 'Returned By (Customer)',
              clientName: returnVoucher.customerName,
              clientEmail: customer?.email,
              clientPhone: customer?.phone,
              clientAddress: customer?.address ?? 'No physical address listed',
            ),
            pw.SizedBox(height: 20),

            // Reason for Return Box
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: SharedPdfTemplate.primaryLightIndigo,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(
                  color: SharedPdfTemplate.borderSlate,
                  width: 1,
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Icon(
                    const pw.IconData(0xe887), // Help/Info icon equivalent
                    color: SharedPdfTemplate.primaryIndigo,
                    size: 14,
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'REASON FOR RETURN / CREDIT ISSUED',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: SharedPdfTemplate.primaryIndigo,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          returnVoucher.reason.isNotEmpty
                              ? returnVoucher.reason
                              : 'General Customer Return.',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: SharedPdfTemplate.slateText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Items Section Title
            SharedPdfTemplate.buildSectionTitle('Returned Items list'),

            // Dynamic Return Items Table
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
                0: pw.FlexColumnWidth(0.6), // S.No
                1: pw.FlexColumnWidth(2.2), // Item Name/SKU
                2: pw.FlexColumnWidth(0.8), // Qty Returned
                3: pw.FlexColumnWidth(1.2), // Original Rate
                4: pw.FlexColumnWidth(1.2), // Refund Total
              },
              children: [
                // Header Row
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: SharedPdfTemplate.primaryIndigo,
                  ),
                  children: [
                    _buildTableHeader('#', alignLeft: true),
                    _buildTableHeader('Item & SKU', alignLeft: true),
                    _buildTableHeader('Returned Qty'),
                    _buildTableHeader('Unit Rate'),
                    _buildTableHeader('Refund Amount'),
                  ],
                ),
                // Item Rows
                for (int i = 0; i < returnVoucher.items.length; i++) ...[
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i % 2 == 0
                          ? PdfColors.white
                          : SharedPdfTemplate.lightGreyBackground,
                    ),
                    children: [
                      _buildTableCell('${i + 1}'),
                      _buildTableCell(
                        '${returnVoucher.items[i].invoiceLineItem.item.name}\nSKU: ${returnVoucher.items[i].invoiceLineItem.item.sku}',
                        alignLeft: true,
                        isSubText: true,
                      ),
                      _buildTableCell(
                        '${returnVoucher.items[i].returnedQuantity}',
                      ),
                      _buildTableCell(
                        '$currencySymbol${returnVoucher.items[i].invoiceLineItem.rate.toStringAsFixed(2)}',
                      ),
                      _buildTableCell(
                        '$currencySymbol${returnVoucher.items[i].total.toStringAsFixed(2)}',
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
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                // Right Column: Credit Summary Card
                pw.Container(
                  width: 220,
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
                        'Total Credit Issued',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateText,
                        ),
                      ),
                      pw.Text(
                        '$currencySymbol${returnVoucher.total.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 13,
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
        style: const pw.TextStyle(
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
