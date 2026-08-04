import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/empty_state.dart';
import '../bloc/sales_return_editor_bloc.dart';
import '../bloc/sales_return_editor_event.dart';
import '../bloc/sales_return_editor_state.dart';
import '../widgets/sales_return_editor_form.dart';

class SalesReturnEditorPage extends StatefulWidget {
  /// When true, opens in view mode.
  final bool readOnly;

  const SalesReturnEditorPage({super.key, this.readOnly = false});

  /// Opens the editor with a route-scoped [SalesReturnEditorBloc].
  static Future<T?> open<T>(
    BuildContext context, {
    SalesReturn? salesReturn,
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
            final bloc = SalesReturnEditorBloc(
              salesRepository: salesRepo,
              syncRepository: syncRepo,
              documentNumberService: docNumbers,
            );
            if (salesReturn != null) {
              bloc.add(OpenSalesReturn(salesReturn));
            } else {
              bloc.add(StartNewReturn(customer: prefillCustomer));
            }
            return bloc;
          },
          child: SalesReturnEditorPage(readOnly: readOnly),
        ),
      ),
    );
  }

  @override
  State<SalesReturnEditorPage> createState() => _SalesReturnEditorPageState();
}

class _SalesReturnEditorPageState extends State<SalesReturnEditorPage> {
  late TextEditingController _reasonController;
  late bool _isViewMode;

  @override
  void initState() {
    super.initState();
    _isViewMode = widget.readOnly;
    final blocState = context.read<SalesReturnEditorBloc>().state;
    _reasonController = TextEditingController(text: blocState.editingReason);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<SalesReturnEditorBloc, SalesReturnEditorState>(
          buildWhen: (previous, current) =>
              previous.isEditingNew != current.isEditingNew,
          builder: (context, state) {
            final readOnly = _isViewMode;
            if (readOnly) return const Text('View Sales Return');
            return Text(
              state.isEditingNew ? 'New Sales Return' : 'Edit Sales Return',
            );
          },
        ),
      ),
      body: SafeArea(
        child: BlocConsumer<SalesReturnEditorBloc, SalesReturnEditorState>(
          listenWhen: (previous, current) =>
              previous.successMessage != current.successMessage ||
              previous.errorMessage != current.errorMessage ||
              previous.editingReason != current.editingReason,
          listener: (context, state) {
            if (_reasonController.text != state.editingReason) {
              _reasonController.text = state.editingReason;
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<SalesReturnEditorBloc>()
                  .add(const ClearSalesReturnEditorMessages());
              Navigator.pop(context);
            } else if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<SalesReturnEditorBloc>()
                  .add(const ClearSalesReturnEditorMessages());
            }
          },
          builder: (context, state) {
            final readOnly = _isViewMode;

            if (state.isEditorLoading) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.warningAmber,
                ),
              );
            }
            if (state.editorError != null) {
              return EmptyState(
                icon: Icons.cloud_off,
                title: "Couldn't load this sales return",
                message: state.editorError,
                action: FilledButton.icon(
                  onPressed: () => context
                      .read<SalesReturnEditorBloc>()
                      .add(const RetryLoadSalesReturn()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                ),
              );
            }

            return SalesReturnEditorForm(
              state: state,
              readOnly: readOnly,
              reasonController: _reasonController,
            );
          },
        ),
      ),
    );
  }
}
