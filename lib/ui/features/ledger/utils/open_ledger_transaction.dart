import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/injection.dart';
import '../../../../domain/models/customer_ledger.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../receipts/bloc/receipt_bloc.dart';
import '../../receipts/views/receipt_editor_page.dart';
import '../../sales_invoice/bloc/sales_invoice_bloc.dart';
import '../../sales_invoice/views/sales_invoice_editor_page.dart';
import '../../sales_return/bloc/sales_return_bloc.dart';
import '../../sales_return/views/sales_return_editor_page.dart';

/// Opens the document for a ledger transaction line in view mode.
///
/// Supported types: `invoice`, `payment`, `credit_note`.
/// Loads from local cache first, then Zoho Books when needed.
Future<void> openLedgerTransaction(
  BuildContext context,
  LedgerTransaction tx,
) async {
  final type = tx.type.toLowerCase().trim();
  final id = tx.transactionId.trim();

  if (id.isEmpty ||
      type == 'opening_balance' ||
      type == 'unknown' ||
      type.isEmpty) {
    if (context.mounted) {
      showErrorSnackBar(context, 'This ledger entry cannot be opened.');
    }
    return;
  }

  if (type != 'invoice' &&
      type != 'payment' &&
      type != 'credit_note' &&
      type != 'debit_note') {
    if (context.mounted) {
      showErrorSnackBar(context, 'Unsupported transaction type: ${tx.type}');
    }
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryIndigo),
              SizedBox(height: 16),
              Text('Loading transaction…'),
            ],
          ),
        ),
      ),
    ),
  );

  var loadingOpen = true;
  void dismissLoading() {
    if (!loadingOpen || !context.mounted) return;
    loadingOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  try {
    final repo = sl<SalesRepository>();

    switch (type) {
      case 'invoice':
      case 'debit_note':
        final invoice = await repo.fetchInvoiceById(id);
        dismissLoading();
        if (!context.mounted) return;
        if (invoice == null) {
          showErrorSnackBar(context, 'Invoice not found.');
          return;
        }
        context.read<SalesInvoiceBloc>().add(StartEditInvoice(invoice));
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SalesInvoiceEditorPage(readOnly: true),
          ),
        );
        break;

      case 'payment':
        final receipt = await repo.fetchReceiptById(id);
        dismissLoading();
        if (!context.mounted) return;
        if (receipt == null) {
          showErrorSnackBar(context, 'Payment receipt not found.');
          return;
        }
        context.read<ReceiptBloc>().add(StartEditReceipt(receipt));
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ReceiptEditorPage(readOnly: true),
          ),
        );
        break;

      case 'credit_note':
        final salesReturn = await repo.fetchSalesReturnById(id);
        dismissLoading();
        if (!context.mounted) return;
        if (salesReturn == null) {
          showErrorSnackBar(context, 'Credit note not found.');
          return;
        }
        context.read<SalesReturnBloc>().add(StartEditReturn(salesReturn));
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SalesReturnEditorPage(readOnly: true),
          ),
        );
        break;
    }
  } catch (e) {
    dismissLoading();
    if (context.mounted) {
      showErrorSnackBar(context, 'Failed to open transaction: $e');
    }
  }
}
