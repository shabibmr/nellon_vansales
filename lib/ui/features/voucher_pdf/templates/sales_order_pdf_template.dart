import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/models/organization.dart';
import '../../../../domain/models/customer.dart';
import 'shared_pdf_template.dart';

/// PDF template for generating professional Sales Order documents.
class SalesOrderPdfTemplate {
  static pw.Document generate(SalesOrder order, Organization? org, Customer? customer) {
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
              voucherTitle: 'Sales Order',
              voucherNumber: order.orderNumber,
              date: order.date,
            ),
            pw.SizedBox(height: 16),

            // Billing Parties Grid (From and To)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: 'Supplier / Dispatcher',
              companyName: companyName,
              companyDetails: 'On-Route Delivery Van\nTax Registered Vendor',
              billToLabel: 'Ordered By (Customer)',
              clientName: order.customerName,
              clientEmail: customer?.email,
              clientPhone: customer?.phone,
              clientAddress: customer?.address ?? 'No physical address listed',
            ),
            pw.SizedBox(height: 20),

            // Shipment Date Block
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: SharedPdfTemplate.lightGreyBackground,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: SharedPdfTemplate.borderSlate, width: 1),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'EXPECTED SHIPMENT DATE',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        SharedPdfTemplate.dateOnlyFormat.format(order.shipmentDate),
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
                        'ORDER STATUS',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.slateTextSecondary,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Booking Confirmed',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: SharedPdfTemplate.successEmerald,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
                    _buildTableHeader('#', alignLeft: true),
                    _buildTableHeader('Item & SKU', alignLeft: true),
                    _buildTableHeader('Qty'),
                    _buildTableHeader('Rate'),
                    _buildTableHeader('Tax Amt'),
                    _buildTableHeader('Total'),
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
                      _buildTableCell('${i + 1}'),
                      _buildTableCell(
                        '${order.items[i].item.name}\nSKU: ${order.items[i].item.sku}'
                            '${order.items[i].discount > 0 ? ' | Disc: $currencySymbol${order.items[i].discount.toStringAsFixed(2)}' : ''}',
                        alignLeft: true,
                        isSubText: true,
                      ),
                      _buildTableCell('${order.items[i].quantity}'),
                      _buildTableCell('$currencySymbol${order.items[i].rate.toStringAsFixed(2)}'),
                      _buildTableCell('$currencySymbol${order.items[i].taxAmount.toStringAsFixed(2)} (${order.items[i].taxPercentage.toStringAsFixed(0)}%)'),
                      _buildTableCell('$currencySymbol${order.items[i].total.toStringAsFixed(2)}', isBold: true),
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
                        order.notes.isNotEmpty ? order.notes : 'No specific delivery instructions.',
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
                pw.Container(
                  width: 220,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: SharedPdfTemplate.lightGreyBackground,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                    border: pw.Border.all(color: SharedPdfTemplate.borderSlate, width: 1),
                  ),
                  child: pw.Column(
                    children: [
                      _buildSummaryRow('Sub Total', '$currencySymbol${order.subTotal.toStringAsFixed(2)}'),
                      if (order.discountTotal > 0) ...[
                        pw.SizedBox(height: 4),
                        _buildSummaryRow('Discount Total', '$currencySymbol${order.discountTotal.toStringAsFixed(2)}'),
                      ],
                      pw.SizedBox(height: 4),
                      _buildSummaryRow('VAT / Tax Total', '$currencySymbol${order.taxTotal.toStringAsFixed(2)}'),
                      if (order.roundOff != 0) ...[
                        pw.SizedBox(height: 4),
                        _buildSummaryRow('Round Off', '$currencySymbol${order.roundOff.toStringAsFixed(2)}'),
                      ],
                      pw.SizedBox(height: 6),
                      pw.Divider(color: SharedPdfTemplate.borderSlate, thickness: 1),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Grand Total',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: SharedPdfTemplate.slateText,
                            ),
                          ),
                          pw.Text(
                            '$currencySymbol${order.total.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: 13,
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
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
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
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: isSubText ? 7.5 : 8.5,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isSubText ? SharedPdfTemplate.slateTextSecondary : SharedPdfTemplate.slateText,
        ),
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
