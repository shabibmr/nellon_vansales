import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/date_picker.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';

/// Shared date-range picker action for report pages backed by [ReportBloc].
///
/// Opens the themed date picker seeded with the current start/end bound and
/// dispatches [SetDateRange]. Replaces the identical `_pickDate` method that
/// each report page used to define locally.
Future<void> pickReportDate<T>(BuildContext context, bool isStart) async {
  final bloc = context.read<ReportBloc<T>>();
  final current = isStart ? bloc.state.startDate : bloc.state.endDate;
  final picked = await showThemedDatePicker(context, initialDate: current);
  if (picked == null) return;
  bloc.add(
    isStart
        ? SetDateRange(picked, bloc.state.endDate)
        : SetDateRange(bloc.state.startDate, picked),
  );
}
