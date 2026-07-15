import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/snackbars.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_state.dart';

/// Shared chrome for report pages: provides [ReportBloc], surfaces fetch errors
/// via snackbar, and rebuilds the body from [ReportState].
///
/// Per-page aggregation / columns / sort enums stay outside this host.
class ReportBlocHost<T> extends StatelessWidget {
  final ReportBloc<T> Function(BuildContext context) create;
  final Widget Function(BuildContext context, ReportState<T> state) builder;
  final String errorPrefix;

  const ReportBlocHost({
    super.key,
    required this.create,
    required this.builder,
    this.errorPrefix = 'Could not load report from Zoho',
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<T>>(
      create: create,
      child: BlocListener<ReportBloc<T>, ReportState<T>>(
        listenWhen: (prev, curr) =>
            curr.error != null && prev.error != curr.error,
        listener: (context, state) {
          showErrorSnackBar(context, '$errorPrefix: ${state.error}');
        },
        child: BlocBuilder<ReportBloc<T>, ReportState<T>>(
          builder: builder,
        ),
      ),
    );
  }
}
