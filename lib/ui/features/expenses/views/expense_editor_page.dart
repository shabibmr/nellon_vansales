import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../bloc/expense_bloc.dart';

class ExpenseEditorPage extends StatefulWidget {
  const ExpenseEditorPage({super.key});

  @override
  State<ExpenseEditorPage> createState() => _ExpenseEditorPageState();
}

class _ExpenseEditorPageState extends State<ExpenseEditorPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  final ImagePicker _picker = ImagePicker();

  Future<void> _selectDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.primaryIndigo,
                    onPrimary: Colors.white,
                    surface: AppTheme.darkSurface,
                    onSurface: AppTheme.darkText,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppTheme.primaryIndigo,
                    onPrimary: Colors.white,
                    surface: AppTheme.lightSurface,
                    onSurface: AppTheme.lightText,
                  ),
                ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      context.read<ExpenseBloc>().add(SetEditingExpenseDate(picked));
    }
  }

  void _showImageSourceSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
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
              const Text('Attach Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primaryIndigo),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 75);
                  if (image != null && mounted) {
                    final bytes = await image.readAsBytes();
                    if (mounted) {
                      context.read<ExpenseBloc>().add(SetReceiptImage(path: image.path, bytes: bytes));
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primaryIndigo),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
                  if (image != null && mounted) {
                    final bytes = await image.readAsBytes();
                    if (mounted) {
                      context.read<ExpenseBloc>().add(SetReceiptImage(path: image.path, bytes: bytes));
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

  void _showAddLineDialog(BuildContext context, bool isDark, {int? editIndex, ExpenseLineItem? existing}) {
    final amountCtrl = TextEditingController(text: existing?.amount.toStringAsFixed(2) ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    String category = existing?.category ?? 'Fuel';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              title: Text(editIndex == null ? 'Add Expense Line' : 'Edit Expense Line'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                        prefixIcon: Icon(Icons.currency_rupee, color: AppTheme.primaryIndigo),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: ['Fuel', 'Tolls', 'Meals', 'Maintenance', 'Miscellaneous']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setDlgState(() => category = v ?? 'Fuel'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Description / Remarks'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: () {
                    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                    if (amount <= 0) return;
                    final line = ExpenseLineItem(
                      category: category,
                      amount: amount,
                      description: descCtrl.text.trim(),
                    );
                    if (editIndex == null) {
                      context.read<ExpenseBloc>().add(AddExpenseLine(line));
                    } else {
                      context.read<ExpenseBloc>().add(UpdateExpenseLine(editIndex, line));
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
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
            p.successMessage != c.successMessage || p.errorMessage != c.errorMessage,
        listener: (context, state) {
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  backgroundColor: AppTheme.successEmerald,
                  content: Text(state.successMessage!)),
            );
            context.read<ExpenseBloc>().add(ClearExpenseMessages());
            Navigator.pop(context);
          } else if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  backgroundColor: AppTheme.errorRose,
                  content: Text(state.errorMessage!)),
            );
            context.read<ExpenseBloc>().add(ClearExpenseMessages());
          }
        },
        builder: (context, state) {
          final date = state.editingDate ?? DateTime.now();

          return Column(
            children: [
              if (state.isLoading) const LinearProgressIndicator(color: AppTheme.primaryIndigo),
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
                                    backgroundColor: AppTheme.infoSky.withValues(alpha: 0.1),
                                    child: const Icon(Icons.calendar_today, color: AppTheme.infoSky),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                        Text(_dateFormat.format(date),
                                            style: const TextStyle(
                                                fontSize: 16, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.keyboard_arrow_right,
                                      color: isDark
                                          ? AppTheme.darkTextSecondary
                                          : AppTheme.lightTextSecondary),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Expense lines header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Expense Lines',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            TextButton.icon(
                              onPressed: () => _showAddLineDialog(context, isDark),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Line'),
                              style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.primaryIndigo),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (state.editingLines.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0)),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.add_circle_outline,
                                      size: 36,
                                      color: isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFCBD5E1)),
                                  const SizedBox(height: 8),
                                  Text('No expense lines yet',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? AppTheme.darkTextSecondary
                                            : AppTheme.lightTextSecondary,
                                      )),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: state.editingLines.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final line = state.editingLines[i];
                              return Card(
                                child: ListTile(
                                  onTap: () => _showAddLineDialog(context, isDark,
                                      editIndex: i, existing: line),
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        AppTheme.errorRose.withValues(alpha: 0.1),
                                    child: const Icon(Icons.receipt_outlined,
                                        color: AppTheme.errorRose, size: 18),
                                  ),
                                  title: Text(line.category,
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: line.description.isNotEmpty
                                      ? Text(line.description,
                                          style: const TextStyle(fontSize: 12))
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '₹${line.amount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.errorRose,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: AppTheme.errorRose, size: 20),
                                        onPressed: () => context
                                            .read<ExpenseBloc>()
                                            .add(RemoveExpenseLine(i)),
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.only(left: 8),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 20),

                        // Receipt image
                        const Text('Receipt Photo',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        _ReceiptImageCard(
                          isDark: isDark,
                          imagePath: state.editingReceiptImagePath,
                          imageBytes: state.editingReceiptImageBytes,
                          onAttach: () => _showImageSourceSheet(isDark),
                          onRemove: () =>
                              context.read<ExpenseBloc>().add(const SetReceiptImage()),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom total + save
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                  border: Border(
                      top: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0))),
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
                            const Text('Total Amount:',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            Text(
                              '₹${state.editingTotal.toStringAsFixed(2)}',
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
                                (state.editingLines.isEmpty || state.isLoading)
                                    ? null
                                    : () => context
                                        .read<ExpenseBloc>()
                                        .add(SaveExpense()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.errorRose,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('SAVE EXPENSE',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ),
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
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  children: [
                    const Icon(Icons.camera_alt_rounded,
                        color: AppTheme.primaryIndigo, size: 32),
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
                      ? Image.memory(imageBytes!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover)
                      : Container(
                          height: 80,
                          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                          child: const Center(
                            child: Icon(Icons.image_outlined,
                                color: AppTheme.primaryIndigo),
                          ),
                        ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                      onPressed: onRemove,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
