import 'package:equatable/equatable.dart';

abstract class ReportEvent extends Equatable {
  const ReportEvent();

  @override
  List<Object?> get props => [];
}

class RefreshReport extends ReportEvent {
  const RefreshReport();
}

class SetDateRange extends ReportEvent {
  final DateTime? startDate;
  final DateTime? endDate;

  const SetDateRange(this.startDate, this.endDate);

  @override
  List<Object?> get props => [startDate, endDate];
}

class SetSort extends ReportEvent {
  final Object field;
  final bool? ascending;

  const SetSort(this.field, {this.ascending});

  @override
  List<Object?> get props => [field, ascending];
}
