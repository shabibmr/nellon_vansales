import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../domain/repositories/expense_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/error_mapper.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/utils/currency.dart';
import '../cubit/expense_log_cubit.dart';
import '../cubit/expense_log_state.dart';

/// Modal dialog that logs a route trip expense log locally.
///
/// Permits choosing standard categories (Fuel, Tolls, Maintenance, Parking fee),
/// inputting cost and remarks, and capturing/attaching receipts via the device camera/gallery.
class ExpenseLogDialog extends StatefulWidget {
  /// Visual context.
  final bool isDark;

  /// Callback triggered when the expense record is successfully committed and cached.
  final VoidCallback onExpenseLogged;

  /// Creates a new [ExpenseLogDialog].
  const ExpenseLogDialog({
    super.key,
    required this.isDark,
    required this.onExpenseLogged,
  });

  /// Presents the dialog provided with [ExpenseLogCubit].
  static Future<void> show(
    BuildContext context, {
    required bool isDark,
    required VoidCallback onExpenseLogged,
  }) {
    final expenseRepo = context.read<ExpenseRepository>();
    final syncRepo = context.read<SyncRepository>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<ExpenseLogCubit>(
        create: (_) => ExpenseLogCubit(
          expenseRepository: expenseRepo,
          syncRepository: syncRepo,
        ),
        child: ExpenseLogDialog(
          isDark: isDark,
          onExpenseLogged: onExpenseLogged,
        ),
      ),
    );
  }

  @override
  State<ExpenseLogDialog> createState() => _ExpenseLogDialogState();
}

class _ExpenseLogDialogState extends State<ExpenseLogDialog> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  String _category = 'Fuel';
  String? _localImagePath;
  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImageSource(StateSetter setDialogState) async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: widget.isDark
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
                  color: widget.isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Receipt Source',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.primaryIndigo,
                ),
                title: const Text('Take Photo with Camera'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final XFile? image = await _picker.pickImage(
                      source: ImageSource.camera,
                      imageQuality: 75,
                    );
                    if (!mounted) return;
                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      setDialogState(() {
                        _localImagePath = image.path;
                        _imageBytes = bytes;
                      });
                    }
                  } catch (e) {
                    if (!mounted) return;
                    showErrorSnackBar(
                      context,
                      'Camera access error: ${userFacingMessage(e)}',
                    );
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
                  try {
                    final XFile? image = await _picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 75,
                    );
                    if (!mounted) return;
                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      setDialogState(() {
                        _localImagePath = image.path;
                        _imageBytes = bytes;
                      });
                    }
                  } catch (e) {
                    if (!mounted) return;
                    showErrorSnackBar(
                      context,
                      'Gallery access error: ${userFacingMessage(e)}',
                    );
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
    return BlocListener<ExpenseLogCubit, ExpenseLogState>(
      listener: (context, state) {
        if (state is ExpenseLogSuccess) {
          Navigator.pop(context);
          final amount = state.expense.lines.isNotEmpty
              ? state.expense.lines.first.amount
              : 0.0;
          showSuccessSnackBar(
            context,
            'Van expense for ${formatCurrency(amount, cs)} queued offline!',
          );
          widget.onExpenseLogged();
        } else if (state is ExpenseLogFailure) {
          showErrorSnackBar(context, state.message);
        }
      },
      child: BlocBuilder<ExpenseLogCubit, ExpenseLogState>(
        builder: (context, state) {
          final isSubmitting = state is ExpenseLogSubmitting;

          return AlertDialog(
            title: const Text('Log Van Expense'),
            content: StatefulBuilder(
              builder: (context, setDialogState) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Expense Amount ($cs)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration:
                            const InputDecoration(labelText: 'Category'),
                        items: ['Fuel', 'Tolls', 'Maintenance', 'Parking fee']
                            .map(
                              (cat) => DropdownMenuItem(
                                value: cat,
                                child: Text(cat),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            _category = val ?? 'Fuel';
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descController,
                        decoration: const InputDecoration(
                          labelText: 'Description / Remarks',
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Visual image attachment card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? AppTheme.darkBackground
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1),
                            width: 1,
                          ),
                        ),
                        child: _localImagePath == null
                            ? InkWell(
                                onTap: () => _pickImageSource(setDialogState),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
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
                                          color: widget.isDark
                                              ? AppTheme.darkText
                                              : AppTheme.lightText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Capture via camera or select from gallery',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: widget.isDark
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
                                    _imageBytes != null
                                        ? Image.memory(
                                            _imageBytes!,
                                            height: 140,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(),
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
                                        onPressed: () {
                                          setDialogState(() {
                                            _localImagePath = null;
                                            _imageBytes = null;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () {
                        final amount =
                            double.tryParse(_amountController.text.trim()) ??
                                0.0;
                        final desc = _descController.text.trim();
                        if (amount <= 0) return;

                        context.read<ExpenseLogCubit>().submitExpense(
                              amount: amount,
                              category: _category,
                              description: desc,
                              receiptImagePath: _localImagePath,
                            );
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('SUBMIT CLAIM'),
              ),
            ],
          );
        },
      ),
    );
  }
}
