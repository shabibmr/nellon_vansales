import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../bloc/expense_bloc.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../../../../data/services/voucher_pdf_service.dart';
import '../../../../domain/models/expense_entry.dart';

class ExpenseEditorPage extends StatefulWidget {
  const ExpenseEditorPage({super.key});

  @override
  State<ExpenseEditorPage> createState() => _ExpenseEditorPageState();
}

class _ExpenseEditorPageState extends State<ExpenseEditorPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;

  static const _categories = [
    'Fuel',
    'Tolls',
    'Meals',
    'Maintenance',
    'Miscellaneous',
  ];

  @override
  void initState() {
    super.initState();
    final s = context.read<ExpenseBloc>().state;
    _amountController = TextEditingController(
      text: s.editingAmount > 0 ? s.editingAmount.toStringAsFixed(2) : '',
    );
    _descriptionController = TextEditingController(text: s.editingDescription);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(DateTime current) async {
    final picked = await showThemedDatePicker(context, initialDate: current);
    if (picked != null && mounted) {
      context.read<ExpenseBloc>().add(SetEditingExpenseDate(picked));
    }
  }

  void _showImageSourceSheet(bool isDark) {
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
                  if (image != null && mounted) {
                    final bytes = await image.readAsBytes();
                    if (mounted) {
                      context.read<ExpenseBloc>().add(
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
                  if (image != null && mounted) {
                    final bytes = await image.readAsBytes();
                    if (mounted) {
                      context.read<ExpenseBloc>().add(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ExpenseBloc, ExpenseState>(
          buildWhen: (p, c) => p.isEditingNew != c.isEditingNew,
          builder: (_, state) =>
              Text(state.isEditingNew ? 'New Expense' : 'Edit Expense'),
        ),
      ),
      body: BlocConsumer<ExpenseBloc, ExpenseState>(
        listenWhen: (p, c) =>
            p.successMessage != c.successMessage ||
            p.errorMessage != c.errorMessage,
        listener: (context, state) {
          if (state.successMessage != null) {
            showSuccessSnackBar(context, state.successMessage!);
            context.read<ExpenseBloc>().add(ClearExpenseMessages());
            Navigator.pop(context);
          } else if (state.errorMessage != null) {
            showErrorSnackBar(context, state.errorMessage!);
            context.read<ExpenseBloc>().add(ClearExpenseMessages());
          }
        },
        builder: (context, state) {
          final date = state.editingDate ?? DateTime.now();
          final cs = context.org.currencySymbol;

          return Column(
            children: [
              if (state.isLoading)
                const LinearProgressIndicator(color: AppTheme.primaryIndigo),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Date picker
                        Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _selectDate(date),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.infoSky
                                        .withValues(alpha: 0.1),
                                    child: const Icon(
                                      Icons.calendar_today,
                                      color: AppTheme.infoSky,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'EXPENSE DATE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? AppTheme.darkTextSecondary
                                                : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _dateFormat.format(date),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_right,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Amount
                        TextFormField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (v) {
                            final amount = double.tryParse(v) ?? 0.0;
                            context.read<ExpenseBloc>().add(
                              SetEditingExpenseAmount(amount),
                            );
                          },
                          decoration: InputDecoration(
                            labelText: 'Amount ($cs)',
                            prefixIcon: const Icon(
                              Icons.currency_rupee,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Category
                        DropdownButtonFormField<String>(
                          initialValue: state.editingCategory,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(
                              Icons.category_outlined,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                          items: _categories
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              context.read<ExpenseBloc>().add(
                                SetEditingExpenseCategory(v),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Description
                        TextFormField(
                          controller: _descriptionController,
                          onChanged: (v) => context.read<ExpenseBloc>().add(
                            SetEditingExpenseDescription(v),
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Description / Remarks (optional)',
                            prefixIcon: Icon(
                              Icons.notes_outlined,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Receipt image
                        const Text(
                          'Receipt Photo',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ReceiptImageCard(
                          isDark: isDark,
                          imagePath: state.editingReceiptImagePath,
                          imageBytes: state.editingReceiptImageBytes,
                          onAttach: () => _showImageSourceSheet(isDark),
                          onRemove: () => context.read<ExpenseBloc>().add(
                            const SetReceiptImage(),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom amount + save
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Amount:',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '$cs${state.editingAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: AppTheme.errorRose,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                (state.editingAmount <= 0 || state.isLoading)
                                ? null
                                : () => context.read<ExpenseBloc>().add(
                                    SaveExpense(),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.errorRose,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'SAVE EXPENSE',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        if (!state.isEditingNew) ...[
                          const SizedBox(height: 16),
                          VoucherPdfActionsWidget(
                            type: VoucherType.expenseVoucher,
                            voucher: ExpenseEntry(
                              id: state.editingId ?? '',
                              date: state.editingDate ?? DateTime.now(),
                              lines: [
                                ExpenseLineItem(
                                  category: state.editingCategory,
                                  amount: state.editingAmount,
                                  description: state.editingDescription,
                                ),
                              ],
                              receiptImagePath: state.editingReceiptImagePath,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReceiptImageCard extends StatelessWidget {
  final bool isDark;
  final String? imagePath;
  final Uint8List? imageBytes;
  final VoidCallback onAttach;
  final VoidCallback onRemove;

  const _ReceiptImageCard({
    required this.isDark,
    required this.imagePath,
    required this.imageBytes,
    required this.onAttach,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: imagePath == null
          ? InkWell(
              onTap: onAttach,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.camera_alt_rounded,
                      color: AppTheme.primaryIndigo,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ATTACH RECEIPT PHOTO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Capture via camera or select from gallery',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  imageBytes != null
                      ? Image.memory(
                          imageBytes!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          height: 80,
                          color: isDark
                              ? AppTheme.darkSurface
                              : AppTheme.lightSurface,
                          child: const Center(
                            child: Icon(
                              Icons.image_outlined,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                        ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: onRemove,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
