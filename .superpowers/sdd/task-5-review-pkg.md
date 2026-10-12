# Review package Task 5
BASE 07264d845fdff4c5cd0f8b9124afc59635330b31
HEAD 5113c9dec6a88318bf7485fb4422c886af11f55b
## Commits
5113c9d Print Firestore supervisor phone on thermal tickets.

## Stat
 .../services/esc_pos/esc_pos_ticket_builder.dart   | 17 ++++++++++++----
 .../services/esc_pos/report_ticket_builder.dart    |  6 ++++++
 .../services/esc_pos/voucher_ticket_builder.dart   | 23 ++++++++++++++++++++++
 lib/data/services/thermal_printer_service.dart     |  8 ++++++++
 .../repositories/thermal_printer_repository.dart   |  4 ++++
 lib/ui/core/widgets/sortable_report_scaffold.dart  |  4 ++++
 .../ledger/views/customer_ledger_page.dart         |  4 ++++
 .../reports/views/shipment_orders_report_page.dart |  4 ++++
 .../thermal_print/cubit/thermal_printer_cubit.dart |  8 ++++++++
 .../widgets/voucher_pdf_actions_widget.dart        |  5 +++++
 test/esc_pos_ticket_builder_test.dart              | 16 +++++++++++++++
 test/report_ticket_builder_test.dart               | 14 +++++++++++++
 12 files changed, 109 insertions(+), 4 deletions(-)

## Diff
diff --git a/lib/data/services/esc_pos/esc_pos_ticket_builder.dart b/lib/data/services/esc_pos/esc_pos_ticket_builder.dart
index 06284c3..e62b628 100644
--- a/lib/data/services/esc_pos/esc_pos_ticket_builder.dart
+++ b/lib/data/services/esc_pos/esc_pos_ticket_builder.dart
@@ -1,16 +1,18 @@
 import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
 import 'package:intl/intl.dart';
 
+import '../../../domain/models/print_settings.dart';
 import '../../../domain/models/thermal_paper_size.dart';
 import '../../../domain/models/thermal_ticket_preview.dart';
 import '../../../domain/utils/amount_in_words.dart';
+import '../../../domain/utils/supervisor_label.dart';
 
 /// Shared ESC/POS layout helpers for 2" / 4" thermal tickets.
 class EscPosTicketBuilder {
   EscPosTicketBuilder({required this.generator, required this.paperSize})
     : columns = paperSize.columns;
 
   final Generator generator;
   final ThermalPaperSize paperSize;
   final int columns;
 
@@ -614,29 +616,36 @@ class EscPosTicketBuilder {
           : symbol,
     );
     final words = amountInWords(total, currencyName: unit);
     bytes.addAll(left('In words:', bold: true));
     for (final line in wrapText(words, columns)) {
       bytes.addAll(left(line));
     }
     return bytes;
   }
 
-  static const String supervisorContact = 'Supervisor : +971 501880810';
-
-  List<int> footer({String? salespersonName, String? salespersonPhone}) {
+  List<int> footer({
+    String? salespersonName,
+    String? salespersonPhone,
+    String? supervisorPhone,
+  }) {
     final bytes = <int>[];
     bytes.addAll(divider());
     final name = salespersonName?.trim() ?? '';
     final phone = salespersonPhone?.trim() ?? '';
     final salesmanRole = name.isEmpty
         ? '( Salesman ) :'
         : '$name ( Salesman ) :';
     final salesmanLine = phone.isEmpty ? salesmanRole : '$salesmanRole $phone';
     bytes.addAll(left(truncate(salesmanLine, columns)));
-    bytes.addAll(left(truncate(supervisorContact, columns)));
+    final supervisorLine = formatSupervisorLine(
+      (supervisorPhone == null || supervisorPhone.trim().isEmpty)
+          ? PrintSettings.fallbackSupervisorPhone
+          : supervisorPhone,
+    );
+    bytes.addAll(left(truncate(supervisorLine, columns)));
     bytes.addAll(center('Thank you'));
     bytes.addAll(doubleDivider());
     bytes.addAll(cut());
     return bytes;
   }
 }
