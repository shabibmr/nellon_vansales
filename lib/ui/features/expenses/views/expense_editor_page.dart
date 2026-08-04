import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/empty_state.dart';
import '../bloc/expense_editor_bloc.dart';
import '../bloc/expense_editor_event.dart';
import '../bloc/expense_editor_state.dart';
import '../widgets/expense_editor_form.dart';

class ExpenseEditorPage extends StatefulWidget {
  /// When true, opens in view mode.
  final bool readOnly;

  const ExpenseEditorPage({super.key, this.readOnly = false});

  /// Opens the editor with a route-scoped [ExpenseEditorBloc].
  static Future<T?> open<T>(
    BuildContext context, {
    ExpenseEntry? expense,
    bool readOnly = false,
  }) {
    final salesRepo = context.read<SalesRepository>();
    final syncRepo = context.read<SyncRepository>();

    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) {
            final bloc = ExpenseEditorBloc(
              salesRepository: salesRepo,
              syncRepository: syncRepo,
            );
            if (expense != null) {
              bloc.add(OpenExpenseEntry(expense));
            } else {
              bloc.add(const StartNewExpense());
            }
            return bloc;
          },
          child: ExpenseEditorPage(readOnly: readOnly),
        ),
      ),
    );
  }

  @override
  State<ExpenseEditorPage> createState() => _ExpenseEditorPageState();
}

class _ExpenseEditorPageState extends State<ExpenseEditorPage> {
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
        title: BlocBuilder<ExpenseEditorBloc, ExpenseEditorState>(
          buildWhen: (previous, current) =>
              previous.isEditingNew != current.isEditingNew,
          builder: (context, state) {
            final readOnly = _isViewMode;
            if (readOnly) return const Text('View Expense');
            return Text(
              state.isEditingNew ? 'New Expense' : 'Edit Expense',
            );
          },
        ),
      ),
      body: SafeArea(
        child: BlocConsumer<ExpenseEditorBloc, ExpenseEditorState>(
          listenWhen: (previous, current) =>
              previous.successMessage != current.successMessage ||
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<ExpenseEditorBloc>()
                  .add(const ClearExpenseEditorMessages());
              Navigator.pop(context);
            } else if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<ExpenseEditorBloc>()
                  .add(const ClearExpenseEditorMessages());
            }
          },
          builder: (context, state) {
            final readOnly = _isViewMode;

            if (state.isEditorLoading) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.errorRose,
                ),
              );
            }
            if (state.editorError != null) {
              return EmptyState(
                icon: Icons.cloud_off,
                title: "Couldn't load this expense entry",
                message: state.editorError,
                action: FilledButton.icon(
                  onPressed: () => context
                      .read<ExpenseEditorBloc>()
                      .add(const RetryLoadExpenseEntry()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                ),
              );
            }

            return ExpenseEditorForm(
              state: state,
              readOnly: readOnly,
            );
          },
        ),
      ),
    );
  }
}
