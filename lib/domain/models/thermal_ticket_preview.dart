import 'package:equatable/equatable.dart';

import 'thermal_paper_size.dart';

/// One visible line of a thermal ticket, matching ESC/POS layout and styles.
class ThermalPreviewLine extends Equatable {
  final String text;
  final bool bold;
  final bool center;
  final bool underline;
  final bool reverse;
  final int widthMultiplier;
  final int heightMultiplier;

  const ThermalPreviewLine({
    required this.text,
    this.bold = false,
    this.center = false,
    this.underline = false,
    this.reverse = false,
    this.widthMultiplier = 1,
    this.heightMultiplier = 1,
  });

  @override
  List<Object?> get props => [
    text,
    bold,
    center,
    underline,
    reverse,
    widthMultiplier,
    heightMultiplier,
  ];
}

/// On-screen stand-in for the bytes that would be sent to the thermal printer.
class ThermalTicketPreview extends Equatable {
  final ThermalPaperSize paperSize;
  final List<ThermalPreviewLine> lines;

  const ThermalTicketPreview({required this.paperSize, required this.lines});

  /// Newline-joined ticket body (styles stripped) for tests and search.
  String get plainText => lines.map((line) => line.text).join('\n');

  @override
  List<Object?> get props => [paperSize, lines];
}