diff --git a/lib/data/services/esc_pos/report_ticket_builder.dart b/lib/data/services/esc_pos/report_ticket_builder.dart
index 645c284..05467d3 100644
--- a/lib/data/services/esc_pos/report_ticket_builder.dart
+++ b/lib/data/services/esc_pos/report_ticket_builder.dart
@@ -22,79 +22,84 @@ class ReportTicketBuilder {
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     required ThermalPaperSize paperSize,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
     DateTime? generatedAt,
   }) async {
     final composed = await _compose(
       title: title,
       headers: headers,
       rows: rows,
       org: org,
       paperSize: paperSize,
       subtitle: subtitle,
       dateRangeText: dateRangeText,
       summaryStats: summaryStats,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
       generatedAt: generatedAt,
     );
     return composed.bytes;
   }
 
   /// Builds an on-screen preview of the thermal ticket.
   static Future<ThermalTicketPreview> buildPreview({
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     required ThermalPaperSize paperSize,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
     DateTime? generatedAt,
   }) async {
     final composed = await _compose(
       title: title,
       headers: headers,
       rows: rows,
       org: org,
       paperSize: paperSize,
       subtitle: subtitle,
       dateRangeText: dateRangeText,
       summaryStats: summaryStats,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
       generatedAt: generatedAt,
     );
     return composed.preview;
   }
 
   static Future<({List<int> bytes, ThermalTicketPreview preview})> _compose({
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     required ThermalPaperSize paperSize,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
     DateTime? generatedAt,
   }) async {
     final profile = await CapabilityProfile.load();
     final escPaper = EscPosTicketBuilder.toEscPosPaperSize(paperSize);
     final generator = Generator(escPaper, profile);
     final b = EscPosTicketBuilder(generator: generator, paperSize: paperSize);
 
     final bytes = <int>[];
     bytes.addAll(b.reset());
 
@@ -223,20 +228,21 @@ class ReportTicketBuilder {
       _padToMinLength(
         b,
         buildTail: (tail) {
           final after = <int>[];
           after.addAll(tail.divider());
           after.addAll(tail.left('Generated: $timestamp'));
           after.addAll(
             tail.footer(
               salespersonName: salespersonName,
               salespersonPhone: salespersonPhone,
+              supervisorPhone: supervisorPhone,
             ),
           );
           return after;
         },
       ),
     );
 
     return (bytes: bytes, preview: b.toPreview());
   }
 
