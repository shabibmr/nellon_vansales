import 'package:equatable/equatable.dart';

class ReportState<T> extends Equatable {
  final bool isLoading;
  final List<T> rows;
  final DateTime? startDate;
  final DateTime? endDate;
  final Object? sortField;
  final bool sortAscending;
  final String? error;
  final bool isLiveData;

  const ReportState({
    required this.isLoading,
    required this.rows,
    this.startDate,
    this.endDate,
    this.sortField,
    required this.sortAscending,
    this.error,
    this.isLiveData = false,
  });

  ReportState<T> copyWith({
    bool? isLoading,
    List<T>? rows,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    Object? Function()? sortField,
    bool? sortAscending,
    String? Function()? error,
    bool? isLiveData,
  }) {
    return ReportState<T>(
      isLoading: isLoading ?? this.isLoading,
      rows: rows ?? this.rows,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      sortField: sortField != null ? sortField() : this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
      error: error != null ? error() : this.error,
      isLiveData: isLiveData ?? this.isLiveData,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        rows,
        startDate,
        endDate,
        sortField,
        sortAscending,
        error,
        isLiveData,
      ];
}
