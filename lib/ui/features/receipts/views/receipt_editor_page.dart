import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/customer_selector_sheet.dart';
import '../bloc/receipt_bloc.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../../../../data/services/voucher_pdf_service.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/open_invoice.dart';

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
  final FocusNode _amountFocusNode = FocusNode();
  final FocusNode _referenceFocusNode = FocusNode();
  final Map<String, TextEditingController> _allocationControllers = {};
  final Map<String, FocusNode> _allocationFocusNodes = {};
  String? _lastCustomerId;

  @override
  void initState() {
    super.initState();
    final state = context.read<ReceiptBloc>().state;
    _amountController = TextEditingController(
      text: state.editingAmount > 0
          ? state.editingAmount.toStringAsFixed(2)
          : '',
    );
    _referenceController = TextEditingController(
      text: state.editingReferenceNumber,
    );
    _lastCustomerId = state.editingCustomer?.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _amountFocusNode.dispose();
    _referenceFocusNode.dispose();
    for (final ctrl in _allocationControllers.values) {
      ctrl.dispose();
    }
    for (final node in _allocationFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  bool _areAllocationsValid(ReceiptState state) {
    if (state.editingCustomer == null) return false;
    final openInvoices = _db.getOpenInvoices(
      customerId: state.editingCustomer!.id,
    );
    double totalAllocated = 0.0;
    for (final alloc in state.editingAllocations) {
      if (alloc.amountApplied < 0) return false;
      final inv = openInvoices.firstWhere(
        (i) => i.invoiceId == alloc.invoiceId,
        orElse: () => OpenInvoice(
          invoiceId: '',
          invoiceNumber: '',
          customerId: '',
          date: DateTime.now(),
          dueDate: DateTime.now(),
          total: 0.0,
          balance: 0.0,
          status: '',
        ),
      );
      if (inv.invoiceId.isEmpty || alloc.amountApplied > inv.balance)
        return false;
      totalAllocated += alloc.amountApplied;
    }
    if (double.parse(totalAllocated.toStringAsFixed(2)) >
        double.parse(state.editingAmount.toStringAsFixed(2))) {
      return false;
    }
    return true;
  }

  void _onAllocationChanged(
    String invoiceId,
    String invoiceNumber,
    String value,
    List<PaymentAllocation> currentAllocations,
  ) {
    final parsed = double.tryParse(value) ?? 0.0;
    final list = List<PaymentAllocation>.from(currentAllocations);
    final index = list.indexWhere((a) => a.invoiceId == invoiceId);

    if (index >= 0) {
      if (parsed <= 0) {
        list.removeAt(index);
      } else {
        list[index] = PaymentAllocation(
          invoiceId: invoiceId,
          invoiceNumber: invoiceNumber,
          amountApplied: parsed,
        );
      }
    } else if (parsed > 0) {
      list.add(
        PaymentAllocation(
          invoiceId: invoiceId,
          invoiceNumber: invoiceNumber,
          amountApplied: parsed,
        ),
      );
    }

    context.read<ReceiptBloc>().add(UpdateReceiptAllocations(list));
  }

  Future<void> _selectDate(DateTime current) async {
    final picked = await showThemedDatePicker(context, initialDate: current);
    if (picked != null && mounted) {
      context.read<ReceiptBloc>().add(SetEditingReceiptDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context, bool isDark) {
    final allCustomers = _db.getCustomers()
      ..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      onSelected: (customer) {
        context.read<ReceiptBloc>().add(SetEditingReceiptCustomer(customer));
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
        listener: (context, state) {
          if (state.successMessage != null) {
            showSuccessSnackBar(context, state.successMessage!);
            context.read<ReceiptBloc>().add(ClearReceiptMessages());
            Navigator.pop(context);
          } else if (state.errorMessage != null) {
            showErrorSnackBar(context, state.errorMessage!);
            context.read<ReceiptBloc>().add(ClearReceiptMessages());
          }

          // Clear allocations controllers if customer changed
          if (state.editingCustomer?.id != _lastCustomerId) {
            _lastCustomerId = state.editingCustomer?.id;
            for (final ctrl in _allocationControllers.values) {
              ctrl.dispose();
            }
            _allocationControllers.clear();
            for (final node in _allocationFocusNodes.values) {
              node.dispose();
            }
            _allocationFocusNodes.clear();
          }

          // Sync amount controller
          final amountText = state.editingAmount > 0
              ? state.editingAmount.toStringAsFixed(2)
              : '';
          if (_amountController.text != amountText &&
              !_amountFocusNode.hasFocus) {
            _amountController.text = amountText;
          }

          // Sync reference controller
          if (_referenceController.text != state.editingReferenceNumber &&
              !_referenceFocusNode.hasFocus) {
            _referenceController.text = state.editingReferenceNumber;
          }

          // Sync allocations controllers
          if (state.editingCustomer != null) {
            final openInvoices = _db.getOpenInvoices(
              customerId: state.editingCustomer!.id,
            );
            for (final inv in openInvoices) {
              final alloc = state.editingAllocations.firstWhere(
                (a) => a.invoiceId == inv.invoiceId,
                orElse: () => PaymentAllocation(
                  invoiceId: inv.invoiceId,
                  invoiceNumber: inv.invoiceNumber,
                  amountApplied: 0.0,
                ),
              );
              final ctrl = _allocationControllers[inv.invoiceId];
              final hasFocus =
                  _allocationFocusNodes[inv.invoiceId]?.hasFocus ?? false;
              final expectedText = alloc.amountApplied > 0
                  ? alloc.amountApplied.toStringAsFixed(2)
                  : '';
              if (ctrl != null) {
                if (ctrl.text != expectedText && !hasFocus) {
                  ctrl.text = expectedText;
                }
              } else {
                _allocationControllers[inv.invoiceId] = TextEditingController(
                  text: expectedText,
                );
              }
            }
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
                                    backgroundColor: AppTheme.primaryIndigo
                                        .withValues(alpha: 0.1),
                                    child: const Icon(
                                      Icons.person,
                                      color: AppTheme.primaryIndigo,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            fontWeight: FontWeight.bold,
                                          ),
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
                        const SizedBox(height: 20),

                        // Amount field
                        TextFormField(
                          controller: _amountController,
                          focusNode: _amountFocusNode,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (v) {
                            final amount = double.tryParse(v) ?? 0.0;
                            context.read<ReceiptBloc>().add(
                              SetEditingAmount(amount),
                            );
                          },
                          decoration: InputDecoration(
                            labelText: 'Payment Amount ($cs)',
                            prefixIcon: const Icon(
                              Icons.currency_rupee,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Payment mode
                        DropdownButtonFormField<String>(
                          initialValue: state.editingPaymentMode,
                          decoration: const InputDecoration(
                            labelText: 'Payment Mode',
                            prefixIcon: Icon(
                              Icons.payment_outlined,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                          items: ['Cash', 'Cheque', 'Bank Transfer', 'Card']
                              .map(
                                (m) =>
                                    DropdownMenuItem(value: m, child: Text(m)),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              context.read<ReceiptBloc>().add(
                                SetEditingPaymentMode(v),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Reference number
                        TextFormField(
                          controller: _referenceController,
                          focusNode: _referenceFocusNode,
                          onChanged: (v) => context.read<ReceiptBloc>().add(
                            SetEditingReference(v),
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Reference Number (optional)',
                            hintText: 'Cheque no., transaction ID...',
                            prefixIcon: Icon(
                              Icons.tag,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Allocations list
                        if (customer != null) ...[
                          Builder(
                            builder: (context) {
                              final openInvoices = _db.getOpenInvoices(
                                customerId: customer.id,
                              );
                              if (openInvoices.isEmpty)
                                return const SizedBox.shrink();

                              final totalAllocated = state.editingAllocations
                                  .fold(0.0, (sum, a) => sum + a.amountApplied);
                              final excessAmount =
                                  state.editingAmount - totalAllocated;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'INVOICE ALLOCATIONS',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? AppTheme.darkTextSecondary
                                              : AppTheme.lightTextSecondary,
                                        ),
                                      ),
                                      Text(
                                        'Allocated: $cs${totalAllocated.toStringAsFixed(2)} / $cs${state.editingAmount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              totalAllocated >
                                                  state.editingAmount + 0.005
                                              ? AppTheme.errorRose
                                              : AppTheme.successEmerald,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (excessAmount > 0.005) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Remaining $cs${excessAmount.toStringAsFixed(2)} will be saved as customer credit/excess payment.',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: AppTheme.infoSky,
                                      ),
                                    ),
                                  ],
                                  if (totalAllocated >
                                      state.editingAmount + 0.005) ...[
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Warning: Total allocated exceeds payment amount!',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.errorRose,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: openInvoices.length,
                                    itemBuilder: (context, index) {
                                      final inv = openInvoices[index];
                                      final ctrl = _allocationControllers
                                          .putIfAbsent(
                                            inv.invoiceId,
                                            () => TextEditingController(
                                              text:
                                                  state.editingAllocations
                                                          .firstWhere(
                                                            (a) =>
                                                                a.invoiceId ==
                                                                inv.invoiceId,
                                                            orElse: () =>
                                                                const PaymentAllocation(
                                                                  invoiceId: '',
                                                                  invoiceNumber:
                                                                      '',
                                                                  amountApplied:
                                                                      0.0,
                                                                ),
                                                          )
                                                          .amountApplied >
                                                      0
                                                  ? state.editingAllocations
                                                        .firstWhere(
                                                          (a) =>
                                                              a.invoiceId ==
                                                              inv.invoiceId,
                                                        )
                                                        .amountApplied
                                                        .toStringAsFixed(2)
                                                  : '',
                                            ),
                                          );
                                      final focusNode = _allocationFocusNodes
                                          .putIfAbsent(
                                            inv.invoiceId,
                                            () => FocusNode(),
                                          );

                                      final allocation = state
                                          .editingAllocations
                                          .firstWhere(
                                            (a) => a.invoiceId == inv.invoiceId,
                                            orElse: () => PaymentAllocation(
                                              invoiceId: inv.invoiceId,
                                              invoiceNumber: inv.invoiceNumber,
                                              amountApplied: 0.0,
                                            ),
                                          );

                                      return Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      inv.invoiceNumber,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Date: ${_dateFormat.format(inv.date)}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: isDark
                                                            ? AppTheme
                                                                  .darkTextSecondary
                                                            : AppTheme
                                                                  .lightTextSecondary,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Outstanding: $cs${inv.balance.toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              SizedBox(
                                                width: 120,
                                                child: TextFormField(
                                                  controller: ctrl,
                                                  focusNode: focusNode,
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  textAlign: TextAlign.end,
                                                  decoration: InputDecoration(
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 8,
                                                        ),
                                                    prefixText: cs,
                                                    hintText: '0.00',
                                                    errorText:
                                                        allocation
                                                                .amountApplied >
                                                            inv.balance
                                                        ? 'Exceeds balance'
                                                        : null,
                                                  ),
                                                  onChanged: (v) {
                                                    _onAllocationChanged(
                                                      inv.invoiceId,
                                                      inv.invoiceNumber,
                                                      v,
                                                      state.editingAllocations,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              );
                            },
                          ),
                        ],
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
                                color: AppTheme.successEmerald,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                (customer == null ||
                                    state.editingAmount <= 0 ||
                                    state.isLoading ||
                                    !_areAllocationsValid(state))
                                ? null
                                : () => context.read<ReceiptBloc>().add(
                                    SaveReceipt(),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successEmerald,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'SAVE RECEIPT',
                              style: TextStyle(color: Colors.white),
                            ),
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
