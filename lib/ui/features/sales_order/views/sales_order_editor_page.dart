import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../bloc/sales_order_editor_bloc.dart';
import '../bloc/sales_order_editor_event.dart';
import '../bloc/sales_order_editor_state.dart';
import '../widgets/sales_order_editor_form.dart';

class SalesOrderEditorPage extends StatefulWidget {
  /// When true, opens in view mode. The user can switch to edit via the
  /// app-bar Edit action (sales orders are the only editable vouchers),
  /// unless the order is already converted to an invoice.
  final bool readOnly;

  const SalesOrderEditorPage({super.key, this.readOnly = false});

  /// Opens the editor with a route-scoped [SalesOrderEditorBloc].
  ///
  /// - [order] null → new order; optional [prefillCustomer] for dashboard flow
  /// - [order] set → open existing (Zoho re-read for saved, local for pending)
  static Future<T?> open<T>(
    BuildContext context, {
    SalesOrder? order,
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
            final bloc = SalesOrderEditorBloc(
              salesRepository: salesRepo,
              syncRepository: syncRepo,
              documentNumberService: docNumbers,
            );
            if (order != null) {
              bloc.add(OpenSalesOrder(order));
            } else {
              bloc.add(StartNewSalesOrder(customer: prefillCustomer));
            }
            return bloc;
          },
          child: SalesOrderEditorPage(readOnly: readOnly),
        ),
      ),
    );
  }

  @override
  State<SalesOrderEditorPage> createState() => _SalesOrderEditorPageState();
}

class _SalesOrderEditorPageState extends State<SalesOrderEditorPage> {
  late TextEditingController _notesController;

  /// Local view-mode flag so the Edit button can unlock the form without
  /// rebuilding the route.
  late bool _isViewMode;

  @override
  void initState() {
    super.initState();
    _isViewMode = widget.readOnly;
    final blocState = context.read<SalesOrderEditorBloc>().state;
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
        title: BlocBuilder<SalesOrderEditorBloc, SalesOrderEditorState>(
          buildWhen: (previous, current) =>
              previous.isEditingNew != current.isEditingNew ||
              previous.isConverted != current.isConverted,
          builder: (context, state) {
            final readOnly = _isViewMode || state.isConverted;
            if (readOnly) return const Text('View Sales Order');
            return Text(
              state.isEditingNew ? 'New Sales Order' : 'Edit Sales Order',
            );
          },
        ),
        actions: [
          BlocBuilder<SalesOrderEditorBloc, SalesOrderEditorState>(
            buildWhen: (p, c) => p.isConverted != c.isConverted,
            builder: (context, state) {
              if (!_isViewMode || state.isConverted) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => setState(() => _isViewMode = false),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<SalesOrderEditorBloc, SalesOrderEditorState>(
          listenWhen: (previous, current) =>
              previous.successMessage != current.successMessage ||
              previous.errorMessage != current.errorMessage ||
              previous.editingNotes != current.editingNotes,
          listener: (context, state) {
            if (_notesController.text != state.editingNotes) {
              _notesController.text = state.editingNotes;
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<SalesOrderEditorBloc>()
                  .add(const ClearSalesOrderEditorMessages());
              Navigator.pop(context);
            } else if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<SalesOrderEditorBloc>()
                  .add(const ClearSalesOrderEditorMessages());
            }
          },
          builder: (context, state) {
            final readOnly = _isViewMode || state.isConverted;

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
                title: "Couldn't load this sales order",
                message: state.editorError,
                action: FilledButton.icon(
                  onPressed: () => context
                      .read<SalesOrderEditorBloc>()
                      .add(const RetryLoadSalesOrder()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                ),
              );
            }

            return SalesOrderEditorForm(
              state: state,
              readOnly: readOnly,
              notesController: _notesController,
            );
          },
        ),
      ),
    );
  }
}
