import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../cubit/sales_return_dialog_cubit.dart';
import '../cubit/sales_return_dialog_state.dart';

/// Modal dialog for logging a sales return credit note.
///
/// Prompts selection of a returned item from the active warehouse product catalog
/// and inputting the returned quantity. Prepares a sales return payload, updates
/// client credit balance or stock in local cache, and enqueues a sync job to post to Zoho.
class SalesReturnDialog extends StatelessWidget {
  /// The selected customer profile returning inventory.
  final Customer customer;

  /// Callback triggered when the sales return transaction is successfully processed and cached.
  final VoidCallback onReturnConfirmed;

  /// Creates a new [SalesReturnDialog] widget.
  const SalesReturnDialog({
    super.key,
    required this.customer,
    required this.onReturnConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SalesReturnDialogCubit(
        customer: customer,
        salesRepository: sl<SalesRepository>(),
        syncWorker: sl<SyncWorker>(),
      )..loadEligibleItems(),
      child: _SalesReturnDialogView(onReturnConfirmed: onReturnConfirmed),
    );
  }
}

class _SalesReturnDialogView extends StatefulWidget {
  final VoidCallback onReturnConfirmed;

  const _SalesReturnDialogView({required this.onReturnConfirmed});

  @override
  State<_SalesReturnDialogView> createState() => _SalesReturnDialogViewState();
}

class _SalesReturnDialogViewState extends State<_SalesReturnDialogView> {
  final _formKey = GlobalKey<FormState>();
  final _dateFormat = DateFormat('dd MMM yyyy');
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void dispose() {
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _reconcileControllers(List<SalesInvoice> invoices) {
    final ids = invoices.map((inv) => inv.id).toSet();

    for (final id in _qtyControllers.keys.toList()) {
      if (!ids.contains(id)) {
        _qtyControllers[id]!.dispose();
        _qtyControllers.remove(id);
      }
    }

    for (final inv in invoices) {
      _qtyControllers.putIfAbsent(inv.id, () => TextEditingController());
    }
  }

  void _onConfirmPressed(SalesReturnDialogState state) {
    if (!_formKey.currentState!.validate()) return;
    context.read<SalesReturnDialogCubit>().submit();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<SalesReturnDialogCubit, SalesReturnDialogState>(
      listenWhen: (prev, curr) =>
          prev.matchingInvoices != curr.matchingInvoices ||
          prev.success != curr.success ||
          prev.errorMessage != curr.errorMessage,
      listener: (context, state) {
        if (state.success && state.selectedItem != null) {
          Navigator.pop(context);
          showSuccessSnackBar(
            context,
            'Sales Return credit queued. ${state.selectedItem!.name} stock restored!',
          );
          widget.onReturnConfirmed();
          return;
        }

        if (state.errorMessage != null) {
          showErrorSnackBar(context, state.errorMessage!);
          context.read<SalesReturnDialogCubit>().clearError();
          return;
        }

        _reconcileControllers(state.matchingInvoices);
      },
      builder: (context, state) {
        return AlertDialog(
          title: const Text('New Sales Return'),
          content: SizedBox(
            width: 450,
            child: state.hasNoPurchaseHistory
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.errorRose,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'This customer has no purchase history. Returns are only allowed for items sold in previous sales invoices.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Select returned item and allocate quantity from invoices.',
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<Item>(
                            key: ValueKey(state.selectedItem?.id ?? 'none'),
                            initialValue: state.selectedItem,
                            decoration: const InputDecoration(
                              labelText: 'Returned Item',
                            ),
                            items: state.eligibleItems
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(item.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (item) {
                              if (item != null) {
                                context
                                    .read<SalesReturnDialogCubit>()
                                    .selectItem(item);
                              }
                            },
                          ),
                          if (state.selectedItem != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Select Invoices & Quantities',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...state.matchingInvoices.map((inv) {
                              final originalLine = inv.items.firstWhere(
                                (line) =>
                                    line.item.id == state.selectedItem!.id,
                              );
                              final maxQty = originalLine.quantity;
                              final controller = _qtyControllers.putIfAbsent(
                                inv.id,
                                () => TextEditingController(),
                              );

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF8FAFC),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0,
                                    vertical: 10.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              inv.invoiceNumber,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: AppTheme.warningAmber,
                                              ),
                                            ),
                                            Text(
                                              'Date: ${_dateFormat.format(inv.date)}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? AppTheme
                                                        .darkTextSecondary
                                                    : AppTheme
                                                        .lightTextSecondary,
                                              ),
                                            ),
                                            Text(
                                              'Sold: $maxQty units',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 80,
                                        child: TextFormField(
                                          controller: controller,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          onChanged: (value) {
                                            final qty =
                                                int.tryParse(value) ?? 0;
                                            context
                                                .read<SalesReturnDialogCubit>()
                                                .setQuantity(inv.id, qty);
                                          },
                                          decoration: InputDecoration(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            hintText: '0',
                                            isDense: true,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          textAlign: TextAlign.center,
                                          validator: (val) {
                                            if (val == null || val.isEmpty) {
                                              return null;
                                            }
                                            final qty = int.tryParse(val);
                                            if (qty == null) return 'Invalid';
                                            if (qty < 0) return 'Min 0';
                                            if (qty > maxQty) {
                                              return 'Max $maxQty';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: state.hasNoPurchaseHistory ||
                      state.selectedItem == null ||
                      !state.canSubmit
                  ? null
                  : () => _onConfirmPressed(state),
              child: state.submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('CONFIRM RETURN'),
            ),
          ],
        );
      },
    );
  }
}