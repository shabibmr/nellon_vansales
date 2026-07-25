import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/customer_selector_sheet.dart';
import '../bloc/receipt_bloc.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/open_invoice.dart';

const _paymentModes = ['Cash', 'Cheque', 'Bank Transfer', 'Card'];

class ReceiptEditorPage extends StatefulWidget {
  /// When true, the receipt is shown read-only (view mode). Receipts cannot
  /// be edited after creation — only sales orders support edit.
  final bool readOnly;

  const ReceiptEditorPage({super.key, this.readOnly = false});

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

  /// When true, allocation field [onChanged] must not dispatch bloc events
  /// (FIFO auto-allocate syncs controllers without re-entering the bloc).
  bool _syncingControllers = false;

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

  List<OpenInvoice> _safeOpenInvoices(String customerId) {
    try {
      return _db.getOpenInvoices(customerId: customerId);
    } catch (_) {
      return const [];
    }
  }

  String _normalizedPaymentMode(String mode) =>
      _paymentModes.contains(mode) ? mode : _paymentModes.first;

  String _allocationTextFor(
    List<PaymentAllocation> allocations,
    String invoiceId,
  ) {
    for (final a in allocations) {
      if (a.invoiceId == invoiceId && a.amountApplied > 0) {
        return a.amountApplied.toStringAsFixed(2);
      }
    }
    return '';
  }

  PaymentAllocation _allocationFor(
    List<PaymentAllocation> allocations,
    OpenInvoice inv,
  ) {
    for (final a in allocations) {
      if (a.invoiceId == inv.invoiceId) return a;
    }
    return PaymentAllocation(
      invoiceId: inv.invoiceId,
      invoiceNumber: inv.invoiceNumber,
      amountApplied: 0.0,
    );
  }

  void _setControllerText(TextEditingController ctrl, String text) {
    if (ctrl.text == text) return;
    _syncingControllers = true;
    ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncingControllers = false;
  }

