import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../bloc/receipt_bloc.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../../../../data/services/voucher_pdf_service.dart';
import '../../../../domain/models/receipt_voucher.dart';

class ReceiptEditorPage extends StatefulWidget {
  const ReceiptEditorPage({super.key});

  @override
  State<ReceiptEditorPage> createState() => _ReceiptEditorPageState();
}

class _ReceiptEditorPageState extends State<ReceiptEditorPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  late TextEditingController _amountController;
  late TextEditingController _referenceController;

  @override
  void initState() {
    super.initState();
    final state = context.read<ReceiptBloc>().state;
    _amountController = TextEditingController(
      text: state.editingAmount > 0 ? state.editingAmount.toStringAsFixed(2) : '',
    );
    _referenceController =
        TextEditingController(text: state.editingReferenceNumber);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

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
      context.read<ReceiptBloc>().add(SetEditingReceiptDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context, bool isDark) {
    final cs = context.org.currencySymbol;
    final allCustomers = _db.getCustomers()..sort((a, b) => a.name.compareTo(b.name));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        var filtered = allCustomers;
        final searchCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (sheetCtx, setModal) {
            void onSearch(String query) {
              final q = query.toLowerCase();
              setModal(() {
                filtered = q.isEmpty
                    ? allCustomers
                    : allCustomers.where((c) {
                        return c.name.toLowerCase().contains(q) ||
                            c.companyName.toLowerCase().contains(q) ||
                            c.phone.contains(query);
                      }).toList();
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollCtrl) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Customer',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        onChanged: onSearch,
                        decoration: InputDecoration(
                          hintText: 'Search by name, company or phone...',
                          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryIndigo),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text('No customers found',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  )))
                          : ListView.separated(
                              controller: scrollCtrl,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final customer = filtered[i];
                                return ListTile(
                                  title: Text(customer.name,
                                      style:
                                          const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(customer.companyName),
                                  trailing: customer.outstandingBalance > 0
                                      ? Text(
                                          'Outstanding: $cs${customer.outstandingBalance.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              color: AppTheme.errorRose,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                  onTap: () {
                                    context
                                        .read<ReceiptBloc>()
                                        .add(SetEditingReceiptCustomer(customer));
                                    Navigator.pop(sheetCtx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
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
        title: BlocBuilder<ReceiptBloc, ReceiptState>(
          buildWhen: (p, c) => p.isEditingNew != c.isEditingNew,
          builder: (_, state) =>
              Text(state.isEditingNew ? 'New Receipt' : 'Edit Receipt'),
        ),
      ),
      body: BlocConsumer<ReceiptBloc, ReceiptState>(
        listenWhen: (p, c) =>
            p.successMessage != c.successMessage || p.errorMessage != c.errorMessage,
        listener: (context, state) {
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  backgroundColor: AppTheme.successEmerald,
                  content: Text(state.successMessage!)),
            );
            context.read<ReceiptBloc>().add(ClearReceiptMessages());
            Navigator.pop(context);
          } else if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  backgroundColor: AppTheme.errorRose,
                  content: Text(state.errorMessage!)),
            );
            context.read<ReceiptBloc>().add(ClearReceiptMessages());
          }
        },
        builder: (context, state) {
          final date = state.editingDate ?? DateTime.now();
          final customer = state.editingCustomer;
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
                        // Customer selector
                        Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: state.isEditingNew
                                ? () => _showCustomerSelector(context, isDark)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        AppTheme.primaryIndigo.withValues(alpha: 0.1),
                                    child: const Icon(Icons.person,
                                        color: AppTheme.primaryIndigo),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CUSTOMER',
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
                                          customer?.name ?? 'Select Customer',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        if (customer != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            customer.companyName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? AppTheme.darkTextSecondary
                                                  : AppTheme.lightTextSecondary,
                                            ),
                                          ),
                                          if (customer.outstandingBalance > 0)
                                            Text(
                                              'Outstanding: $cs${customer.outstandingBalance.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.errorRose,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (state.isEditingNew)
                                    Icon(Icons.keyboard_arrow_right,
                                        color: isDark
                                            ? AppTheme.darkTextSecondary
                                            : AppTheme.lightTextSecondary),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

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
                                    backgroundColor:
                                        AppTheme.infoSky.withValues(alpha: 0.1),
                                    child: const Icon(Icons.calendar_today,
                                        color: AppTheme.infoSky),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'RECEIPT DATE',
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
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold)),
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
                        const SizedBox(height: 20),

                        // Amount field
                        TextFormField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) {
                            final amount = double.tryParse(v) ?? 0.0;
                            context.read<ReceiptBloc>().add(SetEditingAmount(amount));
                          },
                          decoration: InputDecoration(
                            labelText: 'Payment Amount ($cs)',
                            prefixIcon: const Icon(Icons.currency_rupee, color: AppTheme.primaryIndigo),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Payment mode
                        DropdownButtonFormField<String>(
                          initialValue: state.editingPaymentMode,
                          decoration: const InputDecoration(
                            labelText: 'Payment Mode',
                            prefixIcon: Icon(Icons.payment_outlined,
                                color: AppTheme.primaryIndigo),
                          ),
                          items: ['Cash', 'Cheque', 'Bank Transfer', 'Card']
                              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              context
                                  .read<ReceiptBloc>()
                                  .add(SetEditingPaymentMode(v));
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Reference number
                        TextFormField(
                          controller: _referenceController,
                          onChanged: (v) =>
                              context.read<ReceiptBloc>().add(SetEditingReference(v)),
                          decoration: const InputDecoration(
                            labelText: 'Reference Number (optional)',
                            hintText: 'Cheque no., transaction ID...',
                            prefixIcon: Icon(Icons.tag, color: AppTheme.primaryIndigo),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom save button
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
                            : const Color(0xFFE2E8F0)),
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
                            const Text('Amount:',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 16)),
                            Text(
                              '$cs${state.editingAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: AppTheme.successEmerald,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (customer == null ||
                                    state.editingAmount <= 0 ||
                                    state.isLoading)
                                ? null
                                : () =>
                                    context.read<ReceiptBloc>().add(SaveReceipt()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successEmerald,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('SAVE RECEIPT',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        if (!state.isEditingNew) ...[
                          const SizedBox(height: 16),
                          VoucherPdfActionsWidget(
                            type: VoucherType.paymentReceipt,
                            voucher: ReceiptVoucher(
                              id: state.editingId ?? '',
                              paymentNumber: state.receipts
                                  .firstWhere(
                                    (rec) => rec.id == state.editingId,
                                    orElse: () => ReceiptVoucher(
                                      id: '',
                                      paymentNumber: 'RCPT-TEMP',
                                      customerId: '',
                                      customerName: '',
                                      allocations: const [],
                                      amount: 0,
                                      paymentMode: 'Cash',
                                      referenceNumber: '',
                                      date: DateTime.now(),
                                    ),
                                  )
                                  .paymentNumber,
                              customerId: customer?.id ?? '',
                              customerName: customer?.name ?? '',
                              allocations: state.receipts
                                  .firstWhere(
                                    (rec) => rec.id == state.editingId,
                                    orElse: () => ReceiptVoucher(
                                      id: '',
                                      paymentNumber: 'RCPT-TEMP',
                                      customerId: '',
                                      customerName: '',
                                      allocations: const [],
                                      amount: 0,
                                      paymentMode: 'Cash',
                                      referenceNumber: '',
                                      date: DateTime.now(),
                                    ),
                                  )
                                  .allocations,
                              amount: state.editingAmount,
                              paymentMode: state.editingPaymentMode,
                              referenceNumber: state.editingReferenceNumber,
                              date: date,
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
