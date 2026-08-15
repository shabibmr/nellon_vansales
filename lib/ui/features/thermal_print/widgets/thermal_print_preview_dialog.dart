import 'package:flutter/material.dart';

import '../../../../domain/models/thermal_paper_size.dart';
import '../../../../domain/models/thermal_ticket_preview.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialog_scaffolding.dart';

/// Pop-up that renders a [ThermalTicketPreview] as a thermal-paper receipt.
class ThermalPrintPreviewDialog extends StatelessWidget {
  final ThermalTicketPreview preview;
  final VoidCallback? onPrint;

  const ThermalPrintPreviewDialog({
    super.key,
    required this.preview,
    this.onPrint,
  });

  static Future<void> show(
    BuildContext context, {
    required ThermalTicketPreview preview,
    VoidCallback? onPrint,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) =>
          ThermalPrintPreviewDialog(preview: preview, onPrint: onPrint),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogHeader(
                title: 'Thermal preview',
                onClose: () => Navigator.of(context).pop(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Expected output on ${preview.paperSize.label} paper',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(child: _ThermalReceiptPaper(preview: preview)),
              const SizedBox(height: 12),
              DialogActionButtons(
                cancelLabel: 'Close',
                submitLabel: 'Print',
                onCancel: () => Navigator.of(context).pop(),
                onSubmit: onPrint == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        onPrint!();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThermalReceiptPaper extends StatelessWidget {
  final ThermalTicketPreview preview;

  const _ThermalReceiptPaper({required this.preview});

  @override
  Widget build(BuildContext context) {
    const paperColor = Color(0xFFF7F1DE);
    const inkColor = Color(0xFF1A1A1A);
    final isFourInch = preview.paperSize == ThermalPaperSize.inch4;
    final paperWidth = isFourInch ? 340.0 : 210.0;
    final columns = preview.paperSize.columns;
    final fontSize = paperWidth / columns * 1.62;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            child: Center(
              child: Container(
                width: paperWidth + 20,
                decoration: const BoxDecoration(
                  color: Color(0xFFF7F1DE),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      height: 10,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _SerratedEdgePainter(paperColor),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final line in preview.lines)
                            _PreviewLineView(
                              line: line,
                              fontSize: fontSize,
                              paperWidth: paperWidth,
                              inkColor: inkColor,
                              paperColor: paperColor,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _SerratedEdgePainter(paperColor, flip: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewLineView extends StatelessWidget {
  final ThermalPreviewLine line;
  final double fontSize;
  final double paperWidth;
  final Color inkColor;
  final Color paperColor;

  const _PreviewLineView({
    required this.line,
    required this.fontSize,
    required this.paperWidth,
    required this.inkColor,
    required this.paperColor,
  });

  @override
  Widget build(BuildContext context) {
    final height = fontSize * line.heightMultiplier * 1.12;
    if (line.text.isEmpty) {
      return SizedBox(height: height);
    }

    final style = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const [
        'Courier New',
        'Courier',
        'Roboto Mono',
        'Droid Sans Mono',
      ],
      fontSize: fontSize * line.heightMultiplier,
      height: 1.12,
      fontWeight: line.bold ? FontWeight.w700 : FontWeight.w500,
      decoration: line.underline
          ? TextDecoration.underline
          : TextDecoration.none,
      color: line.reverse ? paperColor : inkColor,
      backgroundColor: line.reverse ? inkColor : null,
      letterSpacing: 0,
    );

    Widget text = Text(
      line.text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      textAlign: line.center ? TextAlign.center : TextAlign.left,
      style: style,
    );

    if (line.widthMultiplier > 1) {
      text = Transform.scale(
        scaleX: line.widthMultiplier.toDouble(),
        alignment: line.center ? Alignment.center : Alignment.centerLeft,
        child: text,
      );
    }

    return SizedBox(
      height: height,
      width: paperWidth,
      child: line.center ? Center(child: text) : text,
    );
  }
}

class _SerratedEdgePainter extends CustomPainter {
  final Color color;
  final bool flip;

  const _SerratedEdgePainter(this.color, {this.flip = false});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    const teeth = 18;
    final tooth = size.width / teeth;
    if (flip) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      for (var i = teeth; i >= 0; i--) {
        final x = i * tooth;
        final y = i.isEven ? 0.0 : size.height;
        path.lineTo(x, y);
      }
      path.close();
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
      for (var i = teeth; i >= 0; i--) {
        final x = i * tooth;
        final y = i.isEven ? size.height : 0.0;
        path.lineTo(x, y);
      }
      path.close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SerratedEdgePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.flip != flip;
  }
}