diff --git a/lib/data/services/esc_pos/voucher_ticket_builder.dart b/lib/data/services/esc_pos/voucher_ticket_builder.dart
index 628ad41..36f70b6 100644
--- a/lib/data/services/esc_pos/voucher_ticket_builder.dart
+++ b/lib/data/services/esc_pos/voucher_ticket_builder.dart
@@ -17,135 +17,146 @@ import 'esc_pos_ticket_builder.dart';
 class VoucherTicketBuilder {
   /// Creates a ticket for [type] using the active [paperSize].
   static Future<List<int>> build({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     required ThermalPaperSize paperSize,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) async {
     final composed = await _compose(
       type: type,
       voucher: voucher,
       org: org,
       customer: customer,
       paperSize: paperSize,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
     );
     return composed.bytes;
   }
 
   /// Same layout as [build], as styled lines for an on-screen print preview.
   static Future<ThermalTicketPreview> buildPreview({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     required ThermalPaperSize paperSize,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) async {
     final composed = await _compose(
       type: type,
       voucher: voucher,
       org: org,
       customer: customer,
       paperSize: paperSize,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
     );
     return composed.preview;
   }
 
   static Future<({List<int> bytes, ThermalTicketPreview preview})> _compose({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     required ThermalPaperSize paperSize,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) async {
     final profile = await CapabilityProfile.load();
     final escPaper = EscPosTicketBuilder.toEscPosPaperSize(paperSize);
     final generator = Generator(escPaper, profile);
     final b = EscPosTicketBuilder(generator: generator, paperSize: paperSize);
 
     final bytes = <int>[];
     bytes.addAll(b.reset());
 
     switch (type) {
       case VoucherType.salesInvoice:
         bytes.addAll(
           _invoice(
             b,
             voucher as SalesInvoice,
             org,
             customer,
             salespersonName,
             salespersonPhone,
+            supervisorPhone,
           ),
         );
       case VoucherType.salesOrder:
         bytes.addAll(
           _order(
             b,
             voucher as SalesOrder,
             org,
             customer,
             salespersonName,
             salespersonPhone,
+            supervisorPhone,
           ),
         );
       case VoucherType.salesReturn:
         bytes.addAll(
           _return(
             b,
             voucher as SalesReturn,
             org,
             customer,
             salespersonName,
             salespersonPhone,
+            supervisorPhone,
           ),
         );
       case VoucherType.paymentReceipt:
         bytes.addAll(
           _receipt(
             b,
             voucher as ReceiptVoucher,
             org,
             customer,
             salespersonName,
             salespersonPhone,
+            supervisorPhone,
           ),
         );
       case VoucherType.expenseVoucher:
         bytes.addAll(
           _expense(
             b,
             voucher as ExpenseEntry,
             org,
             salespersonName,
             salespersonPhone,
+            supervisorPhone,
           ),
         );
       case VoucherType.stockTransfer:
         bytes.addAll(
           _stockTransfer(
             b,
             voucher as StockTransfer,
             org,
             salespersonName,
             salespersonPhone,
+            supervisorPhone,
           ),
         );
     }
 
     return (bytes: bytes, preview: b.toPreview());
   }
 
   /// Short calibration page for Settings → Test print.
   static Future<List<int>> buildTestPage({
     required ThermalPaperSize paperSize,
@@ -231,20 +242,21 @@ class VoucherTicketBuilder {
     );
   }
 
   static List<int> _invoice(
     EscPosTicketBuilder b,
     SalesInvoice invoice,
     Organization org,
     Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   ) {
     final symbol = org.currencySymbol;
     final bytes = <int>[];
     bytes.addAll(
       _orgHeader(
         b,
         org,
         voucherTitle: 'SALES INVOICE',
         voucherNumber: invoice.invoiceNumber,
         date: invoice.date,
@@ -288,36 +300,38 @@ class VoucherTicketBuilder {
             after.addAll(
               tail.left(
                 'Notes: ${tail.truncate(invoice.notes, tail.columns - 7)}',
               ),
             );
           }
           after.addAll(
             tail.footer(
               salespersonName: salespersonName,
               salespersonPhone: salespersonPhone,
+              supervisorPhone: supervisorPhone,
             ),
           );
           return after;
         },
       ),
     );
     return bytes;
   }
 
   static List<int> _order(
     EscPosTicketBuilder b,
     SalesOrder order,
     Organization org,
     Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   ) {
     final symbol = org.currencySymbol;
     final bytes = <int>[];
     bytes.addAll(
       _orgHeader(
         b,
         org,
         voucherTitle: 'SALES ORDER',
         voucherNumber: order.orderNumber,
         date: order.date,
@@ -367,36 +381,38 @@ class VoucherTicketBuilder {
             after.addAll(
               tail.left(
                 'Notes: ${tail.truncate(order.notes, tail.columns - 7)}',
               ),
             );
           }
           after.addAll(
             tail.footer(
               salespersonName: salespersonName,
               salespersonPhone: salespersonPhone,
+              supervisorPhone: supervisorPhone,
             ),
           );
           return after;
         },
       ),
     );
     return bytes;
   }
 
   static List<int> _return(
     EscPosTicketBuilder b,
     SalesReturn salesReturn,
     Organization org,
     Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   ) {
     final symbol = org.currencySymbol;
     final bytes = <int>[];
     bytes.addAll(
       _orgHeader(
         b,
         org,
         voucherTitle: 'SALES RETURN',
         voucherNumber: salesReturn.creditNoteNumber,
         date: salesReturn.date,
@@ -440,36 +456,38 @@ class VoucherTicketBuilder {
             after.addAll(
               tail.left(
                 'Reason: ${tail.truncate(salesReturn.reason, tail.columns - 8)}',
               ),
             );
           }
           after.addAll(
             tail.footer(
               salespersonName: salespersonName,
               salespersonPhone: salespersonPhone,
+              supervisorPhone: supervisorPhone,
             ),
           );
           return after;
         },
       ),
     );
     return bytes;
   }
 
   static List<int> _receipt(
     EscPosTicketBuilder b,
     ReceiptVoucher receipt,
     Organization org,
     Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   ) {
     final symbol = org.currencySymbol;
     final bytes = <int>[];
     bytes.addAll(
       _orgHeader(
         b,
         org,
         voucherTitle: 'RECEIPT',
         voucherNumber: receipt.paymentNumber,
         date: receipt.date,
@@ -503,32 +521,34 @@ class VoucherTicketBuilder {
         );
       }
     }
     bytes.addAll(
       _padToMinLength(
         b,
         tableStyle: false,
         buildTail: (tail) => tail.footer(
           salespersonName: salespersonName,
           salespersonPhone: salespersonPhone,
+          supervisorPhone: supervisorPhone,
         ),
       ),
     );
     return bytes;
   }
 
   static List<int> _expense(
     EscPosTicketBuilder b,
     ExpenseEntry expense,
     Organization org,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   ) {
     final symbol = org.currencySymbol;
     final bytes = <int>[];
     bytes.addAll(
       _orgHeader(
         b,
         org,
         voucherTitle: 'EXPENSE',
         voucherNumber: expense.id,
         date: expense.date,
@@ -562,35 +582,37 @@ class VoucherTicketBuilder {
             tail.totalsBlock(
               symbol: symbol,
               currencyCode: org.currencyCode,
               total: expense.amount,
             ),
           );
           after.addAll(
             tail.footer(
               salespersonName: salespersonName,
               salespersonPhone: salespersonPhone,
+              supervisorPhone: supervisorPhone,
             ),
           );
           return after;
         },
       ),
     );
     return bytes;
   }
 
   static List<int> _stockTransfer(
     EscPosTicketBuilder b,
     StockTransfer transfer,
     Organization org,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   ) {
     final bytes = <int>[];
     final isLoad = transfer.direction == StockTransferDirection.load;
     final voucherTitle = isLoad ? 'ISSUE TO VAN' : 'STOCK UNLOADING';
     final voucherNumber = transfer.transferNumber.isNotEmpty
         ? transfer.transferNumber
         : transfer.id;
 
     bytes.addAll(
       _orgHeader(
@@ -661,20 +683,21 @@ class VoucherTicketBuilder {
             after.addAll(
               tail.left(
                 'Notes: ${tail.truncate(transfer.notes, tail.columns - 7)}',
               ),
             );
           }
           after.addAll(
             tail.footer(
               salespersonName: salespersonName,
               salespersonPhone: salespersonPhone,
+              supervisorPhone: supervisorPhone,
             ),
           );
           return after;
         },
       ),
     );
     return bytes;
   }
 
   /// UAE VAT line label, e.g. `VAT @ 5%`.
