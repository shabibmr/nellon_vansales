import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

/// Screen presenting the user with an interactive, scrollable A4 PDF print preview.
class VoucherPdfPreviewPage extends StatelessWidget {
  final Uint8List pdfBytes;
  final String filename;

  const VoucherPdfPreviewPage({
    super.key,
    required this.pdfBytes,
    required this.filename,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          filename,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: PdfPreview(
        build: (format) => pdfBytes,
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        initialPageFormat: PdfPageFormat.a4,
        loadingWidget: const Center(
          child: CircularProgressIndicator(color: Colors.indigo),
        ),
        pdfPreviewPageDecoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black45 : Colors.black12,
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
      ),
    );
  }
}
