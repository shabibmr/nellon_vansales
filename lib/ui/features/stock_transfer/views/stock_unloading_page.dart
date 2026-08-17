import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/stock_transfer.dart';
import '../../../../domain/repositories/stock_transfer_repository.dart';
import '../bloc/stock_transfer_bloc.dart';
import 'stock_transfer_editor_view.dart';

/// Stock-Unloading editor: returns the van's balance stock from the current
/// location back to the organization's default warehouse at end-of-trip.
/// Pass [existingTransfer] to view/edit an already-created transfer instead
/// of planning a new one.
///
/// Prefer [open] so a fresh [StockTransferBloc] is created for the route
/// and disposed when the page pops.
class StockUnloadingPage extends StatelessWidget {
  final StockTransfer? existingTransfer;

  const StockUnloadingPage({super.key, this.existingTransfer});

  /// Pushes a route-scoped Stock-Unloading editor.
  static Future<T?> open<T>(
    BuildContext context, {
    StockTransfer? existing,
  }) {
    final repo = context.read<StockTransferRepository>();
    return Navigator.push<T>(
      context,
      MaterialPageRoute<T>(
        builder: (_) => BlocProvider(
          create: (_) {
            final bloc = StockTransferBloc(stockTransferRepository: repo);
            if (existing == null) {
              bloc.add(LoadUnloadGrid());
            }
            return bloc;
          },
          child: StockUnloadingPage(existingTransfer: existing),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StockTransferEditorView(
      isLoad: false,
      existingTransfer: existingTransfer,
    );
  }
}