diff --git a/lib/data/services/thermal_printer_service.dart b/lib/data/services/thermal_printer_service.dart
index e0ddd4b..d6f3f28 100644
--- a/lib/data/services/thermal_printer_service.dart
+++ b/lib/data/services/thermal_printer_service.dart
@@ -121,103 +121,111 @@ class ThermalPrinterService implements ThermalPrinterRepository {
   }
 
   @override
   Future<void> printVoucher({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) async {
     final bytes = await VoucherTicketBuilder.build(
       type: type,
       voucher: voucher,
       org: org,
       customer: customer,
       paperSize: paperSize,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
     );
     await _writeBytes(bytes);
   }
 
   @override
   Future<ThermalTicketPreview> buildVoucherPreview({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) {
     return VoucherTicketBuilder.buildPreview(
       type: type,
       voucher: voucher,
       org: org,
       customer: customer,
       paperSize: paperSize,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
     );
   }
 
   @override
   Future<void> printReport({
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) async {
     final bytes = await ReportTicketBuilder.build(
       title: title,
       headers: headers,
       rows: rows,
       org: org,
       paperSize: paperSize,
       subtitle: subtitle,
       dateRangeText: dateRangeText,
       summaryStats: summaryStats,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
     );
     await _writeBytes(bytes);
   }
 
   @override
   Future<ThermalTicketPreview> buildReportPreview({
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) {
     return ReportTicketBuilder.buildPreview(
       title: title,
       headers: headers,
       rows: rows,
       org: org,
       paperSize: paperSize,
       subtitle: subtitle,
       dateRangeText: dateRangeText,
       summaryStats: summaryStats,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
     );
   }
 
   @override
   Future<void> printTestPage() async {
     final bytes = await VoucherTicketBuilder.buildTestPage(
       paperSize: paperSize,
       printerName: preferredPrinter?.name,
     );
     await _writeBytes(bytes);
diff --git a/lib/domain/repositories/thermal_printer_repository.dart b/lib/domain/repositories/thermal_printer_repository.dart
index d8f9b36..5fe2484 100644
--- a/lib/domain/repositories/thermal_printer_repository.dart
+++ b/lib/domain/repositories/thermal_printer_repository.dart
@@ -40,51 +40,55 @@ abstract class ThermalPrinterRepository {
   /// Builds an ESC/POS ticket for [voucher] and writes it to the connected printer.
   ///
   /// Connects to [preferredPrinter] automatically when not already connected.
   Future<void> printVoucher({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   });
 
   /// Builds the same ticket layout as [printVoucher] without sending bytes.
   Future<ThermalTicketPreview> buildVoucherPreview({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   });
 
   /// Builds an ESC/POS report ticket and writes it to the connected printer.
   Future<void> printReport({
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   });
 
   /// Builds the same report ticket layout as [printReport] as preview lines.
   Future<ThermalTicketPreview> buildReportPreview({
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   });
 
   /// Prints a short calibration ticket showing paper size and connection info.
   Future<void> printTestPage();
 }
diff --git a/lib/ui/core/widgets/sortable_report_scaffold.dart b/lib/ui/core/widgets/sortable_report_scaffold.dart
index 0b22018..1d1bf6e 100644
--- a/lib/ui/core/widgets/sortable_report_scaffold.dart
+++ b/lib/ui/core/widgets/sortable_report_scaffold.dart
@@ -1,15 +1,16 @@
 import 'package:flutter/material.dart';
 import 'package:flutter_bloc/flutter_bloc.dart';
 import 'package:intl/intl.dart';
 
 import '../../../data/services/report_export_service.dart';
+import '../../features/print_settings/cubit/print_settings_cubit.dart';
 import '../../features/thermal_print/cubit/thermal_printer_cubit.dart';
 import '../../features/thermal_print/widgets/thermal_print_preview_dialog.dart';
 import '../cubit/salesperson_cubit.dart';
 import '../extensions/org_context_extension.dart';
 import '../theme/app_theme.dart';
 import '../utils/error_mapper.dart';
 import 'date_range_filter_card.dart';
 
 /// A single tap-to-sort column header for [SortableReportScaffold].
 class ReportColumn<F extends Enum> {
@@ -134,49 +135,52 @@ class SortableReportScaffold<T, F extends Enum> extends StatelessWidget {
       switch (action) {
         case 'thermal':
           final org = context.org.state;
           if (org == null) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('No organization details found')),
             );
             return;
           }
           final salesperson = context.read<SalespersonCubit>().state;
+          final supervisorPhone = context.read<PrintSettingsCubit>().supervisorPhone;
           final printerCubit = context.read<ThermalPrinterCubit>();
           final dateRangeText = _formatDateRange();
           final summaryStats = {
             for (final chip in summaryChips) chip.label: chip.value,
           };
           final preview = await printerCubit.previewReport(
             title: title,
             headers: headers,
             rows: data,
             org: org,
             dateRangeText: dateRangeText,
             summaryStats: summaryStats,
             salespersonName: salesperson?.name,
             salespersonPhone: salesperson?.phone,
+            supervisorPhone: supervisorPhone,
           );
           if (!context.mounted) return;
           await ThermalPrintPreviewDialog.show(
             context,
             preview: preview,
             onPrint: () {
               printerCubit.printReport(
                 title: title,
                 headers: headers,
                 rows: data,
                 org: org,
                 dateRangeText: dateRangeText,
                 summaryStats: summaryStats,
                 salespersonName: salesperson?.name,
                 salespersonPhone: salesperson?.phone,
+                supervisorPhone: supervisorPhone,
               );
             },
           );
           break;
         case 'csv':
           await ReportExportService.exportCsv(title, headers, data);
           break;
         case 'pdf':
           await ReportExportService.exportPdf(title, headers, data);
           break;
diff --git a/lib/ui/features/ledger/views/customer_ledger_page.dart b/lib/ui/features/ledger/views/customer_ledger_page.dart
index 4d2e439..550c2c4 100644
--- a/lib/ui/features/ledger/views/customer_ledger_page.dart
+++ b/lib/ui/features/ledger/views/customer_ledger_page.dart
@@ -2,20 +2,21 @@ import 'package:flutter/material.dart';
 import 'package:flutter_bloc/flutter_bloc.dart';
 import 'package:intl/intl.dart';
 import '../../../../data/services/report_export_service.dart';
 import '../../../../domain/models/customer_ledger.dart';
 import '../../../../ui/core/cubit/salesperson_cubit.dart';
 import '../../../../ui/core/extensions/org_context_extension.dart';
 import '../../../../ui/core/theme/app_theme.dart';
 import '../../../../ui/core/utils/date_picker.dart';
 import '../../../../ui/core/utils/error_mapper.dart';
 import '../../../../ui/core/utils/snackbars.dart';
+import '../../print_settings/cubit/print_settings_cubit.dart';
 import '../../thermal_print/cubit/thermal_printer_cubit.dart';
 import '../../thermal_print/widgets/thermal_print_preview_dialog.dart';
 import '../bloc/customer_ledger_bloc.dart';
 import '../utils/open_ledger_transaction.dart';
 import '../widgets/customer_ledger_header.dart';
 import '../widgets/ledger_filter_header.dart';
 import '../widgets/ledger_transaction_table.dart';
 
 class CustomerLedgerPage extends StatefulWidget {
   const CustomerLedgerPage({super.key});
@@ -224,47 +225,50 @@ class _CustomerLedgerPageState extends State<CustomerLedgerPage> {
       switch (action) {
         case 'thermal':
           final org = context.org.state;
           if (org == null) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('No organization details found')),
             );
             return;
           }
           final salesperson = context.read<SalespersonCubit>().state;
+          final supervisorPhone = context.read<PrintSettingsCubit>().supervisorPhone;
           final printerCubit = context.read<ThermalPrinterCubit>();
           final preview = await printerCubit.previewReport(
             title: 'CUSTOMER LEDGER',
             subtitle: 'Customer: ${ledger.customerName}',
             headers: headers,
             rows: data,
             org: org,
             dateRangeText: dateRange,
             summaryStats: stats,
             salespersonName: salesperson?.name,
             salespersonPhone: salesperson?.phone,
+            supervisorPhone: supervisorPhone,
           );
           if (!context.mounted) return;
           await ThermalPrintPreviewDialog.show(
             context,
             preview: preview,
             onPrint: () {
               printerCubit.printReport(
                 title: 'CUSTOMER LEDGER',
                 subtitle: 'Customer: ${ledger.customerName}',
                 headers: headers,
                 rows: data,
                 org: org,
                 dateRangeText: dateRange,
                 summaryStats: stats,
                 salespersonName: salesperson?.name,
                 salespersonPhone: salesperson?.phone,
+                supervisorPhone: supervisorPhone,
               );
             },
           );
           break;
         case 'print':
           await ReportExportService.printReport(title, headers, data);
           break;
         case 'pdf':
           await ReportExportService.exportPdf(title, headers, data);
           break;
diff --git a/lib/ui/features/reports/views/shipment_orders_report_page.dart b/lib/ui/features/reports/views/shipment_orders_report_page.dart
index 93bf5b6..2e11623 100644
--- a/lib/ui/features/reports/views/shipment_orders_report_page.dart
+++ b/lib/ui/features/reports/views/shipment_orders_report_page.dart
@@ -14,20 +14,21 @@ import '../../../core/utils/quantity_format.dart';
 import '../../../core/utils/snackbars.dart';
 import '../../../core/widgets/date_range_filter_card.dart';
 import '../../../core/widgets/document_list_card.dart';
 import '../../../core/widgets/empty_state.dart';
 import '../../../core/widgets/status_pill.dart';
 import '../../sales_invoice/bloc/sales_invoice_list_bloc.dart' as inv;
 import '../../sales_invoice/bloc/sales_invoice_list_event.dart' as inv;
 import '../../sales_invoice/bloc/sales_invoice_list_state.dart' as inv;
 import '../../sales_order/views/sales_order_editor_page.dart';
 import '../../stock_transfer/views/issue_to_van_page.dart';
+import '../../print_settings/cubit/print_settings_cubit.dart';
 import '../../thermal_print/cubit/thermal_printer_cubit.dart';
 import '../../thermal_print/widgets/thermal_print_preview_dialog.dart';
 import '../bloc/report_bloc.dart';
 import '../bloc/report_event.dart';
 import '../bloc/report_state.dart';
 import '../bloc/shipment_orders_cubit.dart';
 import '../widgets/report_bloc_host.dart';
 import '../widgets/report_date_actions.dart';
 
 /// Shipment-day workspace: filter sales orders by shipment date, multi-select
@@ -161,45 +162,48 @@ class _ShipmentOrdersReportBody extends StatelessWidget {
       switch (action) {
         case 'thermal':
           final org = context.org.state;
           if (org == null) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('No organization details found')),
             );
             return;
           }
           final salesperson = context.read<SalespersonCubit>().state;
+          final supervisorPhone = context.read<PrintSettingsCubit>().supervisorPhone;
           final printerCubit = context.read<ThermalPrinterCubit>();
           final preview = await printerCubit.previewReport(
             title: 'SHIPMENT ORDERS',
             headers: headers,
             rows: data,
             org: org,
             dateRangeText: dateRange,
             summaryStats: stats,
             salespersonName: salesperson?.name,
             salespersonPhone: salesperson?.phone,
+            supervisorPhone: supervisorPhone,
           );
           if (!context.mounted) return;
           await ThermalPrintPreviewDialog.show(
             context,
             preview: preview,
             onPrint: () {
               printerCubit.printReport(
                 title: 'SHIPMENT ORDERS',
                 headers: headers,
                 rows: data,
                 org: org,
                 dateRangeText: dateRange,
                 summaryStats: stats,
                 salespersonName: salesperson?.name,
                 salespersonPhone: salesperson?.phone,
+                supervisorPhone: supervisorPhone,
               );
             },
           );
           break;
         case 'print':
           await ReportExportService.printReport(title, headers, data);
           break;
         case 'pdf':
           await ReportExportService.exportPdf(title, headers, data);
           break;
diff --git a/lib/ui/features/thermal_print/cubit/thermal_printer_cubit.dart b/lib/ui/features/thermal_print/cubit/thermal_printer_cubit.dart
index fe1b34c..5bae678 100644
--- a/lib/ui/features/thermal_print/cubit/thermal_printer_cubit.dart
+++ b/lib/ui/features/thermal_print/cubit/thermal_printer_cubit.dart
@@ -267,63 +267,68 @@ class ThermalPrinterCubit extends Cubit<ThermalPrinterState> {
   }
 
   /// Builds a visual ticket preview. Does not connect or change print state.
   Future<ThermalTicketPreview> previewVoucher({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) {
     return _repo.buildVoucherPreview(
       type: type,
       voucher: voucher,
       org: org,
       customer: customer,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
     );
   }
 
   /// Builds a visual report ticket preview.
   Future<ThermalTicketPreview> previewReport({
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) {
     return _repo.buildReportPreview(
       title: title,
       headers: headers,
       rows: rows,
       org: org,
       subtitle: subtitle,
       dateRangeText: dateRangeText,
       summaryStats: summaryStats,
       salespersonName: salespersonName,
       salespersonPhone: salespersonPhone,
+      supervisorPhone: supervisorPhone,
     );
   }
 
   Future<void> printVoucher({
     required VoucherType type,
     required dynamic voucher,
     required Organization org,
     required Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) async {
     emit(
       state.copyWith(
         isPrinting: true,
         clearError: true,
         clearStatus: true,
         clearNeedsAppSettings: true,
       ),
     );
     try {
@@ -331,20 +336,21 @@ class ThermalPrinterCubit extends Cubit<ThermalPrinterState> {
         emit(state.copyWith(isPrinting: false));
         return;
       }
       await _repo.printVoucher(
         type: type,
         voucher: voucher,
         org: org,
         customer: customer,
         salespersonName: salespersonName,
         salespersonPhone: salespersonPhone,
+        supervisorPhone: supervisorPhone,
       );
       emit(
         state.copyWith(
           isPrinting: false,
           isConnected: true,
           statusMessage: 'Sent to thermal printer',
         ),
       );
     } catch (e) {
       emit(
@@ -360,20 +366,21 @@ class ThermalPrinterCubit extends Cubit<ThermalPrinterState> {
   Future<void> printReport({
     required String title,
     required List<String> headers,
     required List<List<String>> rows,
     required Organization org,
     String? subtitle,
     String? dateRangeText,
     Map<String, String>? summaryStats,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   }) async {
     emit(
       state.copyWith(
         isPrinting: true,
         clearError: true,
         clearStatus: true,
         clearNeedsAppSettings: true,
       ),
     );
     try {
@@ -384,20 +391,21 @@ class ThermalPrinterCubit extends Cubit<ThermalPrinterState> {
       await _repo.printReport(
         title: title,
         headers: headers,
         rows: rows,
         org: org,
         subtitle: subtitle,
         dateRangeText: dateRangeText,
         summaryStats: summaryStats,
         salespersonName: salespersonName,
         salespersonPhone: salespersonPhone,
+        supervisorPhone: supervisorPhone,
       );
       emit(
         state.copyWith(
           isPrinting: false,
           isConnected: true,
           statusMessage: 'Report sent to thermal printer',
         ),
       );
     } catch (e) {
       emit(
diff --git a/lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart b/lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart
index 6676925..1275a2b 100644
--- a/lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart
+++ b/lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart
@@ -11,20 +11,21 @@ import '../../../../domain/repositories/customer_repository.dart';
 import '../../../../domain/repositories/print_settings_repository.dart';
 import '../../../../domain/repositories/session_repository.dart';
 import '../../../../domain/repositories/salesperson_repository.dart';
 import '../../../../domain/repositories/voucher_pdf_repository.dart';
 import '../../../core/cubit/salesperson_cubit.dart';
 import '../../../core/extensions/org_context_extension.dart';
 import '../../../core/theme/app_theme.dart';
 import '../../../core/utils/error_mapper.dart';
 import '../../../core/utils/permission_dialogs.dart';
 import '../../../core/utils/snackbars.dart';
+import '../../print_settings/cubit/print_settings_cubit.dart';
 import '../../thermal_print/cubit/thermal_printer_cubit.dart';
 import '../../thermal_print/cubit/thermal_printer_state.dart';
 import '../../thermal_print/widgets/thermal_print_preview_dialog.dart';
 import '../bloc/voucher_pdf_bloc.dart';
 import '../bloc/voucher_pdf_event.dart';
 import '../bloc/voucher_pdf_state.dart';
 import '../views/voucher_pdf_preview_page.dart';
 
 /// Interactive visual row containing trigger buttons for all PDF capabilities.
 ///
@@ -84,20 +85,21 @@ class _VoucherPdfActionsBody extends StatelessWidget {
       VoucherType.expenseVoucher => null,
       VoucherType.stockTransfer => null,
     };
   }
 
   ({
     Organization org,
     Customer? customer,
     String? salespersonName,
     String? salespersonPhone,
+    String? supervisorPhone,
   })?
   _thermalContext(BuildContext context) {
     final org = context.org.state;
     if (org == null) {
       showErrorSnackBar(
         context,
         'Organization data not loaded — please sync first',
       );
       return null;
     }
@@ -105,49 +107,52 @@ class _VoucherPdfActionsBody extends StatelessWidget {
     final customers = context.read<CustomerRepository>().getCustomers();
     final customer = customerId != null
         ? customers.where((c) => c.id == customerId).firstOrNull
         : null;
     final salesperson = context.read<SalespersonCubit>().state;
     return (
       org: org,
       customer: customer,
       salespersonName: salesperson?.name,
       salespersonPhone: salesperson?.phone,
+      supervisorPhone: context.read<PrintSettingsCubit>().supervisorPhone,
     );
   }
 
   void _printThermal(BuildContext context) {
     final args = _thermalContext(context);
     if (args == null) return;
     context.read<ThermalPrinterCubit>().printVoucher(
       type: type,
       voucher: voucher,
       org: args.org,
       customer: args.customer,
       salespersonName: args.salespersonName,
       salespersonPhone: args.salespersonPhone,
+      supervisorPhone: args.supervisorPhone,
     );
   }
 
   Future<void> _previewThermal(BuildContext context) async {
     final args = _thermalContext(context);
     if (args == null) return;
     final cubit = context.read<ThermalPrinterCubit>();
     await HapticFeedback.mediumImpact();
     try {
       final preview = await cubit.previewVoucher(
         type: type,
         voucher: voucher,
         org: args.org,
         customer: args.customer,
         salespersonName: args.salespersonName,
         salespersonPhone: args.salespersonPhone,
+        supervisorPhone: args.supervisorPhone,
       );
       if (!context.mounted) return;
       await ThermalPrintPreviewDialog.show(
         context,
         preview: preview,
         onPrint: () {
           if (context.mounted) _printThermal(context);
         },
       );
     } catch (e) {
diff --git a/test/esc_pos_ticket_builder_test.dart b/test/esc_pos_ticket_builder_test.dart
index 0c18aa3..6821a91 100644
--- a/test/esc_pos_ticket_builder_test.dart
+++ b/test/esc_pos_ticket_builder_test.dart
@@ -349,20 +349,36 @@ void main() {
       );
       final supervisorIdx = texts.indexWhere(
         (t) => t.contains('Supervisor : +971 501880810'),
       );
       final thanksIdx = texts.indexWhere((t) => t.contains('Thank you'));
       expect(salesIdx, greaterThan(-1));
       expect(supervisorIdx, greaterThan(salesIdx));
       expect(thanksIdx, greaterThan(supervisorIdx));
     });
 
+    test('footer uses the supplied supervisor phone', () async {
+      final preview = await VoucherTicketBuilder.buildPreview(
+        type: VoucherType.salesInvoice,
+        voucher: invoice,
+        org: org,
+        customer: customer,
+        paperSize: ThermalPaperSize.inch4,
+        supervisorPhone: '+971 50 111 2222',
+      );
+      expect(
+        preview.plainText.contains('Supervisor : +971 50 111 2222'),
+        isTrue,
+      );
+      expect(preview.plainText.contains('+971 501880810'), isFalse);
+    });
+
     test('prints salesman role line when number is missing', () async {
       final preview = await VoucherTicketBuilder.buildPreview(
         type: VoucherType.salesInvoice,
         voucher: invoice,
         org: org,
         customer: customer,
         paperSize: ThermalPaperSize.inch4,
         salespersonName: 'Shinad',
       );
       final texts = preview.lines.map((l) => l.text).toList();
diff --git a/test/report_ticket_builder_test.dart b/test/report_ticket_builder_test.dart
index 369f84e..a1e6050 100644
--- a/test/report_ticket_builder_test.dart
+++ b/test/report_ticket_builder_test.dart
@@ -70,20 +70,34 @@ void main() {
       expect(allText, isNot(contains('SKU-002')));
       expect(allText, contains('Premium Product 100ml'));
 
       // 5. Generated timestamp at bottom in footer
       expect(allText, contains('Generated: 20-Aug-2026 08:30 AM'));
       expect(allText, contains('Rashid Khan ( Salesman ) : +971 55 987 6543'));
       expect(allText, contains('Supervisor : +971 501880810'));
       expect(allText, contains('Thank you'));
     });
 
+    test('footer uses the supplied supervisor phone', () async {
+      final preview = await ReportTicketBuilder.buildPreview(
+        title: 'Item Sales Report',
+        headers: headers,
+        rows: rows,
+        org: org,
+        paperSize: ThermalPaperSize.inch4,
+        supervisorPhone: '+971 50 111 2222',
+      );
+      final allText = preview.lines.map((l) => l.text).join('\n');
+      expect(allText, contains('Supervisor : +971 50 111 2222'));
+      expect(allText, isNot(contains('+971 501880810')));
+    });
+
     test('generates valid 4" ESC/POS binary command bytes', () async {
       final bytes = await ReportTicketBuilder.build(
         title: 'Item Sales Report',
         headers: headers,
         rows: rows,
         org: org,
         paperSize: ThermalPaperSize.inch4,
         dateRangeText: '01-Aug-2026 to 20-Aug-2026',
         salespersonName: 'Rashid Khan',
         salespersonPhone: '+971 55 987 6543',
