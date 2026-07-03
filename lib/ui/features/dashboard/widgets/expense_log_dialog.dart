import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../../data/models/expense_entry_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/utils/currency.dart';

/// Modal dialog that logs a route trip expense log locally.
///
/// Permits choosing standard categories (Fuel, Tolls, Meals, Maintenance, Miscellaneous),
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
  final HiveDatabaseService _db = sl<HiveDatabaseService>();

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImageSource(StateSetter setDialogState) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
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
                leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primaryIndigo),
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
                    showErrorSnackBar(context, 'Camera Access Error: $e');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primaryIndigo),
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
                    showErrorSnackBar(context, 'Gallery Access Error: $e');
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
                  decoration: InputDecoration(labelText: 'Expense Amount ($cs)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ['Fuel', 'Tolls', 'Meals', 'Maintenance', 'Miscellaneous']
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
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
                  decoration: const InputDecoration(labelText: 'Description / Remarks'),
                ),
                const SizedBox(height: 16),
                // Visual image attachment card
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: widget.isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      width: 1,
                    ),
                  ),
                  child: _localImagePath == null
                      ? InkWell(
                          onTap: () => _pickImageSource(setDialogState),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
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
                                    color: widget.isDark ? AppTheme.darkText : AppTheme.lightText,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Capture via camera or select from gallery',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: widget.isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
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
                                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () async {
            final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
            final desc = _descController.text.trim();
            if (amount <= 0) return;

            final tempId = 'temp_exp_${DateTime.now().millisecondsSinceEpoch}';
            final expense = ExpenseEntry(
              id: tempId,
              date: DateTime.now(),
              lines: [
                ExpenseLineItem(
                  category: _category,
                  amount: amount,
                  description: desc,
                ),
              ],
              receiptImagePath: _localImagePath,
              isPendingSync: true,
            );

            // Save local
            await _db.saveLocalExpense(expense);

            // Enqueue sync
            final syncItem = SyncQueueItem(
              id: tempId,
              type: 'expense',
              payload: ExpenseEntryModel.fromDomain(expense).toJson(),
              status: SyncStatus.pending,
              timestamp: DateTime.now(),
            );
            await _db.enqueueSyncItem(syncItem);

            if (!context.mounted) return;

            sl<SyncWorker>().syncPendingItems();

            Navigator.pop(context);
            showSuccessSnackBar(context, 'Van expense for ${formatCurrency(amount, cs)} queued offline!');
            widget.onExpenseLogged();
          },
          child: const Text('SUBMIT CLAIM'),
        ),
      ],
    );
  }
}
