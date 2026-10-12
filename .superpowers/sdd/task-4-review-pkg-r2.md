# Review package Task 4 r2
BASE fd070bbf162606af84f3aa1cb825bcb8a6a827d8
HEAD 07264d845fdff4c5cd0f8b9124afc59635330b31
## Commits
07264d8 Fix invoice PDF layout regression and supervisor footer tests.
ce0fb57 Print Firestore supervisor phone on voucher PDFs.

## Stat
 lib/data/services/voucher_pdf_service.dart         |   7 +-
 .../voucher_pdf/bloc/voucher_pdf_bloc.dart         |   4 +
 .../templates/expense_pdf_template.dart            |   3 +-
 .../templates/invoice_pdf_template.dart            |   3 +-
 .../templates/receipt_pdf_template.dart            |   3 +-
 .../templates/sales_order_pdf_template.dart        |   3 +-
 .../templates/sales_return_pdf_template.dart       |   3 +-
 .../voucher_pdf/templates/shared_pdf_template.dart |  12 +-
 .../templates/stock_transfer_pdf_template.dart     |   3 +-
 .../widgets/voucher_pdf_actions_widget.dart        |   2 +
 test/pdf_text_test_utils.dart                      |  61 +++++++
 test/voucher_pdf_bloc_test.dart                    | 182 +++++++++++++++++++++
 test/voucher_pdf_service_test.dart                 |  75 +++++++++
 13 files changed, 346 insertions(+), 15 deletions(-)

## Diff
diff --git a/lib/data/services/voucher_pdf_service.dart b/lib/data/services/voucher_pdf_service.dart
index a5fe87d..259861e 100644
--- a/lib/data/services/voucher_pdf_service.dart
+++ b/lib/data/services/voucher_pdf_service.dart
@@ -7,36 +7,37 @@ import 'package:pdf/widgets.dart' as pw;
 import 'package:printing/printing.dart';
 
 import '../../domain/models/sales_invoice.dart';
 import '../../domain/models/sales_order.dart';
 import '../../domain/models/sales_return.dart';
 import '../../domain/models/receipt_voucher.dart';
 import '../../domain/models/expense_entry.dart';
 import '../../domain/models/stock_transfer.dart';
 import '../../domain/models/organization.dart';
 import '../../domain/models/customer.dart';
+import '../../domain/models/print_settings.dart';
 import '../../domain/models/salesperson.dart';
 import '../../domain/repositories/voucher_pdf_repository.dart';
 
 import '../../ui/features/voucher_pdf/templates/invoice_pdf_template.dart';
 import '../../ui/features/voucher_pdf/templates/sales_order_pdf_template.dart';
 import '../../ui/features/voucher_pdf/templates/sales_return_pdf_template.dart';
 import '../../ui/features/voucher_pdf/templates/receipt_pdf_template.dart';
 import '../../ui/features/voucher_pdf/templates/expense_pdf_template.dart';
 import '../../ui/features/voucher_pdf/templates/stock_transfer_pdf_template.dart';
