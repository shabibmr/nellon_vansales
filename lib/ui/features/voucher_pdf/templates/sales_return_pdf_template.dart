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
    Organization org,
    Customer? customer, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
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
              voucherTitle: 'Credit Note',
              voucherNumber: returnVoucher.creditNoteNumber,
              date: returnVoucher.date,
            ),
            pw.SizedBox(height: 16),

            // Billing Parties Grid (From and To)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: 'Receiver / Merchant',
              companyName: org.name,
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
                    SharedPdfTemplate.buildTableHeader('#', alignLeft: true),
                    SharedPdfTemplate.buildTableHeader(
                      'Item & SKU',
                      alignLeft: true,
                    ),
                    SharedPdfTemplate.buildTableHeader('Returned Qty'),
                    SharedPdfTemplate.buildTableHeader('Unit Rate'),
                    SharedPdfTemplate.buildTableHeader('Refund Amount'),
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
                      SharedPdfTemplate.buildTableCell('${i + 1}'),
                      SharedPdfTemplate.buildTableCell(
                        '${returnVoucher.items[i].invoiceLineItem.item.name}\nSKU: ${returnVoucher.items[i].invoiceLineItem.item.sku}',
                        alignLeft: true,
                        isSubText: true,
                      ),
                      SharedPdfTemplate.buildTableCell(
                        '${returnVoucher.items[i].returnedQuantity}',
                      ),
                      SharedPdfTemplate.buildTableCell(
                        '$currencySymbol${returnVoucher.items[i].invoiceLineItem.rate.toStringAsFixed(2)}',
                      ),
                      SharedPdfTemplate.buildTableCell(
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
                SharedPdfTemplate.buildTotalsCard(
                  rows: const [],
                  grandTotalLabel: 'Total Credit Issued',
                  grandTotalValue:
                      '$currencySymbol${returnVoucher.total.toStringAsFixed(2)}',
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
}
