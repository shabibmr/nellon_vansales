import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/confirm_discard_refresh_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/voucher_refresh_action.dart';
import '../bloc/sales_invoice_editor_bloc.dart';
import '../bloc/sales_invoice_editor_event.dart';
import '../bloc/sales_invoice_editor_state.dart';
import '../widgets/sales_invoice_editor_form.dart';

class SalesInvoiceEditorPage extends StatefulWidget {
  /// When true, opens in view mode.
  final bool readOnly;

  const SalesInvoiceEditorPage({super.key, this.readOnly = false});

  /// Opens the editor with a route-scoped [SalesInvoiceEditorBloc].
  ///
  /// - [invoice] null & [fromOrder] null → new invoice; optional [prefillCustomer]
  /// - [invoice] set → open existing
  /// - [fromOrder] set → prefill from sales order conversion
  static Future<T?> open<T>(
    BuildContext context, {
    SalesInvoice? invoice,
    SalesOrder? fromOrder,
    Customer? prefillCustomer,
    bool readOnly = false,
  }) {
    final salesRepo = context.read<SalesRepository>();
    final syncRepo = context.read<SyncRepository>();
    final docNumbers = sl<DocumentNumberService>();

    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) {
            final bloc = SalesInvoiceEditorBloc(
              salesRepository: salesRepo,
              syncRepository: syncRepo,
              documentNumberService: docNumbers,
            );
            if (invoice != null) {
              bloc.add(OpenSalesInvoice(invoice));
            } else if (fromOrder != null) {
              bloc.add(StartInvoiceFromOrder(fromOrder));
            } else {
              bloc.add(StartNewInvoice(customer: prefillCustomer));
            }
            return bloc;
          },
          child: SalesInvoiceEditorPage(readOnly: readOnly),
        ),
      ),
    );
  }

  @override
  State<SalesInvoiceEditorPage> createState() => _SalesInvoiceEditorPageState();
}

class _SalesInvoiceEditorPageState extends State<SalesInvoiceEditorPage> {
  late TextEditingController _notesController;
  late bool _isViewMode;

  @override
  void initState() {
    super.initState();
    _isViewMode = widget.readOnly;
    final blocState = context.read<SalesInvoiceEditorBloc>().state;
    _notesController = TextEditingController(text: blocState.editingNotes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<SalesInvoiceEditorBloc, SalesInvoiceEditorState>(
          buildWhen: (previous, current) =>
              previous.isEditingNew != current.isEditingNew,
          builder: (context, state) {
            final readOnly = _isViewMode;
            if (readOnly) return const Text('View Sales Invoice');
            return Text(
              state.isEditingNew ? 'New Sales Invoice' : 'Edit Sales Invoice',
            );
          },
        ),
        actions: [
          BlocBuilder<SalesInvoiceEditorBloc, SalesInvoiceEditorState>(
            buildWhen: (p, c) =>
                p.canRefreshFromZoho != c.canRefreshFromZoho ||
                p.isRefreshing != c.isRefreshing,
            builder: (context, state) {
              return VoucherRefreshAction(
                visible: state.canRefreshFromZoho,
                isLoading: state.isRefreshing,
                onPressed: () => _onRefreshPressed(context),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<SalesInvoiceEditorBloc, SalesInvoiceEditorState>(
          listenWhen: (previous, current) =>
              previous.successMessage != current.successMessage ||
              previous.errorMessage != current.errorMessage ||
              previous.infoMessage != current.infoMessage ||
              previous.editingNotes != current.editingNotes,
          listener: (context, state) {
            if (_notesController.text != state.editingNotes) {
              _notesController.text = state.editingNotes;
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<SalesInvoiceEditorBloc>()
                  .add(const ClearSalesInvoiceEditorMessages());
              Navigator.pop(context);
            } else if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<SalesInvoiceEditorBloc>()
                  .add(const ClearSalesInvoiceEditorMessages());
            } else if (state.infoMessage != null) {
              showInfoSnackBar(context, state.infoMessage!);
              context
                  .read<SalesInvoiceEditorBloc>()
                  .add(const ClearSalesInvoiceEditorMessages());
            }
          },
          builder: (context, state) {
            final readOnly = _isViewMode || state.isRefreshing;

            if (state.isEditorLoading) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primaryIndigo,
                ),
              );
            }
            if (state.editorError != null) {
              return EmptyState(
                icon: Icons.cloud_off,
                title: "Couldn't load this sales invoice",
                message: state.editorError,
                action: FilledButton.icon(
                  onPressed: () => context
                      .read<SalesInvoiceEditorBloc>()
                      .add(const RetryLoadSalesInvoice()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                ),
              );
            }

            return SalesInvoiceEditorForm(
              state: state,
              readOnly: readOnly,
              notesController: _notesController,
            );
          },
        ),
      ),
    );
  }

  Future<void> _onRefreshPressed(BuildContext context) async {
    final bloc = context.read<SalesInvoiceEditorBloc>();
    // Notes live in the controller until Save; include them in dirty detection.
    final snapshotNotes = bloc.state.editingInvoice?.notes ?? '';
    final notesDirty =
        _notesController.text.trim() != snapshotNotes.trim();
    final dirty = bloc.state.isFormDirty || notesDirty;
    if (dirty) {
      final ok = await confirmDiscardEditsForRefresh(context);
      if (!ok || !context.mounted) return;
    }
    // Keep BLoC notes in sync for fingerprint / wasDirty consistency.
    bloc.add(UpdateInvoiceNotes(_notesController.text));
    bloc.add(RefreshSalesInvoiceFromZoho(forceDirty: dirty));
  }
}
