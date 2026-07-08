import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/models/organization.dart';
import '../../../../domain/models/customer.dart';
import 'shared_pdf_template.dart';

/// PDF template for generating professional Sales Order documents.
class SalesOrderPdfTemplate {
  static pw.Document generate(
    SalesOrder order,
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
              voucherTitle: 'Sales Order',
              voucherNumber: order.orderNumber,
              date: order.date,
            ),
            pw.SizedBox(height: 16),

            // Billing Parties Grid (From and To)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: 'Supplier / Dispatcher',
              companyName: org.name,
              companyDetails: 'On-Route Delivery Van\nTax Registered Vendor',
              billToLabel: 'Ordered By (Customer)',
              clientName: order.customerName,
              clientEmail: customer?.email,
              clientPhone: customer?.phone,
              clientAddress: customer?.address ?? 'No physical address listed',
            ),
            pw.SizedBox(height: 20),

            // Shipment Date & Order Status Block
            SharedPdfTemplate.buildInfoPanel([
              PdfInfoEntry(
                'Expected Shipment Date',
                SharedPdfTemplate.dateOnlyFormat.format(order.shipmentDate),
              ),
              PdfInfoEntry(
                'Order Status',
                'Booking Confirmed',
                alignment: pw.CrossAxisAlignment.end,
                valueColor: SharedPdfTemplate.successEmerald,
              ),
            ]),
            pw.SizedBox(height: 20),

            // Items Section Title
            SharedPdfTemplate.buildSectionTitle('Ordered Line Items'),

            // Dynamic Line Items Table
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
                2: pw.FlexColumnWidth(0.8), // Qty
                3: pw.FlexColumnWidth(1.0), // Rate
                4: pw.FlexColumnWidth(1.0), // Tax Amount
                5: pw.FlexColumnWidth(1.2), // Line Total
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
                    SharedPdfTemplate.buildTableHeader('Qty'),
                    SharedPdfTemplate.buildTableHeader('Rate'),
                    SharedPdfTemplate.buildTableHeader('Tax Amt'),
                    SharedPdfTemplate.buildTableHeader('Total'),
                  ],
                ),
                // Item Rows
                for (int i = 0; i < order.items.length; i++) ...[
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i % 2 == 0
                          ? PdfColors.white
                          : SharedPdfTemplate.lightGreyBackground,
                    ),
                    children: [
                      SharedPdfTemplate.buildTableCell('${i + 1}'),
                      SharedPdfTemplate.buildTableCell(
                        '${order.items[i].item.name}\nSKU: ${order.items[i].item.sku}'
                        '${order.items[i].discount > 0 ? ' | Disc: $currencySymbol${order.items[i].discount.toStringAsFixed(2)}' : ''}',
                        alignLeft: true,
                        isSubText: true,
                      ),
                      SharedPdfTemplate.buildTableCell(
                        '${order.items[i].quantity}',
                      ),
                      SharedPdfTemplate.buildTableCell(
                        '$currencySymbol${order.items[i].rate.toStringAsFixed(2)}',
                      ),
                      SharedPdfTemplate.buildTableCell(
                        '$currencySymbol${order.items[i].taxAmount.toStringAsFixed(2)} (${order.items[i].taxPercentage.toStringAsFixed(0)}%)',
                      ),
                      SharedPdfTemplate.buildTableCell(
                        '$currencySymbol${order.items[i].total.toStringAsFixed(2)}',
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
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left Column: Notes & Remarks
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'REMARKS & NOTES',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        order.notes.isNotEmpty
                            ? order.notes
                            : 'No specific delivery instructions.',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: SharedPdfTemplate.slateText,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 32),
                // Right Column: Totals Calculation Card
                SharedPdfTemplate.buildTotalsCard(
                  rows: [
                    SharedPdfTemplate.buildSummaryRow(
                      'Sub Total',
                      '$currencySymbol${order.subTotal.toStringAsFixed(2)}',
                    ),
                    if (order.discountTotal > 0) ...[
                      pw.SizedBox(height: 4),
                      SharedPdfTemplate.buildSummaryRow(
                        'Discount Total',
                        '$currencySymbol${order.discountTotal.toStringAsFixed(2)}',
                      ),
                    ],
                    pw.SizedBox(height: 4),
                    SharedPdfTemplate.buildSummaryRow(
                      'VAT / Tax Total',
                      '$currencySymbol${order.taxTotal.toStringAsFixed(2)}',
                    ),
                    if (order.roundOff != 0) ...[
                      pw.SizedBox(height: 4),
                      SharedPdfTemplate.buildSummaryRow(
                        'Round Off',
                        '$currencySymbol${order.roundOff.toStringAsFixed(2)}',
                      ),
                    ],
                  ],
                  grandTotalLabel: 'Grand Total',
                  grandTotalValue:
                      '$currencySymbol${order.total.toStringAsFixed(2)}',
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
