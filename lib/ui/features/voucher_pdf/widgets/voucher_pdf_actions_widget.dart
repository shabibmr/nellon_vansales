import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/permission_dialogs.dart';
import '../../../core/utils/snackbars.dart';
import '../../thermal_print/cubit/thermal_printer_cubit.dart';
import '../../thermal_print/cubit/thermal_printer_state.dart';
import '../bloc/voucher_pdf_bloc.dart';
import '../bloc/voucher_pdf_event.dart';
import '../bloc/voucher_pdf_state.dart';
import '../views/voucher_pdf_preview_page.dart';

/// Interactive visual row containing trigger buttons for all PDF capabilities.
///
/// Features loading overlays and platform snackbar notifications. Provides its
/// own [VoucherPdfBloc] instance scoped to this widget, so PDF state from one
/// voucher screen can never leak onto another after navigation.
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
    return BlocProvider<VoucherPdfBloc>(
      create: (_) => VoucherPdfBloc(
        pdfService: sl<VoucherPdfRepository>(),
        dbService: sl<HiveDatabaseService>(),
      ),
      child: _VoucherPdfActionsBody(type: type, voucher: voucher),
    );
  }
}

class _VoucherPdfActionsBody extends StatelessWidget {
  final VoucherType type;
  final dynamic voucher;

  const _VoucherPdfActionsBody({required this.type, required this.voucher});

  String? _customerIdFor(VoucherType type, dynamic voucher) {
    return switch (type) {
      VoucherType.salesInvoice => (voucher as SalesInvoice).customerId,
      VoucherType.salesOrder => (voucher as SalesOrder).customerId,
      VoucherType.salesReturn => (voucher as SalesReturn).customerId,
      VoucherType.paymentReceipt => (voucher as ReceiptVoucher).customerId,
      VoucherType.expenseVoucher => null,
    };
  }

  void _printThermal(BuildContext context) {
    final db = sl<HiveDatabaseService>();
    final org = db.getOrganization();
    if (org == null) {
      showErrorSnackBar(
        context,
        'Organization data not loaded — please sync first',
      );
      return;
    }
    final customerId = _customerIdFor(type, voucher);
    final customer =
        customerId != null ? db.getCustomerById(customerId) : null;
    final salesperson = db.getCurrentSalesperson()?.name;

    context.read<ThermalPrinterCubit>().printVoucher(
          type: type,
          voucher: voucher,
          org: org,
          customer: customer,
          salespersonName: salesperson,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final snackShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    return MultiBlocListener(
      listeners: [
        BlocListener<VoucherPdfBloc, VoucherPdfState>(
          listener: (context, state) {
            if (state is VoucherPdfReady) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoucherPdfPreviewPage(
                    pdfBytes: state.pdfBytes,
                    filename: state.filename,
                  ),
                ),
              );
              context.read<VoucherPdfBloc>().add(ResetVoucherPdfState());
            } else if (state is VoucherPdfActionSuccess) {
              showSuccessSnackBar(
                context,
                state.message,
                behavior: SnackBarBehavior.floating,
                shape: snackShape,
              );
              context.read<VoucherPdfBloc>().add(ResetVoucherPdfState());
            } else if (state is VoucherPdfFailure) {
              showErrorSnackBar(
                context,
                state.error,
                behavior: SnackBarBehavior.floating,
                shape: snackShape,
              );
              context.read<VoucherPdfBloc>().add(ResetVoucherPdfState());
            }
          },
        ),
        BlocListener<ThermalPrinterCubit, ThermalPrinterState>(
          listenWhen: (prev, curr) =>
              prev.statusMessage != curr.statusMessage ||
              prev.errorMessage != curr.errorMessage ||
              prev.needsAppSettings != curr.needsAppSettings,
          listener: (context, state) {
            if (state.needsAppSettings) {
              showBluetoothPermissionSettingsDialog(context);
              context.read<ThermalPrinterCubit>().clearNeedsAppSettings();
              if (state.errorMessage != null) {
                showErrorSnackBar(
                  context,
                  state.errorMessage!,
                  behavior: SnackBarBehavior.floating,
                  shape: snackShape,
                );
                context.read<ThermalPrinterCubit>().clearMessages();
              }
              return;
            }
            if (state.errorMessage != null) {
              showErrorSnackBar(
                context,
                state.errorMessage!,
                behavior: SnackBarBehavior.floating,
                shape: snackShape,
              );
              context.read<ThermalPrinterCubit>().clearMessages();
            } else if (state.statusMessage != null) {
              showSuccessSnackBar(
                context,
                state.statusMessage!,
                behavior: SnackBarBehavior.floating,
                shape: snackShape,
              );
              context.read<ThermalPrinterCubit>().clearMessages();
            }
          },
        ),
      ],
      child: BlocBuilder<VoucherPdfBloc, VoucherPdfState>(
        builder: (context, state) {
          return BlocBuilder<ThermalPrinterCubit, ThermalPrinterState>(
            builder: (context, thermalState) {
              final isLoading =
                  state is VoucherPdfLoading || thermalState.isPrinting;

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
                            'Document Actions',
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
                        const LinearProgressIndicator(
                          color: AppTheme.primaryIndigo,
                        ),
                        const SizedBox(height: 12),
                      ],
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
                            icon: Icons.bluetooth,
                            label: 'Thermal',
                            color: AppTheme.primaryDarkIndigo,
                            isDisabled: isLoading,
                            onPressed: () => _printThermal(context),
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
        },
      ),
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