-import '../../ui/features/voucher_pdf/templates/shared_pdf_template.dart';
 
 /// A comprehensive service responsible for compiling PDFs, writing them to disk as temp files,
 /// and invoking native Android/iOS Print and Share handlers.
 class VoucherPdfService implements VoucherPdfRepository {
-  /// Default supervisor contact for voucher PDFs.
-  static const String defaultSupervisorPhone = SharedPdfTemplate.supervisorContact;
+  /// Default supervisor phone for voucher PDFs (footer adds the label).
+  static const String defaultSupervisorPhone =
+      PrintSettings.fallbackSupervisorPhone;
 
   /// Asset path for the brand logo rendered on voucher PDFs.
   static const String defaultLogoAssetPath =
       'assets/images/nellon-logo-cropped.png';
 
   Uint8List? _cachedLogoBytes;
 
   /// Loads and caches the brand logo bytes for PDF letterheads.
   Future<Uint8List?> getLogoBytes([
     String assetPath = defaultLogoAssetPath,
diff --git a/lib/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart b/lib/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart
index 6608010..250532c 100644
--- a/lib/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart
+++ b/lib/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart
@@ -1,35 +1,38 @@
 import 'dart:typed_data';
 import 'package:flutter_bloc/flutter_bloc.dart';
 import 'package:pdf/pdf.dart';
 import '../../../../domain/repositories/customer_repository.dart';
+import '../../../../domain/repositories/print_settings_repository.dart';
 import '../../../../domain/repositories/session_repository.dart';
 import '../../../../domain/repositories/salesperson_repository.dart';
 import '../../../../domain/repositories/voucher_pdf_repository.dart';
 import '../../../../domain/models/sales_invoice.dart';
 import '../../../../domain/models/sales_order.dart';
 import '../../../../domain/models/sales_return.dart';
 import '../../../../domain/models/receipt_voucher.dart';
 import '../../../../domain/models/customer.dart';
 import '../../../core/utils/error_mapper.dart';
 import 'voucher_pdf_event.dart';
 import 'voucher_pdf_state.dart';
 
 /// Central BLoC orchestrating document serialization and platform action integrations.
 class VoucherPdfBloc extends Bloc<VoucherPdfEvent, VoucherPdfState> {
   final VoucherPdfRepository pdfService;
+  final PrintSettingsRepository printSettings;
   final CustomerRepository customerRepository;
   final SessionRepository sessionRepository;
   final SalespersonRepository? salespersonRepository;
 
   VoucherPdfBloc({
     required this.pdfService,
+    required this.printSettings,
     required this.customerRepository,
     required this.sessionRepository,
     this.salespersonRepository,
   }) : super(VoucherPdfInitial()) {
     on<GenerateVoucherPdfPreviewRequested>(_onPreviewRequested);
     on<PrintVoucherPdfRequested>(_onPrintRequested);
     on<ShareVoucherPdfRequested>(_onShareRequested);
     on<EmailVoucherPdfRequested>(_onEmailRequested);
     on<WhatsAppVoucherPdfRequested>(_onWhatsAppRequested);
     on<ResetVoucherPdfState>(_onResetState);
@@ -67,20 +70,21 @@ class VoucherPdfBloc extends Bloc<VoucherPdfEvent, VoucherPdfState> {
     }
     final customer = _getCustomer(type, voucher);
     final salesperson = salespersonRepository?.currentSalesperson;
 
     return pdfService.generateVoucherPdf(
       type: type,
       voucher: voucher,
       org: org,
       customer: customer,
       salesperson: salesperson,
+      supervisorPhone: printSettings.supervisorPhone,
       pageFormat: pageFormat,
     );
   }
 
   Future<void> _onPreviewRequested(
     GenerateVoucherPdfPreviewRequested event,
     Emitter<VoucherPdfState> emit,
   ) async {
     emit(VoucherPdfLoading());
     try {
diff --git a/lib/ui/features/voucher_pdf/templates/expense_pdf_template.dart b/lib/ui/features/voucher_pdf/templates/expense_pdf_template.dart
index 498153c..5181432 100644
--- a/lib/ui/features/voucher_pdf/templates/expense_pdf_template.dart
+++ b/lib/ui/features/voucher_pdf/templates/expense_pdf_template.dart
@@ -1,24 +1,25 @@
 import 'package:pdf/pdf.dart';
 import 'package:pdf/widgets.dart' as pw;
 import '../../../../domain/models/expense_entry.dart';
 import '../../../../domain/models/organization.dart';
+import '../../../../domain/models/print_settings.dart';
 import '../../../../domain/models/salesperson.dart';
 import 'shared_pdf_template.dart';
 
 /// PDF template for generating professional Expense Voucher documents.
 class ExpensePdfTemplate {
   static pw.Document generate(
     ExpenseEntry expense,
     Organization org, {
     Salesperson? salesperson,
-    String? supervisorPhone = SharedPdfTemplate.supervisorContact,
+    String? supervisorPhone = PrintSettings.fallbackSupervisorPhone,
     PdfPageFormat pageFormat = PdfPageFormat.a4,
     pw.ImageProvider? logoImage,
   }) {
     final pdf = pw.Document();
     final currencySymbol = org.currencySymbol;
 
     pdf.addPage(
       pw.MultiPage(
         pageFormat: pageFormat,
         margin: const pw.EdgeInsets.all(32),
diff --git a/lib/ui/features/voucher_pdf/templates/invoice_pdf_template.dart b/lib/ui/features/voucher_pdf/templates/invoice_pdf_template.dart
index c5c91e8..7cd3964 100644
--- a/lib/ui/features/voucher_pdf/templates/invoice_pdf_template.dart
+++ b/lib/ui/features/voucher_pdf/templates/invoice_pdf_template.dart
@@ -1,27 +1,28 @@
 import 'package:pdf/pdf.dart';
 import 'package:pdf/widgets.dart' as pw;
+import '../../../../domain/models/print_settings.dart';
 import '../../../../domain/models/sales_invoice.dart';
 import '../../../../domain/models/organization.dart';
 import '../../../../domain/models/customer.dart';
 import '../../../../domain/models/salesperson.dart';
 import '../../../core/utils/quantity_format.dart';
 import 'shared_pdf_template.dart';
 
 /// PDF template for generating professional Sales Invoice documents.
 class InvoicePdfTemplate {
   static pw.Document generate(
     SalesInvoice invoice,
     Organization org,
     Customer? customer, {
     Salesperson? salesperson,
-    String? supervisorPhone = SharedPdfTemplate.supervisorContact,
+    String? supervisorPhone = PrintSettings.fallbackSupervisorPhone,
     PdfPageFormat pageFormat = PdfPageFormat.a4,
     pw.ImageProvider? logoImage,
   }) {
     final pdf = pw.Document();
     final currencySymbol = org.currencySymbol;
 
     pdf.addPage(
       pw.MultiPage(
         pageFormat: pageFormat,
         margin: const pw.EdgeInsets.all(32),
diff --git a/lib/ui/features/voucher_pdf/templates/receipt_pdf_template.dart b/lib/ui/features/voucher_pdf/templates/receipt_pdf_template.dart
index df06a7b..88b01fe 100644
--- a/lib/ui/features/voucher_pdf/templates/receipt_pdf_template.dart
+++ b/lib/ui/features/voucher_pdf/templates/receipt_pdf_template.dart
@@ -1,26 +1,27 @@
 import 'package:pdf/pdf.dart';
 import 'package:pdf/widgets.dart' as pw;
 import '../../../../domain/models/receipt_voucher.dart';
 import '../../../../domain/models/organization.dart';
 import '../../../../domain/models/customer.dart';
+import '../../../../domain/models/print_settings.dart';
 import '../../../../domain/models/salesperson.dart';
 import 'shared_pdf_template.dart';
 
 /// PDF template for generating professional Payment Receipt documents.
 class ReceiptPdfTemplate {
   static pw.Document generate(
     ReceiptVoucher receipt,
     Organization org,
     Customer? customer, {
     Salesperson? salesperson,
-    String? supervisorPhone = SharedPdfTemplate.supervisorContact,
+    String? supervisorPhone = PrintSettings.fallbackSupervisorPhone,
     PdfPageFormat pageFormat = PdfPageFormat.a4,
     pw.ImageProvider? logoImage,
   }) {
     final pdf = pw.Document();
     final currencySymbol = org.currencySymbol;
 
     pdf.addPage(
       pw.MultiPage(
         pageFormat: pageFormat,
         margin: const pw.EdgeInsets.all(32),
diff --git a/lib/ui/features/voucher_pdf/templates/sales_order_pdf_template.dart b/lib/ui/features/voucher_pdf/templates/sales_order_pdf_template.dart
index 480f0ee..478cd1e 100644
--- a/lib/ui/features/voucher_pdf/templates/sales_order_pdf_template.dart
+++ b/lib/ui/features/voucher_pdf/templates/sales_order_pdf_template.dart
@@ -1,27 +1,28 @@
 import 'package:pdf/pdf.dart';
 import 'package:pdf/widgets.dart' as pw;
 import '../../../../domain/models/sales_order.dart';
 import '../../../../domain/models/organization.dart';
 import '../../../../domain/models/customer.dart';
+import '../../../../domain/models/print_settings.dart';
 import '../../../../domain/models/salesperson.dart';
 import '../../../core/utils/quantity_format.dart';
 import 'shared_pdf_template.dart';
 
 /// PDF template for generating professional Sales Order documents.
 class SalesOrderPdfTemplate {
   static pw.Document generate(
     SalesOrder order,
     Organization org,
     Customer? customer, {
     Salesperson? salesperson,
-    String? supervisorPhone = SharedPdfTemplate.supervisorContact,
+    String? supervisorPhone = PrintSettings.fallbackSupervisorPhone,
     PdfPageFormat pageFormat = PdfPageFormat.a4,
     pw.ImageProvider? logoImage,
   }) {
     final pdf = pw.Document();
     final currencySymbol = org.currencySymbol;
 
     pdf.addPage(
       pw.MultiPage(
         pageFormat: pageFormat,
         margin: const pw.EdgeInsets.all(32),
diff --git a/lib/ui/features/voucher_pdf/templates/sales_return_pdf_template.dart b/lib/ui/features/voucher_pdf/templates/sales_return_pdf_template.dart
index f9a635a..a37fe99 100644
--- a/lib/ui/features/voucher_pdf/templates/sales_return_pdf_template.dart
+++ b/lib/ui/features/voucher_pdf/templates/sales_return_pdf_template.dart
@@ -1,27 +1,28 @@
 import 'package:pdf/pdf.dart';
 import 'package:pdf/widgets.dart' as pw;
 import '../../../../domain/models/sales_return.dart';
 import '../../../../domain/models/organization.dart';
 import '../../../../domain/models/customer.dart';
+import '../../../../domain/models/print_settings.dart';
 import '../../../../domain/models/salesperson.dart';
 import '../../../core/utils/quantity_format.dart';
 import 'shared_pdf_template.dart';
 
 /// PDF template for generating professional Sales Return (Credit Note) documents.
 class SalesReturnPdfTemplate {
   static pw.Document generate(
     SalesReturn returnVoucher,
     Organization org,
     Customer? customer, {
     Salesperson? salesperson,
-    String? supervisorPhone = SharedPdfTemplate.supervisorContact,
+    String? supervisorPhone = PrintSettings.fallbackSupervisorPhone,
     PdfPageFormat pageFormat = PdfPageFormat.a4,
     pw.ImageProvider? logoImage,
   }) {
     final pdf = pw.Document();
     final currencySymbol = org.currencySymbol;
 
     pdf.addPage(
       pw.MultiPage(
         pageFormat: pageFormat,
         margin: const pw.EdgeInsets.all(32),
diff --git a/lib/ui/features/voucher_pdf/templates/shared_pdf_template.dart b/lib/ui/features/voucher_pdf/templates/shared_pdf_template.dart
index 4c7026f..81df363 100644
--- a/lib/ui/features/voucher_pdf/templates/shared_pdf_template.dart
+++ b/lib/ui/features/voucher_pdf/templates/shared_pdf_template.dart
@@ -1,15 +1,17 @@
 import 'package:pdf/pdf.dart';
 import 'package:pdf/widgets.dart' as pw;
 import 'package:intl/intl.dart';
 import '../../../../domain/models/organization.dart';
+import '../../../../domain/models/print_settings.dart';
 import '../../../../domain/models/salesperson.dart';
+import '../../../../domain/utils/supervisor_label.dart';
 
 /// A single label/value entry rendered inside [SharedPdfTemplate.buildInfoPanel].
 class PdfInfoEntry {
   final String label;
   final String value;
   final pw.CrossAxisAlignment alignment;
   final PdfColor? valueColor;
 
   const PdfInfoEntry(
     this.label,
@@ -32,22 +34,22 @@ class SharedPdfTemplate {
   static final PdfColor slateTextSecondary = const PdfColor.fromInt(0xFF64748B);
   static final PdfColor borderSlate = const PdfColor.fromInt(0xFFE2E8F0);
   static final PdfColor alertAmber = const PdfColor.fromInt(0xFFF59E0B);
   static final PdfColor successEmerald = const PdfColor.fromInt(0xFF10B981);
   static final PdfColor lightGreyBackground = const PdfColor.fromInt(0xFFF8FAFC);
 
   // Formatting helpers
   static final DateFormat dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
   static final DateFormat dateOnlyFormat = DateFormat('dd MMM yyyy');
 
-  /// Default supervisor contact line for documents.
-  static const String supervisorContact = 'Supervisor : +971 501880810';
+  /// Default supervisor phone for documents (number only; footer adds the label).
+  static const String supervisorContact = PrintSettings.fallbackSupervisorPhone;
 
   /// Common corporate grid header with billing enforcer typography and vibrant accents.
   static pw.Widget buildHeader({
     required Organization org,
     required String voucherTitle,
     required String voucherNumber,
     required DateTime date,
     pw.ImageProvider? logoImage,
   }) {
     return pw.Container(
@@ -539,24 +541,22 @@ class SharedPdfTemplate {
     String? supervisorPhone = supervisorContact,
   }) {
     final salesmanName = salesperson?.name.trim() ?? '';
     final salesmanPhone = salesperson?.phone?.trim() ?? '';
     final hasSalesman = salesmanName.isNotEmpty || salesmanPhone.isNotEmpty;
     final salesmanLabel = hasSalesman
         ? (salesmanPhone.isNotEmpty
             ? '$salesmanName (Salesman) : $salesmanPhone'
             : '$salesmanName (Salesman)')
         : '';
-    final supervisorLabel = (supervisorPhone != null && supervisorPhone.trim().isNotEmpty)
-        ? (supervisorPhone.toLowerCase().startsWith('supervisor')
-            ? supervisorPhone
-            : 'Supervisor : $supervisorPhone')
+    final supervisorLabel = supervisorPhone != null
+        ? formatSupervisorLine(supervisorPhone)
         : '';
 
     return pw.Container(
       margin: const pw.EdgeInsets.only(top: 20),
       child: pw.Column(
         children: [
           pw.Divider(color: borderSlate, thickness: 1),
           pw.SizedBox(height: 6),
           if (hasSalesman || supervisorLabel.isNotEmpty) ...[
             pw.Row(
diff --git a/lib/ui/features/voucher_pdf/templates/stock_transfer_pdf_template.dart b/lib/ui/features/voucher_pdf/templates/stock_transfer_pdf_template.dart
index b4b559b..918a3d7 100644
--- a/lib/ui/features/voucher_pdf/templates/stock_transfer_pdf_template.dart
+++ b/lib/ui/features/voucher_pdf/templates/stock_transfer_pdf_template.dart
@@ -1,26 +1,27 @@
 import 'package:pdf/pdf.dart';
 import 'package:pdf/widgets.dart' as pw;
 
 import '../../../../domain/models/organization.dart';
+import '../../../../domain/models/print_settings.dart';
 import '../../../../domain/models/salesperson.dart';
 import '../../../../domain/models/stock_transfer.dart';
 import '../../../core/utils/quantity_format.dart';
 import 'shared_pdf_template.dart';
 
 /// PDF template for generating professional Stock Transfer (Issue to Van / Stock Unloading) documents.
 class StockTransferPdfTemplate {
   static pw.Document generate(
     StockTransfer transfer,
     Organization org, {
     Salesperson? salesperson,
-    String? supervisorPhone = SharedPdfTemplate.supervisorContact,
+    String? supervisorPhone = PrintSettings.fallbackSupervisorPhone,
     PdfPageFormat pageFormat = PdfPageFormat.a4,
     pw.ImageProvider? logoImage,
   }) {
     final pdf = pw.Document();
     final isLoad = transfer.direction == StockTransferDirection.load;
     final voucherTitle = isLoad ? 'Issue to Van' : 'Stock Unloading';
     final voucherNumber = transfer.transferNumber.isNotEmpty
         ? transfer.transferNumber
         : transfer.id;
 
diff --git a/lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart b/lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart
index b33b6f0..6676925 100644
--- a/lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart
+++ b/lib/ui/features/voucher_pdf/widgets/voucher_pdf_actions_widget.dart
@@ -1,20 +1,21 @@
 import 'package:flutter/material.dart';
 import 'package:flutter/services.dart';
 import 'package:flutter_bloc/flutter_bloc.dart';
 import '../../../../domain/models/customer.dart';
 import '../../../../domain/models/organization.dart';
 import '../../../../domain/models/receipt_voucher.dart';
 import '../../../../domain/models/sales_invoice.dart';
 import '../../../../domain/models/sales_order.dart';
 import '../../../../domain/models/sales_return.dart';
 import '../../../../domain/repositories/customer_repository.dart';
+import '../../../../domain/repositories/print_settings_repository.dart';
 import '../../../../domain/repositories/session_repository.dart';
 import '../../../../domain/repositories/salesperson_repository.dart';
 import '../../../../domain/repositories/voucher_pdf_repository.dart';
 import '../../../core/cubit/salesperson_cubit.dart';
 import '../../../core/extensions/org_context_extension.dart';
 import '../../../core/theme/app_theme.dart';
 import '../../../core/utils/error_mapper.dart';
 import '../../../core/utils/permission_dialogs.dart';
 import '../../../core/utils/snackbars.dart';
 import '../../thermal_print/cubit/thermal_printer_cubit.dart';
@@ -42,20 +43,21 @@ class VoucherPdfActionsWidget extends StatelessWidget {
     required this.type,
     required this.voucher,
     this.compact = false,
   });
 
   @override
   Widget build(BuildContext context) {
     return BlocProvider<VoucherPdfBloc>(
       create: (ctx) => VoucherPdfBloc(
         pdfService: ctx.read<VoucherPdfRepository>(),
+        printSettings: ctx.read<PrintSettingsRepository>(),
         customerRepository: ctx.read<CustomerRepository>(),
         sessionRepository: ctx.read<SessionRepository>(),
         salespersonRepository: ctx.read<SalespersonRepository>(),
       ),
       child: _VoucherPdfActionsBody(
         type: type,
         voucher: voucher,
         compact: compact,
       ),
     );
diff --git a/test/pdf_text_test_utils.dart b/test/pdf_text_test_utils.dart
new file mode 100644
index 0000000..a104f12
--- /dev/null
+++ b/test/pdf_text_test_utils.dart
@@ -0,0 +1,61 @@
+import 'dart:convert';
+import 'dart:io';
+import 'dart:typed_data';
+
+import 'package:flutter_test/flutter_test.dart';
+import 'package:van_sales/domain/utils/supervisor_label.dart';
+
+/// Best-effort extraction of visible text from PDF bytes produced by the `pdf`
+/// package (FlateDecode content streams plus TJ text operators).
+String extractPdfText(Uint8List bytes) {
+  final raw = latin1.decode(bytes, allowInvalid: true);
+  final parts = <String>[raw];
+
+  final objectPattern = RegExp(
+    r'(\d+\s+\d+\s+obj[\s\S]*?)(?=endobj)',
+    multiLine: true,
+  );
+
+  for (final objMatch in objectPattern.allMatches(raw)) {
+    final obj = objMatch.group(1)!;
+    if (!obj.contains('/FlateDecode')) continue;
+
+    final streamMatch =
+        RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream').firstMatch(obj);
+    if (streamMatch == null) continue;
+
+    final streamBytes = Uint8List.fromList(streamMatch.group(1)!.codeUnits);
+    try {
+      final inflated = ZLibCodec().decode(streamBytes);
+      parts.add(utf8.decode(inflated, allowMalformed: true));
+    } catch (_) {
+      // Some streams may use raw deflate; skip on failure.
+    }
+  }
+
+  final combined = parts.join('\n');
+  final tjPattern = RegExp(r'\[\(([^)]*)\)\]TJ');
+  final tjText = tjPattern
+      .allMatches(combined)
+      .map((m) => m.group(1)!)
+      .join();
+
+  return '$combined\n$tjText';
+}
+
+/// Normalizes [extractPdfText] output to a single readable line for assertions.
+String extractPdfVisibleText(Uint8List bytes) {
+  final combined = extractPdfText(bytes);
+  return RegExp(r'\[\(([^)]*)\)\]TJ')
+      .allMatches(combined)
+      .map((m) => m.group(1)!)
+      .join();
+}
+
+/// Compares supervisor footer text when PDF TJ operators omit spaces.
+void expectPdfContainsSupervisorLine(String pdfText, String phone) {
+  final normalizedPdf = pdfText.replaceAll(RegExp(r'\s+'), '');
+  final normalizedLine =
+      formatSupervisorLine(phone).replaceAll(RegExp(r'\s+'), '');
+  expect(normalizedPdf, contains(normalizedLine));
+}
diff --git a/test/voucher_pdf_bloc_test.dart b/test/voucher_pdf_bloc_test.dart
new file mode 100644
index 0000000..71ce494
--- /dev/null
+++ b/test/voucher_pdf_bloc_test.dart
@@ -0,0 +1,182 @@
+import 'dart:typed_data';
+
+import 'package:flutter_test/flutter_test.dart';
+import 'package:pdf/pdf.dart';
+import 'package:van_sales/domain/models/customer.dart';
+import 'package:van_sales/domain/models/item.dart';
+import 'package:van_sales/domain/models/organization.dart';
+import 'package:van_sales/domain/models/print_settings.dart';
+import 'package:van_sales/domain/models/sales_invoice.dart';
+import 'package:van_sales/domain/models/salesperson.dart';
+import 'package:van_sales/domain/repositories/customer_repository.dart';
+import 'package:van_sales/domain/repositories/print_settings_repository.dart';
+import 'package:van_sales/domain/repositories/session_repository.dart';
+import 'package:van_sales/domain/repositories/voucher_pdf_repository.dart';
+import 'package:van_sales/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart';
+import 'package:van_sales/ui/features/voucher_pdf/bloc/voucher_pdf_event.dart';
+import 'package:van_sales/ui/features/voucher_pdf/bloc/voucher_pdf_state.dart';
+
+class FakePrintSettingsRepository implements PrintSettingsRepository {
+  FakePrintSettingsRepository(this._phone);
+
+  final String _phone;
+
+  @override
+  String get supervisorPhone => _phone;
+
+  @override
+  Future<void> hydrate() async {}
+
+  @override
+  Future<PrintSettings> refresh() async =>
+      PrintSettings(supervisorPhone: _phone);
+}
+
+class RecordingVoucherPdfRepository implements VoucherPdfRepository {
+  String? capturedSupervisorPhone;
+
+  @override
+  Future<Uint8List> generateVoucherPdf({
+    required VoucherType type,
+    required dynamic voucher,
+    required Organization org,
+    required Customer? customer,
+    Salesperson? salesperson,
+    String? supervisorPhone,
+    PdfPageFormat pageFormat = PdfPageFormat.a4,
+    Uint8List? logoBytes,
+  }) async {
+    capturedSupervisorPhone = supervisorPhone;
+    return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x2D]);
+  }
+
+  @override
+  String getSafeFilename({required VoucherType type, required dynamic voucher}) =>
+      'test_voucher.pdf';
+
+  @override
+  dynamic noSuchMethod(Invocation invocation) {
+    if (invocation.isGetter) {
+      return '';
+    }
+    return Future<void>.value();
+  }
+}
+
+class FakeSessionRepository implements SessionRepository {
+  FakeSessionRepository(this.org);
+
+  final Organization? org;
+
+  @override
+  Organization? getOrganization() => org;
+
+  @override
+  dynamic noSuchMethod(Invocation invocation) => null;
+}
+
+class FakeCustomerRepository implements CustomerRepository {
+  final Map<String, Customer> customers;
+
+  FakeCustomerRepository(this.customers);
+
+  @override
+  Customer? getCustomerById(String id) => customers[id];
+
+  @override
+  dynamic noSuchMethod(Invocation invocation) {
+    if (invocation.isGetter) return <dynamic>[];
+    return Future<void>.value();
+  }
+}
+
+void main() {
+  const org = Organization(
+    id: 'org1',
+    name: 'Test Van Co LLC',
+    currencyCode: 'AED',
+    currencySymbol: 'AED',
+    fiscalYearStartMonth: '4',
+    timeZone: 'Asia/Dubai',
+    address: '12 Warehouse Rd, Dubai, UAE',
+    phone: '+971 4 123 4567',
+    trn: '100123456700003',
+  );
+
+  const customer = Customer(
+    id: 'c1',
+    name: 'Al Noor Supermarket',
+    companyName: 'Al Noor Trading LLC',
+    email: 'info@alnoor.ae',
+    phone: '+971 50 123 4567',
+    address: 'Shop 4, Deira, Dubai',
+    trn: '100987654300003',
+    outstandingBalance: 500,
+    creditLimit: 5000,
+    routeId: 'r1',
+    sequence: 1,
+  );
+
+  const item = Item(
+    id: 'i1',
+    name: 'Premium Product',
+    sku: 'SKU-001',
+    rate: 100,
+    stock: 200,
+    description: 'Product Description',
+    taxName: 'VAT 5%',
+    taxPercentage: 5,
+    uom: 'pcs',
+  );
+
+  final invoice = SalesInvoice(
+    id: 'inv-bloc-1',
+    invoiceNumber: 'INV-BLOC-001',
+    customerId: customer.id,
+    customerName: customer.name,
+    date: DateTime(2026, 1, 15),
+    dueDate: DateTime(2026, 1, 30),
+    items: const [
+      InvoiceLineItem(
+        item: item,
+        quantity: 1,
+        rate: 100,
+        taxPercentage: 5,
+      ),
+    ],
+    notes: '',
+  );
+
+  group('VoucherPdfBloc - supervisor phone wiring', () {
+    test('passes PrintSettingsRepository supervisor phone to generateVoucherPdf',
+        () async {
+      const firestorePhone = '+971 50 999 0000';
+      final pdfRepo = RecordingVoucherPdfRepository();
+      final printSettings = FakePrintSettingsRepository(firestorePhone);
+      final bloc = VoucherPdfBloc(
+        pdfService: pdfRepo,
+        printSettings: printSettings,
+        customerRepository: FakeCustomerRepository({customer.id: customer}),
+        sessionRepository: FakeSessionRepository(org),
+      );
+
+      bloc.add(
+        GenerateVoucherPdfPreviewRequested(
+          type: VoucherType.salesInvoice,
+          voucher: invoice,
+        ),
+      );
+
+      await expectLater(
+        bloc.stream,
+        emitsInOrder([
+          isA<VoucherPdfLoading>(),
+          isA<VoucherPdfReady>(),
+        ]),
+      );
+
+      expect(pdfRepo.capturedSupervisorPhone, firestorePhone);
+      await bloc.close();
+    });
+  });
+}
diff --git a/test/voucher_pdf_service_test.dart b/test/voucher_pdf_service_test.dart
index a9d1464..55f3b94 100644
--- a/test/voucher_pdf_service_test.dart
+++ b/test/voucher_pdf_service_test.dart
@@ -1,25 +1,28 @@
 import 'dart:typed_data';
 import 'package:flutter_test/flutter_test.dart';
 import 'package:van_sales/data/services/voucher_pdf_service.dart';
 import 'package:van_sales/domain/models/customer.dart';
 import 'package:van_sales/domain/models/expense_entry.dart';
 import 'package:van_sales/domain/models/item.dart';
 import 'package:van_sales/domain/models/organization.dart';
+import 'package:van_sales/domain/models/print_settings.dart';
 import 'package:van_sales/domain/models/receipt_voucher.dart';
 import 'package:van_sales/domain/models/sales_invoice.dart';
 import 'package:van_sales/domain/models/sales_order.dart';
 import 'package:van_sales/domain/models/sales_return.dart';
 import 'package:van_sales/domain/models/salesperson.dart';
 import 'package:van_sales/domain/models/stock_transfer.dart';
 import 'package:van_sales/domain/repositories/voucher_pdf_repository.dart';
+import 'package:van_sales/domain/utils/supervisor_label.dart';
 
+import 'pdf_text_test_utils.dart';
 void main() {
   TestWidgetsFlutterBinding.ensureInitialized();
 
   const org = Organization(
     id: 'org1',
     name: 'Test Van Co LLC',
     currencyCode: 'AED',
     currencySymbol: 'AED',
     fiscalYearStartMonth: '4',
     timeZone: 'Asia/Dubai',
@@ -328,11 +331,83 @@ void main() {
         org: org,
         customer: customer,
         salesperson: salesperson,
         logoBytes: dummyPng,
       );
 
       expect(bytes, isNotEmpty);
       expect(bytes.length, greaterThan(1000));
     });
   });
+
+  group('VoucherPdfService - supervisor footer', () {
+    late VoucherPdfService service;
+
+    setUp(() {
+      service = VoucherPdfService();
+    });
+
+    SalesInvoice _sampleInvoice() => SalesInvoice(
+      id: 'inv-supervisor',
+      invoiceNumber: 'INV-SUP-001',
+      customerId: customer.id,
+      customerName: customer.name,
+      date: DateTime(2026, 1, 15),
+      dueDate: DateTime(2026, 1, 30),
+      items: const [
+        InvoiceLineItem(
+          item: item,
+          quantity: 1,
+          rate: 100,
+          taxPercentage: 5,
+        ),
+      ],
+      notes: '',
+    );
+
+    test('footer uses explicit supervisor phone from Firestore', () async {
+      const firestorePhone = '+971 50 999 0000';
+      final bytes = await service.generateVoucherPdf(
+        type: VoucherType.salesInvoice,
+        voucher: _sampleInvoice(),
+        org: org,
+        customer: customer,
+        salesperson: salesperson,
+        supervisorPhone: firestorePhone,
+      );
+
+      expect(bytes, isNotEmpty);
+      final expectedLine = formatSupervisorLine(firestorePhone);
+      expect(expectedLine, 'Supervisor : $firestorePhone');
+
+      final pdfText = extractPdfVisibleText(bytes);
+      expectPdfContainsSupervisorLine(pdfText, firestorePhone);
+    });
+
+    test('footer falls back to default supervisor phone when not overridden',
+        () async {
+      final bytes = await service.generateVoucherPdf(
+        type: VoucherType.salesInvoice,
+        voucher: _sampleInvoice(),
+        org: org,
+        customer: customer,
+        salesperson: salesperson,
+      );
+
+      expect(bytes, isNotEmpty);
+      expect(
+        VoucherPdfService.defaultSupervisorPhone,
+        PrintSettings.fallbackSupervisorPhone,
+      );
+      final expectedLine = formatSupervisorLine(
+        VoucherPdfService.defaultSupervisorPhone,
+      );
+      expect(expectedLine, 'Supervisor : ${PrintSettings.fallbackSupervisorPhone}');
+
+      final pdfText = extractPdfVisibleText(bytes);
+      expectPdfContainsSupervisorLine(
+        pdfText,
+        VoucherPdfService.defaultSupervisorPhone,
+      );
+    });
+  });
 }
