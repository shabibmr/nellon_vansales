import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/stock_transfer.dart';
import '../../../../domain/repositories/stock_transfer_repository.dart';
import '../bloc/stock_transfer_bloc.dart';
import 'stock_transfer_editor_view.dart';

/// Issue-to-Van editor: loads stock from the organization's default
/// warehouse into the current van location. Pass [existingTransfer] to
/// view/edit an already-created transfer instead of planning a new one.
///
/// Prefer [open] so a fresh [StockTransferBloc] is created for the route
/// and disposed when the page pops.
class IssueToVanPage extends StatelessWidget {
  final StockTransfer? existingTransfer;

  const IssueToVanPage({super.key, this.existingTransfer});

  /// Pushes a route-scoped Issue-to-Van editor.
  ///
  /// [existing] re-opens a saved transfer. [demand] pre-fills Col 2 from
  /// shipment-order quantities. Omit both for a blank planning grid.
  static Future<T?> open<T>(
    BuildContext context, {
    StockTransfer? existing,
    Map<String, double>? demand,
  }) {
    final repo = context.read<StockTransferRepository>();
    return Navigator.push<T>(
      context,
      MaterialPageRoute<T>(
        builder: (_) => BlocProvider(
          create: (_) {
            final bloc = StockTransferBloc(stockTransferRepository: repo);
            if (existing == null) {
              if (demand != null) {
                bloc.add(LoadIssueGridWithDemand(demand));
              } else {
                bloc.add(LoadIssueGrid());
              }
            }
            return bloc;
          },
          child: IssueToVanPage(existingTransfer: existing),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StockTransferEditorView(
      isLoad: true,
      existingTransfer: existingTransfer,
    );
  }
}
