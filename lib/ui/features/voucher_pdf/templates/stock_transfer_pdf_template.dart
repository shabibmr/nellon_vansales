import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../domain/models/organization.dart';
import '../../../../domain/models/stock_transfer.dart';
import '../../../core/utils/quantity_format.dart';
import 'shared_pdf_template.dart';

/// PDF template for generating professional Stock Transfer (Issue to Van / Stock Unloading) documents.
class StockTransferPdfTemplate {
  static pw.Document generate(
    StockTransfer transfer,
    Organization org, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) {
    final pdf = pw.Document();
    final isLoad = transfer.direction == StockTransferDirection.load;
    final voucherTitle = isLoad ? 'Issue to Van' : 'Stock Unloading';
    final voucherNumber = transfer.transferNumber.isNotEmpty
        ? transfer.transferNumber
        : transfer.id;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            // Letterhead Header
            SharedPdfTemplate.buildHeader(
              org: org,
              voucherTitle: voucherTitle,
              voucherNumber: voucherNumber,
              date: transfer.date,
            ),
            pw.SizedBox(height: 16),

            // Transfer Locations Grid (Source and Destination)
            SharedPdfTemplate.buildClientGrid(
              billFromLabel: isLoad
                  ? 'Source (Warehouse / Depot)'
                  : 'Source (Van / Salesperson)',
              companyName: isLoad ? org.name : 'Route Delivery Van',
              companyDetails: isLoad
                  ? 'Main Inventory Depot\nLocation: ${transfer.fromLocationId}'
                  : 'On-Road Mobile Stock Location\nLocation: ${transfer.fromLocationId}',
              billToLabel: isLoad
                  ? 'Destination (Van / Salesperson)'
                  : 'Destination (Warehouse / Depot)',
              clientName: isLoad ? 'Route Delivery Van' : org.name,
              clientPhone: null,
              clientEmail: null,
              clientAddress: isLoad
                  ? 'On-Road Mobile Stock Location\nLocation: ${transfer.toLocationId}'
                  : 'Main Inventory Depot\nLocation: ${transfer.toLocationId}',
            ),
            pw.SizedBox(height: 20),

            // Movement Metadata Info Panel
            SharedPdfTemplate.buildInfoPanel([
              PdfInfoEntry(
                'Movement Type',
                isLoad
                    ? 'Issue to Van (Stock Load)'
                    : 'Stock Unloading (Van Return)',
              ),
              PdfInfoEntry(
                'Transfer Status',
                transfer.status.toUpperCase(),
                alignment: pw.CrossAxisAlignment.center,
              ),
              PdfInfoEntry(
                'Line Items',
                '${transfer.lines.length} items',
                alignment: pw.CrossAxisAlignment.end,
              ),
            ]),
            pw.SizedBox(height: 20),

            // Items Section Title
            SharedPdfTemplate.buildSectionTitle('Transferred Stock Items'),

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
                0: pw.FlexColumnWidth(0.6), // #
                1: pw.FlexColumnWidth(2.8), // Item Name & SKU
                2: pw.FlexColumnWidth(1.2), // Total Qty
                3: pw.FlexColumnWidth(1.4), // Pack / Entered Units
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
                    SharedPdfTemplate.buildTableHeader('Total Qty'),
                    SharedPdfTemplate.buildTableHeader('Pack / Entered Units'),
                  ],
                ),
                // Item Rows
                for (int i = 0; i < transfer.lines.length; i++) ...[
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i % 2 == 0
                          ? PdfColors.white
                          : SharedPdfTemplate.lightGreyBackground,
                    ),
                    children: [
                      SharedPdfTemplate.buildTableCell('${i + 1}'),
                      SharedPdfTemplate.buildTableCell(
                        '${transfer.lines[i].item.name}\nSKU: ${transfer.lines[i].item.sku}',
                        alignLeft: true,
                        isSubText: true,
                      ),
                      SharedPdfTemplate.buildTableCell(
                        '${formatQuantity(transfer.lines[i].quantity)}'
                        '${transfer.lines[i].item.uom.isNotEmpty ? ' ${transfer.lines[i].item.uom}' : ''}',
                        isBold: true,
                      ),
                      SharedPdfTemplate.buildTableCell(
                        transfer.lines[i].conversionRate > 0 &&
                                transfer.lines[i].conversionRate != 1.0 &&
                                transfer.lines[i].uom.isNotEmpty
                            ? '${formatQuantity(transfer.lines[i].enteredQuantity)} ${transfer.lines[i].uom}'
                            : (transfer.lines[i].uom.isNotEmpty
                                ? transfer.lines[i].uom
                                : '—'),
                        isSubText: true,
                      ),
                    ],
                  ),
                ],
              ],
            ),
            pw.SizedBox(height: 20),

            // Summary Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left Column: Remarks & Notes
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
                        transfer.notes.isNotEmpty
                            ? transfer.notes
                            : 'No specific notes or instructions recorded.',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: SharedPdfTemplate.slateText,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 32),
                // Right Column: Summary Card
                SharedPdfTemplate.buildTotalsCard(
                  rows: [
                    SharedPdfTemplate.buildSummaryRow(
                      'Total Unique Lines',
                      '${transfer.lines.length}',
                    ),
                  ],
                  grandTotalLabel: 'Total Quantity',
                  grandTotalValue: formatQuantity(transfer.totalQuantity),
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
