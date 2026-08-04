import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/empty_state.dart';
import '../bloc/receipt_editor_bloc.dart';
import '../bloc/receipt_editor_event.dart';
import '../bloc/receipt_editor_state.dart';
import '../widgets/receipt_editor_form.dart';

class ReceiptEditorPage extends StatefulWidget {
  /// When true, opens in view mode.
  final bool readOnly;

  const ReceiptEditorPage({super.key, this.readOnly = false});

  /// Opens the editor with a route-scoped [ReceiptEditorBloc].
  static Future<T?> open<T>(
    BuildContext context, {
    ReceiptVoucher? receipt,
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
            final bloc = ReceiptEditorBloc(
              salesRepository: salesRepo,
              syncRepository: syncRepo,
              documentNumberService: docNumbers,
            );
            if (receipt != null) {
              bloc.add(OpenReceiptVoucher(receipt));
            } else {
              bloc.add(StartNewReceipt(customer: prefillCustomer));
            }
            return bloc;
          },
          child: ReceiptEditorPage(readOnly: readOnly),
        ),
      ),
    );
  }

  @override
  State<ReceiptEditorPage> createState() => _ReceiptEditorPageState();
}

class _ReceiptEditorPageState extends State<ReceiptEditorPage> {
  late bool _isViewMode;

  @override
  void initState() {
    super.initState();
    _isViewMode = widget.readOnly;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ReceiptEditorBloc, ReceiptEditorState>(
          buildWhen: (previous, current) =>
              previous.isEditingNew != current.isEditingNew,
          builder: (context, state) {
            final readOnly = _isViewMode;
            if (readOnly) return const Text('View Receipt');
            return Text(
              state.isEditingNew ? 'New Receipt' : 'Edit Receipt',
            );
          },
        ),
      ),
      body: SafeArea(
        child: BlocConsumer<ReceiptEditorBloc, ReceiptEditorState>(
          listenWhen: (previous, current) =>
              previous.successMessage != current.successMessage ||
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<ReceiptEditorBloc>()
                  .add(const ClearReceiptEditorMessages());
              Navigator.pop(context);
            } else if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<ReceiptEditorBloc>()
                  .add(const ClearReceiptEditorMessages());
            }
          },
          builder: (context, state) {
            final readOnly = _isViewMode;

            if (state.isEditorLoading) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.successEmerald,
                ),
              );
            }
            if (state.editorError != null) {
              return EmptyState(
                icon: Icons.cloud_off,
                title: "Couldn't load this receipt voucher",
                message: state.editorError,
                action: FilledButton.icon(
                  onPressed: () => context
                      .read<ReceiptEditorBloc>()
                      .add(const RetryLoadReceiptVoucher()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                ),
              );
            }

            return ReceiptEditorForm(
              state: state,
              readOnly: readOnly,
            );
          },
        ),
      ),
    );
  }
}
