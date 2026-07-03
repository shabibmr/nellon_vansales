import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../data/services/voucher_pdf_service.dart';
import '../bloc/voucher_pdf_bloc.dart';
import '../bloc/voucher_pdf_event.dart';
import '../bloc/voucher_pdf_state.dart';
import '../views/voucher_pdf_preview_page.dart';

/// Interactive visual row containing trigger buttons for all PDF capabilities.
///
/// Features loading overlays and platform snackbar notifications.
class VoucherPdfActionsWidget extends StatelessWidget {
  final VoucherType type;
  final dynamic voucher;

  const VoucherPdfActionsWidget({
    super.key,
    required this.type,
    required this.voucher,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<VoucherPdfBloc, VoucherPdfState>(
      listener: (context, state) {
        if (state is VoucherPdfReady) {
          // Route into the beautiful interactive A4 Print Preview
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VoucherPdfPreviewPage(
                pdfBytes: state.pdfBytes,
                filename: state.filename,
              ),
            ),
          );
          // Instantly clear/reset the bloc state so popping back doesn't trigger loop
          context.read<VoucherPdfBloc>().add(ResetVoucherPdfState());
        } else if (state is VoucherPdfActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.successEmerald,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              content: Text(state.message),
            ),
          );
          context.read<VoucherPdfBloc>().add(ResetVoucherPdfState());
        } else if (state is VoucherPdfFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.errorRose,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              content: Text(state.error),
            ),
          );
          context.read<VoucherPdfBloc>().add(ResetVoucherPdfState());
        }
      },
      builder: (context, state) {
        final isLoading = state is VoucherPdfLoading;

        return Card(
          margin: const EdgeInsets.all(16.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'PDF Document Actions',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                    if (isLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryIndigo,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isLoading) ...[
                  const LinearProgressIndicator(color: AppTheme.primaryIndigo),
                  const SizedBox(height: 12),
                ],
                // Responsive Grid/Row Layout
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildActionButton(
                      context: context,
                      icon: Icons.visibility,
                      label: 'Preview',
                      color: AppTheme.primaryIndigo,
                      isDisabled: isLoading,
                      onPressed: () {
                        context.read<VoucherPdfBloc>().add(
                          GenerateVoucherPdfPreviewRequested(
                            type: type,
                            voucher: voucher,
                          ),
                        );
                      },
                    ),
                    _buildActionButton(
                      context: context,
                      icon: Icons.print,
                      label: 'Print',
                      color: AppTheme.infoSky,
                      isDisabled: isLoading,
                      onPressed: () {
                        context.read<VoucherPdfBloc>().add(
                          PrintVoucherPdfRequested(
                            type: type,
                            voucher: voucher,
                          ),
                        );
                      },
                    ),
                    _buildActionButton(
                      context: context,
                      icon: Icons.share,
                      label: 'Share',
                      color: isDark ? Colors.white70 : Colors.black87,
                      isDisabled: isLoading,
                      onPressed: () {
                        context.read<VoucherPdfBloc>().add(
                          ShareVoucherPdfRequested(
                            type: type,
                            voucher: voucher,
                          ),
                        );
                      },
                    ),
                    _buildActionButton(
                      context: context,
                      icon: Icons.email,
                      label: 'Email',
                      color: AppTheme.warningAmber,
                      isDisabled: isLoading,
                      onPressed: () {
                        context.read<VoucherPdfBloc>().add(
                          EmailVoucherPdfRequested(
                            type: type,
                            voucher: voucher,
                          ),
                        );
                      },
                    ),
                    _buildActionButton(
                      context: context,
                      icon: Icons.chat_bubble,
                      label: 'WhatsApp',
                      color: AppTheme.successEmerald,
                      isDisabled: isLoading,
                      onPressed: () {
                        context.read<VoucherPdfBloc>().add(
                          WhatsAppVoucherPdfRequested(
                            type: type,
                            voucher: voucher,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required bool isDisabled,
    required VoidCallback onPressed,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.1),
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      child: ElevatedButton.icon(
        onPressed: isDisabled ? null : onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}
