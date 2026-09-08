import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/supervisor_label.dart';

/// Best-effort extraction of visible text from PDF bytes produced by the `pdf`
/// package (FlateDecode content streams plus TJ text operators).
String extractPdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final parts = <String>[raw];

  final objectPattern = RegExp(
    r'(\d+\s+\d+\s+obj[\s\S]*?)(?=endobj)',
    multiLine: true,
  );

  for (final objMatch in objectPattern.allMatches(raw)) {
    final obj = objMatch.group(1)!;
    if (!obj.contains('/FlateDecode')) continue;

    final streamMatch =
        RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream').firstMatch(obj);
    if (streamMatch == null) continue;

    final streamBytes = Uint8List.fromList(streamMatch.group(1)!.codeUnits);
    try {
      final inflated = ZLibCodec().decode(streamBytes);
      parts.add(utf8.decode(inflated, allowMalformed: true));
    } catch (_) {
      // Some streams may use raw deflate; skip on failure.
    }
  }

  final combined = parts.join('\n');
  final tjPattern = RegExp(r'\[\(([^)]*)\)\]TJ');
  final tjText = tjPattern
      .allMatches(combined)
      .map((m) => m.group(1)!)
      .join();

  return '$combined\n$tjText';
}

/// Normalizes [extractPdfText] output to a single readable line for assertions.
String extractPdfVisibleText(Uint8List bytes) {
  final combined = extractPdfText(bytes);
  return RegExp(r'\[\(([^)]*)\)\]TJ')
      .allMatches(combined)
      .map((m) => m.group(1)!)
      .join();
}

/// Compares supervisor footer text when PDF TJ operators omit spaces.
void expectPdfContainsSupervisorLine(String pdfText, String phone) {
  final normalizedPdf = pdfText.replaceAll(RegExp(r'\s+'), '');
  final normalizedLine =
      formatSupervisorLine(phone).replaceAll(RegExp(r'\s+'), '');
  expect(normalizedPdf, contains(normalizedLine));
}