  bool _areAllocationsValid(ReceiptState state) {
    if (state.editingCustomer == null) return false;
    final openInvoices = _safeOpenInvoices(state.editingCustomer!.id);
    double totalAllocated = 0.0;
    for (final alloc in state.editingAllocations) {
      if (alloc.amountApplied < 0) return false;
      OpenInvoice? inv;
      for (final i in openInvoices) {
        if (i.invoiceId == alloc.invoiceId) {
          inv = i;
          break;
        }
      }
      if (inv == null || alloc.amountApplied > inv.balance) {
        return false;
      }
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
    if (_syncingControllers) return;

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

  void _disposeAllocationControllers() {
    for (final ctrl in _allocationControllers.values) {
      ctrl.dispose();
    }
    _allocationControllers.clear();
    for (final node in _allocationFocusNodes.values) {
      node.dispose();
    }
    _allocationFocusNodes.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final readOnly = widget.readOnly;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: BlocBuilder<ReceiptBloc, ReceiptState>(
          buildWhen: (p, c) => p.isEditingNew != c.isEditingNew,
          builder: (_, state) {
            if (readOnly) return const Text('View Receipt');
            return Text(state.isEditingNew ? 'New Receipt' : 'Edit Receipt');
          },
        ),
      ),
      body: SafeArea(
        child: BlocConsumer<ReceiptBloc, ReceiptState>(
          listenWhen: (p, c) =>
              p.successMessage != c.successMessage ||
              p.errorMessage != c.errorMessage ||
              p.editingCustomer?.id != c.editingCustomer?.id ||
              p.editingAmount != c.editingAmount ||
              p.editingReferenceNumber != c.editingReferenceNumber ||
              p.editingAllocations != c.editingAllocations,
          listener: (context, state) {
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context.read<ReceiptBloc>().add(ClearReceiptMessages());
              Navigator.pop(context);
              return;
            }
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context.read<ReceiptBloc>().add(ClearReceiptMessages());
            }

            // Clear allocation controllers if customer changed
            if (state.editingCustomer?.id != _lastCustomerId) {
              _lastCustomerId = state.editingCustomer?.id;
              _disposeAllocationControllers();
            }

            // Sync amount controller only when unfocused (don't fight typing)
            final amountText = state.editingAmount > 0
                ? state.editingAmount.toStringAsFixed(2)
                : '';
            if (_amountController.text != amountText &&
                !_amountFocusNode.hasFocus) {
              _setControllerText(_amountController, amountText);
            }

            // Sync reference controller
            if (_referenceController.text != state.editingReferenceNumber &&
                !_referenceFocusNode.hasFocus) {
              _setControllerText(
                _referenceController,
                state.editingReferenceNumber,
              );
            }

            // Sync allocation controllers (edit mode only, skip focused rows)
            if (!readOnly && state.editingCustomer != null) {
              final openInvoices = _safeOpenInvoices(
                state.editingCustomer!.id,
              );
              for (final inv in openInvoices) {
                final expectedText = _allocationTextFor(
                  state.editingAllocations,
                  inv.invoiceId,
                );
                final ctrl = _allocationControllers.putIfAbsent(
                  inv.invoiceId,
                  () => TextEditingController(text: expectedText),
                );
                _allocationFocusNodes.putIfAbsent(
                  inv.invoiceId,
                  () => FocusNode(),
                );
                final hasFocus =
                    _allocationFocusNodes[inv.invoiceId]?.hasFocus ?? false;
                if (ctrl.text != expectedText && !hasFocus) {
                  _setControllerText(ctrl, expectedText);
                }
              }
            }
          },
          builder: (context, state) {
            final date = state.editingDate ?? DateTime.now();
            final customer = state.editingCustomer;
            final cs = context.org.currencySymbol;
            final paymentMode = _normalizedPaymentMode(
              state.editingPaymentMode,
            );

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
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          // Customer selector
                          Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: (!readOnly && state.isEditingNew)
                                  ? () =>
                                        _showCustomerSelector(context, isDark)
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
                                                    : AppTheme
                                                          .lightTextSecondary,
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
                                    if (!readOnly && state.isEditingNew)
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

                          // Receipt date (system-set; not editable)
                          Card(
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
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Amount field — controller owned by State, not recreated
                          TextFormField(
                            controller: _amountController,
                            focusNode: _amountFocusNode,
                            readOnly: readOnly,
                            enabled: !readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: readOnly
                                ? null
                                : (v) {
                                    if (_syncingControllers) return;
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

                          // Payment mode — stable key + clamped value so rebuilds
                          // never hit DropdownButton's "exactly one item" assert.
                          DropdownButtonFormField<String>(
                            key: ValueKey('receipt_payment_mode_$paymentMode'),
                            initialValue: paymentMode,
                            decoration: const InputDecoration(
                              labelText: 'Payment Mode',
                              prefixIcon: Icon(
                                Icons.payment_outlined,
                                color: AppTheme.primaryIndigo,
                              ),
                            ),
                            items: _paymentModes
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                            onChanged: readOnly
                                ? null
                                : (v) {
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
                            readOnly: readOnly,
                            enabled: !readOnly,
                            onChanged: readOnly
                                ? null
                                : (v) {
                                    if (_syncingControllers) return;
                                    context.read<ReceiptBloc>().add(
                                      SetEditingReference(v),
                                    );
                                  },
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

                          // Allocations — view mode shows saved rows only
                          if (readOnly &&
                              state.editingAllocations.isNotEmpty) ...[
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
                            const SizedBox(height: 8),
                            ...state.editingAllocations.map((alloc) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          alloc.invoiceNumber,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '$cs${alloc.amountApplied.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: AppTheme.successEmerald,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 16),
                          ],

                          // Allocations list (edit mode)
                          if (!readOnly && customer != null)
                            _buildEditAllocations(
                              context,
                              state: state,
                              customerId: customer.id,
                              cs: cs,
                              isDark: isDark,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom save bar — compact when keyboard is open so the form
                // does not collapse to a blank strip.
                if (!keyboardOpen || readOnly)
                  _buildBottomBar(
                    context,
                    state: state,
                    customer: customer,
                    date: date,
                    cs: cs,
                    isDark: isDark,
                    readOnly: readOnly,
                    compact: keyboardOpen,
                  )
                else
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SizedBox(
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'SAVE  $cs${state.editingAmount.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEditAllocations(
    BuildContext context, {
    required ReceiptState state,
    required String customerId,
    required String cs,
    required bool isDark,
  }) {
    final openInvoices = _safeOpenInvoices(customerId);
    if (openInvoices.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalAllocated = state.editingAllocations.fold(
      0.0,
      (sum, a) => sum + a.amountApplied,
    );
    final excessAmount = state.editingAmount - totalAllocated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            Flexible(
              child: Text(
                'Allocated: $cs${totalAllocated.toStringAsFixed(2)} / $cs${state.editingAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: totalAllocated > state.editingAmount + 0.005
                      ? AppTheme.errorRose
                      : AppTheme.successEmerald,
                ),
                textAlign: TextAlign.end,
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
        if (totalAllocated > state.editingAmount + 0.005) ...[
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
        ...openInvoices.map((inv) {
          final expectedText = _allocationTextFor(
            state.editingAllocations,
            inv.invoiceId,
          );
          final ctrl = _allocationControllers.putIfAbsent(
            inv.invoiceId,
            () => TextEditingController(text: expectedText),
          );
          final focusNode = _allocationFocusNodes.putIfAbsent(
            inv.invoiceId,
            () => FocusNode(),
          );
          final allocation = _allocationFor(state.editingAllocations, inv);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inv.invoiceNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Date: ${_dateFormat.format(inv.date)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                        Text(
                          'Outstanding: $cs${inv.balance.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.end,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        prefixText: cs,
                        hintText: '0.00',
                        errorText: allocation.amountApplied > inv.balance
                            ? 'Exceeds balance'
                            : null,
                        errorMaxLines: 1,
                        isDense: true,
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
        }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBottomBar(
    BuildContext context, {
    required ReceiptState state,
    required Customer? customer,
    required DateTime date,
    required String cs,
    required bool isDark,
    required bool readOnly,
    required bool compact,
  }) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 20),
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
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
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
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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
                  onPressed: readOnly
                      ? () => Navigator.pop(context)
                      : (customer == null ||
                            state.editingAmount <= 0 ||
                            state.isLoading ||
                            !_areAllocationsValid(state))
                      ? null
                      : () => context.read<ReceiptBloc>().add(SaveReceipt()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successEmerald,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    readOnly ? 'CLOSE' : 'SAVE RECEIPT',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              if (!state.isEditingNew && !compact) ...[
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
    );
  }
}
