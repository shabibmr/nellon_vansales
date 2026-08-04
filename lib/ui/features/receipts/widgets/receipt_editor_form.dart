import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/widgets/customer_selector_sheet.dart';
import '../../../core/widgets/editor_footer.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../bloc/receipt_editor_bloc.dart';
import '../bloc/receipt_editor_event.dart';
import '../bloc/receipt_editor_state.dart';
import 'receipt_allocations_section.dart';
import 'receipt_customer_card.dart';
import 'receipt_date_card.dart';

const _paymentModes = ['Cash', 'Cheque', 'Bank Transfer', 'Card'];

/// Main form body for the receipt editor (scroll area + footer).
class ReceiptEditorForm extends StatefulWidget {
  final ReceiptEditorState state;
  final bool readOnly;

  const ReceiptEditorForm({
    super.key,
    required this.state,
    required this.readOnly,
  });

  @override
  State<ReceiptEditorForm> createState() => _ReceiptEditorFormState();
}

class _ReceiptEditorFormState extends State<ReceiptEditorForm> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  late TextEditingController _amountController;
  late TextEditingController _referenceController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.state.editingAmount > 0
          ? widget.state.editingAmount.toStringAsFixed(2)
          : '',
    );
    _referenceController = TextEditingController(
      text: widget.state.editingReferenceNumber,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _selectReceiptDate(
    BuildContext context,
    DateTime currentDate,
  ) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
      color: AppTheme.successEmerald,
    );
    if (picked != null && context.mounted) {
      context.read<ReceiptEditorBloc>().add(SetEditingReceiptDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final allCustomers = _db.getCustomers()
      ..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      onSelected: (customer) {
        context.read<ReceiptEditorBloc>().add(SetEditingReceiptCustomer(customer));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final state = widget.state;
    final readOnly = widget.readOnly;
    final customer = state.editingCustomer;
    final date = state.editingDate ?? DateTime.now();

    final showTrailingPdf = !state.isEditingNew &&
        state.editingId != null &&
        customer != null;

    return Column(
      children: [
        if (state.isSaving)
          const LinearProgressIndicator(color: AppTheme.successEmerald),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  ReceiptCustomerCard(
                    customer: customer,
                    canSelect: !readOnly && state.isEditingNew,
                    onTap: () => _showCustomerSelector(context),
                  ),
                  const SizedBox(height: 12),
                  ReceiptDateCard(
                    label: 'RECEIPT DATE',
                    date: date,
                    icon: Icons.calendar_today,
                    accentColor: AppTheme.successEmerald,
                    onTap: readOnly
                        ? null
                        : () => _selectReceiptDate(context, date),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PAYMENT DETAILS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: AppTheme.successEmerald,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _amountController,
                            readOnly: readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Received Amount ($cs)',
                              hintText: '0.00',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              final parsed = double.tryParse(val) ?? 0.0;
                              context.read<ReceiptEditorBloc>().add(
                                SetEditingAmount(parsed),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _paymentModes.contains(state.editingPaymentMode)
                                ? state.editingPaymentMode
                                : 'Cash',
                            decoration: const InputDecoration(
                              labelText: 'Payment Mode',
                              border: OutlineInputBorder(),
                            ),
                            items: _paymentModes
                                .map(
                                  (mode) => DropdownMenuItem(
                                    value: mode,
                                    child: Text(mode),
                                  ),
                                )
                                .toList(),
                            onChanged: readOnly
                                ? null
                                : (mode) {
                                    if (mode != null) {
                                      context.read<ReceiptEditorBloc>().add(
                                        SetEditingPaymentMode(mode),
                                      );
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _referenceController,
                            readOnly: readOnly,
                            decoration: const InputDecoration(
                              labelText: 'Reference Number / Cheque No.',
                              hintText: 'Optional reference',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              context.read<ReceiptEditorBloc>().add(
                                SetEditingReference(val),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ReceiptAllocationsSection(
                    allocations: state.editingAllocations,
                    currencySymbol: cs,
                    readOnly: readOnly,
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
        EditorFooter(
          rows: [
            (
              label: 'Total Amount Received:',
              value: formatCurrency(state.editingAmount, cs),
              emphasize: true,
            ),
          ],
          buttonLabel: readOnly ? 'CLOSE' : 'SAVE RECEIPT',
          buttonColor: AppTheme.successEmerald,
          onSave: readOnly
              ? () => Navigator.pop(context)
              : (customer == null ||
                    state.editingAmount <= 0 ||
                    state.isSaving)
              ? null
              : () {
                  context.read<ReceiptEditorBloc>().add(const SaveReceipt());
                },
          trailing: showTrailingPdf && state.editingReceipt != null
              ? VoucherPdfActionsWidget(
                  type: VoucherType.paymentReceipt,
                  voucher: state.editingReceipt!,
                )
              : null,
        ),
      ],
    );
  }
}
