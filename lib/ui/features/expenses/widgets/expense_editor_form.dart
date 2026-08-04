import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/widgets/editor_footer.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../bloc/expense_editor_bloc.dart';
import '../bloc/expense_editor_event.dart';
import '../bloc/expense_editor_state.dart';
import 'expense_date_card.dart';

const _categories = [
  'Fuel',
  'Tolls',
  'Maintenance',
  'Parking fee',
];

/// Main form body for the van expense editor (scroll area + footer).
class ExpenseEditorForm extends StatefulWidget {
  final ExpenseEditorState state;
  final bool readOnly;

  const ExpenseEditorForm({
    super.key,
    required this.state,
    required this.readOnly,
  });

  @override
  State<ExpenseEditorForm> createState() => _ExpenseEditorFormState();
}

class _ExpenseEditorFormState extends State<ExpenseEditorForm> {
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.state.editingAmount > 0
          ? widget.state.editingAmount.toStringAsFixed(2)
          : '',
    );
    _descriptionController = TextEditingController(
      text: widget.state.editingDescription,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectExpenseDate(
    BuildContext context,
    DateTime currentDate,
  ) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
      color: AppTheme.errorRose,
    );
    if (picked != null && context.mounted) {
      context.read<ExpenseEditorBloc>().add(SetEditingExpenseDate(picked));
    }
  }

  void _showImageSourceSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Attach Receipt',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.primaryIndigo,
                ),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final image = await _picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 75,
                  );
                  if (image != null && context.mounted) {
                    final bytes = await image.readAsBytes();
                    if (context.mounted) {
                      context.read<ExpenseEditorBloc>().add(
                        SetReceiptImage(path: image.path, bytes: bytes),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppTheme.primaryIndigo,
                ),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final image = await _picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 75,
                  );
                  if (image != null && context.mounted) {
                    final bytes = await image.readAsBytes();
                    if (context.mounted) {
                      context.read<ExpenseEditorBloc>().add(
                        SetReceiptImage(path: image.path, bytes: bytes),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = widget.state;
    final readOnly = widget.readOnly;
    final date = state.editingDate ?? DateTime.now();

    final showTrailingPdf = !state.isEditingNew && state.editingId != null;

    return Column(
      children: [
        if (state.isSaving)
          const LinearProgressIndicator(color: AppTheme.errorRose),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  ExpenseDateCard(
                    label: 'EXPENSE DATE',
                    date: date,
                    icon: Icons.calendar_today,
                    accentColor: AppTheme.errorRose,
                    onTap: readOnly
                        ? null
                        : () => _selectExpenseDate(context, date),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'EXPENSE DETAILS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: AppTheme.errorRose,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _categories.contains(state.editingCategory)
                                ? state.editingCategory
                                : _categories.first,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            items: _categories
                                .map(
                                  (cat) => DropdownMenuItem(
                                    value: cat,
                                    child: Text(cat),
                                  ),
                                )
                                .toList(),
                            onChanged: readOnly
                                ? null
                                : (cat) {
                                    if (cat != null) {
                                      context.read<ExpenseEditorBloc>().add(
                                        SetEditingExpenseCategory(cat),
                                      );
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _amountController,
                            readOnly: readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Amount ($cs)',
                              hintText: '0.00',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              final parsed = double.tryParse(val) ?? 0.0;
                              context.read<ExpenseEditorBloc>().add(
                                SetEditingExpenseAmount(parsed),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionController,
                            readOnly: readOnly,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Description / Notes',
                              hintText: 'Describe this expense...',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              context.read<ExpenseEditorBloc>().add(
                                SetEditingExpenseDescription(val),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ATTACH RECEIPT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: AppTheme.errorRose,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (state.editingReceiptImagePath != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.attachment_rounded,
                                  color: AppTheme.errorRose,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    state.editingReceiptImagePath!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!readOnly)
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => context
                                        .read<ExpenseEditorBloc>()
                                        .add(const SetReceiptImage(path: null)),
                                  ),
                              ],
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: readOnly
                                  ? null
                                  : () => _showImageSourceSheet(context, isDark),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('ATTACH RECEIPT IMAGE'),
                            ),
                        ],
                      ),
                    ),
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
              label: 'Total Expense:',
              value: formatCurrency(state.editingAmount, cs),
              emphasize: true,
            ),
          ],
          buttonLabel: readOnly ? 'CLOSE' : 'SAVE EXPENSE',
          buttonColor: AppTheme.errorRose,
          onSave: readOnly
              ? () => Navigator.pop(context)
              : (state.editingAmount <= 0 || state.isSaving)
              ? null
              : () {
                  context.read<ExpenseEditorBloc>().add(const SaveExpense());
                },
          trailing: showTrailingPdf && state.editingExpense != null
              ? VoucherPdfActionsWidget(
                  type: VoucherType.expenseVoucher,
                  voucher: state.editingExpense!,
                )
              : null,
        ),
      ],
    );
  }
}
